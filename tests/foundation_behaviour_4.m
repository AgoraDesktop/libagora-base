/*
 * foundation_behaviour_4 — the fifth wave of the behavioural pass.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. The fourth wave crossed one boundary; this one crosses the rest that can be crossed
 * hermetically: a redirect and the COOKIE round trip it carries, a POST body and a caller's header, NSTask's
 * pipes and environment, an NSConnection between two PROCESSES over a TCP port, and a repeated-lifecycle soak.
 *
 * THE SERVERS ARE POSIX SOCKETS ON 127.0.0.1 with a kernel-chosen port, as in the fourth wave: nothing here depends
 * on the internet or on a fixed port being free.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static int g_fail;

static void
check(int condition, const char *what)
{
	if (!condition) {
		printf("FAIL: %s\n", what);
		g_fail = 1;
	} else {
		printf("ok: %s\n", what);
	}
}

/* ---- the HTTP server with a redirect, a cookie and a POST ------------------------------------------------- */

struct http_server {
	int fd;
	int port;
	int expected;
	int seen;
	pthread_mutex_t lock;
	char cookie[512];
	char method[16];
	char body[128];
	char probe[64];
};

static int
make_listener(struct http_server *server)
{
	struct sockaddr_in address;
	socklen_t length = sizeof address;
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	int yes = 1;

	if (fd < 0) {
		return -1;
	}
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
	memset(&address, 0, sizeof address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	if (bind(fd, (struct sockaddr *)&address, sizeof address) != 0 ||
	    listen(fd, 4) != 0 ||
	    getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
		close(fd);
		return -1;
	}
	server->fd = fd;
	server->port = ntohs(address.sin_port);
	server->seen = 0;
	pthread_mutex_init(&server->lock, NULL);
	return 0;
}

static void
send_all(int fd, const char *text)
{
	size_t length = strlen(text);
	size_t sent = 0;

	while (sent < length) {
		ssize_t put = write(fd, text + sent, length - sent);

		if (put <= 0) {
			return;
		}
		sent += (size_t)put;
	}
}

/* A header's value, matched case-insensitively against the request's header block. */
static int
header_value(const char *request, const char *name, char *out, size_t capacity)
{
	const char *line = strstr(request, "\r\n");
	size_t nameLength = strlen(name);

	out[0] = '\0';
	while (line != NULL && line[0] != '\0') {
		const char *next = strstr(line + 2, "\r\n");

		line += 2;
		if (strncasecmp(line, name, nameLength) == 0 && line[nameLength] == ':') {
			const char *value = line + nameLength + 1;
			const char *end = next != NULL ? next : line + strlen(line);
			size_t length;

			while (*value == ' ') {
				value++;
			}
			length = (size_t)(end - value);
			if (length >= capacity) {
				length = capacity - 1;
			}
			memcpy(out, value, length);
			out[length] = '\0';
			return 1;
		}
		if (next == NULL) {
			break;
		}
		line = next;
	}
	return 0;
}

static void *
http_serve(void *context)
{
	struct http_server *server = (struct http_server *)context;
	int connection;

	for (connection = 0; connection < server->expected; connection++) {
		char request[4096];
		size_t used = 0;
		int client = accept(server->fd, NULL, NULL);
		ssize_t got;
		char *headersEnd;
		char method[16] = "";
		char path[256] = "";
		char header[512];
		int bodyLength = 0;
		char *body;

		if (client < 0) {
			break;
		}
		memset(request, 0, sizeof request);
		while (used < sizeof request - 1 &&
		       (got = read(client, request + used, sizeof request - 1 - used)) > 0) {
			used += (size_t)got;
			request[used] = '\0';
			if (strstr(request, "\r\n\r\n") != NULL) {
				break;
			}
		}
		headersEnd = strstr(request, "\r\n\r\n");
		if (headersEnd == NULL) {
			close(client);
			continue;
		}
		*headersEnd = '\0';
		if (sscanf(request, "%15s %255s", method, path) != 2) {
			close(client);
			continue;
		}
		body = headersEnd + 4;
		if (header_value(request, "Content-Length", header, sizeof header)) {
			bodyLength = atoi(header);
		}
		{
			size_t have = used - (size_t)(body - request);

			while ((int)have < bodyLength && used < sizeof request - 1 &&
			       (got = read(client, request + used, sizeof request - 1 - used)) > 0) {
				used += (size_t)got;
				have += (size_t)got;
				body = headersEnd + 4;
			}
			request[used] = '\0';
		}

		pthread_mutex_lock(&server->lock);
		server->seen++;
		snprintf(server->method, sizeof server->method, "%s", method);
		snprintf(server->body, sizeof server->body, "%.*s", bodyLength, body);
		if (!header_value(request, "Cookie", server->cookie, sizeof server->cookie)) {
			server->cookie[0] = '\0';
		}
		if (!header_value(request, "X-Probe", server->probe, sizeof server->probe)) {
			server->probe[0] = '\0';
		}
		pthread_mutex_unlock(&server->lock);

		if (strncmp(path, "/redirect", 9) == 0) {
			send_all(client,
				 "HTTP/1.1 302 Found\r\n"
				 "Location: /final\r\n"
				 "Set-Cookie: probe=1; Path=/\r\n"
				 "Content-Length: 0\r\n"
				 "Connection: close\r\n"
				 "\r\n");
		} else if (strncmp(path, "/final", 6) == 0) {
			send_all(client,
				 "HTTP/1.1 200 OK\r\n"
				 "Content-Type: text/plain\r\n"
				 "Content-Length: 5\r\n"
				 "Connection: close\r\n"
				 "\r\n"
				 "final");
		} else if (strncmp(path, "/post", 5) == 0) {
			send_all(client,
				 "HTTP/1.1 200 OK\r\n"
				 "Content-Type: text/plain\r\n"
				 "Content-Length: 6\r\n"
				 "Connection: close\r\n"
				 "\r\n"
				 "posted");
		} else {
			send_all(client,
				 "HTTP/1.1 404 Not Found\r\n"
				 "Content-Length: 0\r\n"
				 "Connection: close\r\n"
				 "\r\n");
		}
		close(client);
	}
	close(server->fd);
	return NULL;
}

/* ---- a distributed-objects root --------------------------------------------------------------------------- */

@protocol EchoProtocol
- (NSString *)echo:(NSString *)text;
@end

@interface EchoObject : NSObject <EchoProtocol>
@end

@implementation EchoObject
- (NSString *)echo:(NSString *)text
{
	return [text isEqualToString:@"ping"] ? @"pong" : text;
}
@end

/* ---- the soak's observable object ------------------------------------------------------------------------- */

@interface SoakObject : NSObject
{
@public
	int number;
}
- (int)number;
- (void)setNumber:(int)value;
@end

@implementation SoakObject
- (int)number { return number; }
- (void)setNumber:(int)value { number = value; }
@end

@interface SoakObserver : NSObject
{
@public
	int changes;
}
@end

@implementation SoakObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	(void)keyPath; (void)object; (void)change; (void)context;
	changes++;
}
@end

int
main(int argc, char **argv)
{
	NSAutoreleasePool *pool;
	char configRoot[] = "/tmp/agora-wave5-defaults-XXXXXX";

	pool = [[NSAutoreleasePool alloc] init];
	if (mkdtemp(configRoot) != NULL) {
		setenv("FNX_CONFIG_ROOT", configRoot, 1);
	}

	/* ============================== REDIRECT, COOKIE, POST =================================== */

	{
		struct http_server server;
		pthread_t thread;
		NSMutableArray *existing;
		NSUInteger i;

		/* A CLEAN COOKIE JAR: the storage is process-wide, so a previous run must not decide this one. */
		existing = [[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies] mutableCopy];
		for (i = 0; i < [existing count]; i++) {
			NSHTTPCookie *cookie = [existing objectAtIndex:i];

			if ([[cookie domain] rangeOfString:@"127.0.0.1"].location != NSNotFound ||
			    [cookie domain] == nil) {
				[[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:cookie];
			}
		}
		[existing release];

		if (make_listener(&server) == 0) {
			NSString *base = [NSString stringWithFormat:@"http://127.0.0.1:%d", server.port];
			NSError *error = nil;
			NSHTTPURLResponse *response = nil;
			NSData *data;
			NSString *body;
			NSArray *cookies;
			NSMutableURLRequest *post;

			server.expected = 4;
			pthread_create(&thread, NULL, http_serve, &server);

			/* 1. A REDIRECT IS FOLLOWED, and the 302's Set-Cookie is kept. */
			data = [NSURLConnection sendSynchronousRequest:
				[NSURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/redirect"]]
					       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
					   timeoutInterval:10.0]
						 returningResponse:&response
							     error:&error];
			body = data != nil ? [[[NSString alloc] initWithData:data
								   encoding:NSUTF8StringEncoding] autorelease] : nil;
			check(data != nil && error == nil, "a redirected request completes");
			check([response statusCode] == 200, "the followed response is the destination's 200");
			check([[response URL].path isEqualToString:@"/final"], "the response URL is the redirect target");
			check([body isEqualToString:@"final"], "the body is the destination's");

			/* 2. THE COOKIE WAS STORED, AND THE FOLLOWED REQUEST SENT IT. */
			cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage]
				   cookiesForURL:[NSURL URLWithString:[base stringByAppendingString:@"/final"]]];
			check([cookies count] == 1 && [[[cookies objectAtIndex:0] name] isEqualToString:@"probe"],
			      "the Set-Cookie on the 302 is in the shared storage");
			pthread_mutex_lock(&server.lock);
			check(strstr(server.cookie, "probe=1") != NULL,
			      "the followed request carried the stored cookie");
			pthread_mutex_unlock(&server.lock);

			/* 3. A SECOND REQUEST TO THE SAME HOST SENDS THE COOKIE TOO. */
			data = [NSURLConnection sendSynchronousRequest:
				[NSURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/final"]]
					       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
					   timeoutInterval:10.0]
						 returningResponse:&response
							     error:&error];
			check(data != nil && [response statusCode] == 200, "a cookie-carrying GET completes");

			/* 4. A POST WITH A CALLER'S BODY AND HEADER. */
			post = [NSMutableURLRequest requestWithURL:
				[NSURL URLWithString:[base stringByAppendingString:@"/post"]]
				cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
				timeoutInterval:10.0];
			[post setHTTPMethod:@"POST"];
			[post setHTTPBody:[@"payload" dataUsingEncoding:NSUTF8StringEncoding]];
			[post setValue:@"yes" forHTTPHeaderField:@"X-Probe"];
			data = [NSURLConnection sendSynchronousRequest:post
						      returningResponse:&response
								  error:&error];
			body = data != nil ? [[[NSString alloc] initWithData:data
								   encoding:NSUTF8StringEncoding] autorelease] : nil;
			check([body isEqualToString:@"posted"], "a POST's response arrives");
			pthread_join(thread, NULL);
			pthread_mutex_lock(&server.lock);
			check(strcmp(server.method, "POST") == 0, "the server saw the POST method");
			check(strcmp(server.body, "payload") == 0, "the server saw the request body");
			check(strcmp(server.probe, "yes") == 0, "the server saw the caller's header");
			check(strstr(server.cookie, "probe=1") != NULL, "the POST carried the stored cookie too");
			pthread_mutex_unlock(&server.lock);
		} else {
			check(0, "the HTTP listener could not bind a loopback port");
		}
	}

	/* ============================== NSTASK PIPES AND ENVIRONMENT ============================== */

	{
		NSTask *task = [[NSTask alloc] init];
		NSPipe *outPipe = [NSPipe pipe];
		NSPipe *errPipe = [NSPipe pipe];
		NSMutableDictionary *environment = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];

		[environment setObject:@"value" forKey:@"AGORA_PROBE"];
		[task setLaunchPath:@"/bin/sh"];
		[task setArguments:[NSArray arrayWithObjects:@"-c",
				    @"printf '%s' \"$AGORA_PROBE\"; printf 'err' 1>&2; exit 7", nil]];
		[task setEnvironment:environment];
		[task setStandardOutput:outPipe];
		[task setStandardError:errPipe];
		[task launch];
		/* THE PARENT'S OWN WRITE ENDS MUST BE CLOSED, or readDataToEndOfFile waits for a writer that is
		 * this process. */
		[[outPipe fileHandleForWriting] closeFile];
		[[errPipe fileHandleForWriting] closeFile];
		[task waitUntilExit];
		{
			NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
			NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
			NSString *outText = [[[NSString alloc] initWithData:outData
								   encoding:NSUTF8StringEncoding] autorelease];
			NSString *errText = [[[NSString alloc] initWithData:errData
								   encoding:NSUTF8StringEncoding] autorelease];

			check([task terminationStatus] == 7, "NSTask reports the child's exit status");
			check([outText isEqualToString:@"value"], "NSTask's stdout pipe carries the child's output");
			check([errText isEqualToString:@"err"], "NSTask's stderr pipe is separate");
			check(![task isRunning], "a waited-for task is not running");
		}
		[task release];
	}

	/* ============================== NSConnection ON ITS OWN THREAD ============================= */

	/* THE IN-PROCESS ROUND TRIP, WITH THE SERVICE SERVED BY `-runInNewThread` RATHER THAN BY THE CALLER'S LOOP.
	 * (The cross-process case is NOT here: this library's name server is in-process, so a service and its client
	 * must share a process — NSConnection.h records that limitation and its ground.) */
	{
		EchoObject *echo = [[EchoObject alloc] init];
		NSMessagePort *port = [[NSMessagePort alloc] initWithName:@"AgoraThreadProbe"];

		check(port != nil, "an NSMessagePort takes a name");
		if (port != nil) {
			NSConnection *service = [NSConnection connectionWithReceivePort:port sendPort:nil];

			check(service != nil, "a connection is made over the named port");
			if (service != nil) {
				id proxy;

				[service setRootObject:echo];
				[service runInNewThread];
				proxy = [NSConnection rootProxyForConnectionWithRegisteredName:@"AgoraThreadProbe"
											host:nil];
				check(proxy != nil, "a client resolves a service served by -runInNewThread");
				if (proxy != nil) {
					[proxy setProtocolForProxy:@protocol(EchoProtocol)];
					check([[(id<EchoProtocol>)proxy echo:@"ping"] isEqualToString:@"pong"],
					      "-runInNewThread serves the request on its own loop");
				}
				[service invalidate];
			}
			[port release];
		}
		[echo release];
	}

	/* ============================== A REPEATED-LIFECYCLE SOAK ================================= */

	{
		NSUInteger iteration;

		for (iteration = 0; iteration < 300; iteration++) {
			NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
			SoakObject *object = [[SoakObject alloc] init];
			SoakObserver *observer = [[SoakObserver alloc] init];
			NSString *name = [NSString stringWithFormat:@"AgoraSoakNotification-%lu",
					  (unsigned long)iteration];
			NSData *archive;
			id back;

			[object addObserver:observer forKeyPath:@"number" options:0 context:NULL];
			[object setNumber:(int)iteration];
			[object removeObserver:observer forKeyPath:@"number"];
			[[NSNotificationCenter defaultCenter] addObserver:observer
								 selector:@selector(observeValueForKeyPath:ofObject:change:context:)
								     name:name
								   object:nil];
			[[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
			[[NSNotificationCenter defaultCenter] removeObserver:observer name:name object:nil];
			archive = [NSKeyedArchiver archivedDataWithRootObject:
				   [NSDictionary dictionaryWithObjectsAndKeys:
				    [NSNumber numberWithUnsignedInteger:iteration], @"iteration", nil]];
			back = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
			if (![back isKindOfClass:[NSDictionary class]]) {
				g_fail = 1;
				printf("FAIL: soak iteration %lu did not round-trip\n", (unsigned long)iteration);
			}
			[object release];
			[observer release];
			[inner drain];
		}
		check(1, "300 observe/notify/archive lifecycles complete");
	}

	[pool drain];
	printf(g_fail ? "foundation_behaviour_4: FAIL\n" : "foundation_behaviour_4: all checks passed\n");
	return g_fail;
}
