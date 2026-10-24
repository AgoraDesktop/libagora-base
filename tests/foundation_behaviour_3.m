/*
 * foundation_behaviour_3 — the fourth wave of the behavioural pass.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. The first three waves cover values, machinery, calendars and formats. This one covers the
 * parts that cross a BOUNDARY: secure coding (an archive with a class allow-list), user defaults written by ANOTHER
 * PROCESS, an HTTP request against a socket this test listens on, socket streams, an NSConnection round-trip, file
 * handles, and a coarse performance smoke test that would catch an accidental quadratic rather than a wrong answer.
 *
 * EVERY NETWORK TEST IS HERMETIC: the servers are POSIX sockets on 127.0.0.1 with a kernel-chosen port, so nothing
 * here depends on the internet or on a fixed port being free.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
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

static double
now_seconds(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* ---- a secure-codable value ------------------------------------------------------------------------------- */

@interface SecureThing : NSObject <NSSecureCoding>
{
@public
	NSString *label;
	NSInteger number;
}
@end

@implementation SecureThing
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc { [label release]; [super dealloc]; }
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:label forKey:@"label"];
	[coder encodeInteger:number forKey:@"number"];
}
- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil) {
		label = [[coder decodeObjectOfClass:[NSString class] forKey:@"label"] retain];
		number = [coder decodeIntegerForKey:@"number"];
	}
	return self;
}
@end

/* ---- a local HTTP server, and a socket echo server --------------------------------------------------------- */

struct listener {
	int fd;
	int port;
};

static int
make_listener(struct listener *out)
{
	struct sockaddr_in address;
	socklen_t length = sizeof address;
	int fd = socket(AF_INET, SOCK_STREAM, 0);

	if (fd < 0) {
		return -1;
	}
	memset(&address, 0, sizeof address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	if (bind(fd, (struct sockaddr *)&address, sizeof address) != 0 ||
	    listen(fd, 1) != 0 ||
	    getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
		close(fd);
		return -1;
	}
	out->fd = fd;
	out->port = ntohs(address.sin_port);
	return 0;
}

static void *
http_server(void *context)
{
	struct listener *listener = (struct listener *)context;
	char request[2048];
	int client = accept(listener->fd, NULL, NULL);

	if (client >= 0) {
		static const char response[] =
			"HTTP/1.1 200 OK\r\n"
			"Content-Type: text/plain\r\n"
			"Content-Length: 5\r\n"
			"Connection: close\r\n"
			"\r\n"
			"hello";

		(void)read(client, request, sizeof request - 1);
		(void)write(client, response, sizeof response - 1);
		close(client);
	}
	close(listener->fd);
	return NULL;
}

static void *
echo_server(void *context)
{
	struct listener *listener = (struct listener *)context;
	char buffer[8];
	ssize_t got;
	int client = accept(listener->fd, NULL, NULL);

	memset(buffer, 0, sizeof buffer);
	if (client >= 0) {
		got = read(client, buffer, 4);
		if (got == 4) {
			(void)write(client, "pong", 4);
		}
		close(client);
	}
	close(listener->fd);
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

static NSString *
scratch_root(void)
{
	static char path[512];
	char template[] = "/tmp/agora-wave4-XXXXXX";

	if (path[0] == 0) {
		if (mkdtemp(template) != NULL) {
			snprintf(path, sizeof path, "%s", template);
		}
	}
	return [NSString stringWithUTF8String:path];
}

/* THE CHILD MODE: write one defaults key and synchronise, so the parent can read it from a fresh process. */
static int
write_defaults_child(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"AgoraCrossProcessProbe"];

	[defaults setObject:@"from-child" forKey:@"childKey"];
	check([defaults synchronize], "the child synchronises its defaults");
	[defaults release];
	[pool drain];
	return g_fail;
}

int
main(int argc, char **argv)
{
	NSAutoreleasePool *pool;
	char configRoot[] = "/tmp/agora-wave4-defaults-XXXXXX";

	if (argc > 1 && strcmp(argv[1], "--write-defaults") == 0) {
		return write_defaults_child();
	}
	pool = [[NSAutoreleasePool alloc] init];
	if (mkdtemp(configRoot) != NULL) {
		setenv("FNX_CONFIG_ROOT", configRoot, 1);
	}

	/* ============================== SECURE CODING ============================================= */

	{
		SecureThing *thing = [[SecureThing alloc] init];
		NSError *error = nil;
		NSData *data;
		SecureThing *back;
		id wrong;

		thing->label = [@"secret" copy];
		thing->number = 42;
		data = [NSKeyedArchiver archivedDataWithRootObject:thing requiringSecureCoding:YES error:&error];
		check(data != nil && error == nil, "a secure archive writes with a class allow-list");
		back = data != nil
			? [NSKeyedUnarchiver unarchivedObjectOfClass:[SecureThing class] fromData:data error:&error]
			: nil;
		check(back != nil && [back->label isEqualToString:@"secret"] && back->number == 42,
		      "the secure archive reads back with the declared class");
		error = nil;
		wrong = data != nil
			? [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:data error:&error]
			: nil;
		check(wrong == nil && error != nil,
		      "an unarchiver refuses a root class that is not on the allow-list");
		[thing release];
	}
	{
		NSSecureUnarchiveFromDataTransformer *transformer =
			[[NSSecureUnarchiveFromDataTransformer alloc] init];
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:
				[NSArray arrayWithObjects:@"one", @"two", nil]];
		id value = [transformer transformedValue:data];

		check([[NSSecureUnarchiveFromDataTransformer allowedTopLevelClasses] count] > 0,
		      "the secure transformer names its default allowed classes");
		check([value isKindOfClass:[NSArray class]] && [value count] == 2,
		      "the secure transformer unarchives a property-list-shaped archive");
		[transformer release];
	}

	/* ============================== DEFAULTS ACROSS PROCESSES ================================= */

	{
		char resolved[1024];
		NSString *executable = nil;
		NSTask *task;
		NSUserDefaults *defaults;

		if (realpath(argv[0], resolved) != NULL) {
			executable = [NSString stringWithUTF8String:resolved];
		}
		check(executable != nil, "the probe can name its own executable");
		task = executable != nil
			? [NSTask launchedTaskWithLaunchPath:executable
					     arguments:[NSArray arrayWithObject:@"--write-defaults"]]
			: nil;
		if (task != nil) {
			[task waitUntilExit];
			check([task terminationStatus] == 0, "a child process writes defaults and exits cleanly");
		}
		defaults = [[NSUserDefaults alloc] initWithSuiteName:@"AgoraCrossProcessProbe"];
		check([[[defaults objectForKey:@"childKey"] description] isEqualToString:@"from-child"],
		      "the parent reads the value another process wrote");
		check([[[[defaults dictionaryRepresentation] objectForKey:@"childKey"] description]
		       isEqualToString:@"from-child"],
		      "the value appears in -dictionaryRepresentation");
		[defaults release];
	}

	/* ============================== HTTP OVER A LOCAL SOCKET ================================== */

	{
		struct listener listener;
		pthread_t thread;
		NSURLRequest *request = nil;
		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		NSData *data = nil;
		NSString *urlString;

		if (make_listener(&listener) == 0) {
			check(1, "the HTTP listener bound a loopback port");
			pthread_create(&thread, NULL, http_server, &listener);
			urlString = [NSString stringWithFormat:@"http://127.0.0.1:%d/probe", listener.port];
			request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
						   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
					       timeoutInterval:10.0];
			data = [NSURLConnection sendSynchronousRequest:request
						      returningResponse:&response
								  error:&error];
			pthread_join(thread, NULL);
			check(data != nil && error == nil, "a synchronous HTTP request succeeds against a local server");
			check([response isKindOfClass:[NSHTTPURLResponse class]] && [response statusCode] == 200,
			      "the response is HTTP 200");
			{
				NSString *body = [[[NSString alloc] initWithData:data
									encoding:NSUTF8StringEncoding] autorelease];

				check(body != nil && [body isEqualToString:@"hello"],
				      "the response body is the bytes the server sent");
			}
		} else {
			check(0, "the HTTP listener could not bind a loopback port");
		}
	}

	/* ============================== SOCKET STREAMS ============================================ */

	{
		struct listener listener;

		if (make_listener(&listener) == 0) {
			pthread_t thread;
			NSInputStream *input = nil;
			NSOutputStream *output = nil;
			int spins;
			char buffer[8];

			pthread_create(&thread, NULL, echo_server, &listener);
			[NSStream getStreamsToHostWithName:@"127.0.0.1"
						      port:listener.port
					       inputStream:&input
					      outputStream:&output];
			check(input != nil && output != nil, "the stream factory returns both socket streams");
			[input open];
			[output open];
			for (spins = 0; spins < 100 && ![output hasSpaceAvailable]; spins++) {
				[[NSRunLoop currentRunLoop] runUntilDate:
					[NSDate dateWithTimeIntervalSinceNow:0.02]];
			}
			check([output hasSpaceAvailable], "the output stream becomes writable");
			check([output write:(const uint8_t *)"ping" maxLength:4] == 4,
			      "the output stream writes the request");
			for (spins = 0; spins < 200 && ![input hasBytesAvailable]; spins++) {
				[[NSRunLoop currentRunLoop] runUntilDate:
					[NSDate dateWithTimeIntervalSinceNow:0.02]];
			}
			memset(buffer, 0, sizeof buffer);
			check([input hasBytesAvailable] && [input read:(uint8_t *)buffer maxLength:4] == 4 &&
			      memcmp(buffer, "pong", 4) == 0,
			      "the input stream reads the reply");
			[input close];
			[output close];
			pthread_join(thread, NULL);
		} else {
			check(0, "the stream listener could not bind a loopback port");
		}
	}

	/* ============================== DISTRIBUTED OBJECTS ======================================= */

	{
		EchoObject *echo = [[EchoObject alloc] init];
		NSConnection *service = [NSConnection serviceConnectionWithName:@"AgoraEchoProbe"
								    rootObject:echo];

		check(service != nil, "an NSConnection registers a service name");
		if (service != nil) {
			id proxy = [NSConnection rootProxyForConnectionWithRegisteredName:@"AgoraEchoProbe"
										    host:nil];

			check(proxy != nil, "a client resolves the registered name");
			if (proxy != nil) {
				[proxy setProtocolForProxy:@protocol(EchoProtocol)];
				check([[(id<EchoProtocol>)proxy echo:@"ping"] isEqualToString:@"pong"],
				      "a message through the proxy is answered by the root object");
			}
			[service invalidate];
		}
		[echo release];
	}

	/* ============================== FILE HANDLES =============================================== */

	{
		NSString *path = [scratch_root() stringByAppendingPathComponent:@"handle.txt"];
		NSFileManager *manager = [NSFileManager defaultManager];
		NSFileHandle *writer;
		NSFileHandle *reader;
		NSData *payload = [@"0123456789" dataUsingEncoding:NSUTF8StringEncoding];

		[manager createFileAtPath:path contents:nil attributes:nil];
		writer = [NSFileHandle fileHandleForWritingAtPath:path];
		check(writer != nil, "a writing handle opens an existing file");
		[writer writeData:payload];
		check([writer offsetInFile] == 10, "-offsetInFile follows the write");
		[writer synchronizeFile];
		[writer closeFile];

		reader = [NSFileHandle fileHandleForReadingAtPath:path];
		check(reader != nil, "a reading handle opens the file");
		[reader seekToFileOffset:5];
		{
			NSString *tail = [[[NSString alloc] initWithData:[reader readDataToEndOfFile]
								encoding:NSUTF8StringEncoding] autorelease];

			check([tail isEqualToString:@"56789"], "-seekToFileOffset: and -readDataToEndOfFile");
		}
		[reader closeFile];

		writer = [NSFileHandle fileHandleForWritingAtPath:path];
		[writer truncateFileAtOffset:3];
		[writer closeFile];
		check([[manager attributesOfItemAtPath:path error:NULL] fileSize] == 3, "-truncateFileAtOffset:");
	}

	/* ============================== PERFORMANCE SMOKE ========================================= */

	{
		double started;
		double elapsed;
		NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
		NSMutableSet *set = [[NSMutableSet alloc] init];
		NSMutableArray *array = [NSMutableArray array];
		NSUInteger i;

		started = now_seconds();
		for (i = 0; i < 100000; i++) {
			[dictionary setObject:[NSNumber numberWithUnsignedInteger:i]
				       forKey:[NSNumber numberWithUnsignedInteger:i]];
		}
		for (i = 0; i < 100000; i++) {
			(void)[dictionary objectForKey:[NSNumber numberWithUnsignedInteger:i]];
		}
		elapsed = now_seconds() - started;
		check(elapsed < 10.0, "100k dictionary inserts and lookups finish in linear-ish time");
		printf("     dictionary: %.3fs\n", elapsed);

		started = now_seconds();
		for (i = 0; i < 50000; i++) {
			[set addObject:[NSNumber numberWithUnsignedInteger:i]];
		}
		for (i = 0; i < 50000; i++) {
			(void)[set containsObject:[NSNumber numberWithUnsignedInteger:i]];
		}
		elapsed = now_seconds() - started;
		check(elapsed < 10.0, "50k set inserts and membership tests finish in linear-ish time");
		printf("     set:         %.3fs\n", elapsed);

		for (i = 0; i < 50000; i++) {
			[array addObject:[NSNumber numberWithUnsignedInteger:(i * 7919) % 50000]];
		}
		started = now_seconds();
		(void)[array sortedArrayUsingSelector:@selector(compare:)];
		elapsed = now_seconds() - started;
		check(elapsed < 10.0, "sorting 50k numbers is not quadratic");
		printf("     sort:        %.3fs\n", elapsed);

		started = now_seconds();
		for (i = 0; i < 200000; i++) {
			NSString *text = [NSString stringWithFormat:@"string-%lu", (unsigned long)i];

			(void)[text hash];
		}
		elapsed = now_seconds() - started;
		check(elapsed < 10.0, "200k string hashes finish in linear-ish time");
		printf("     strings:     %.3fs\n", elapsed);

		[dictionary release];
		[set release];
	}

	[pool drain];
	printf(g_fail ? "foundation_behaviour_3: FAIL\n" : "foundation_behaviour_3: all checks passed\n");
	return g_fail;
}
