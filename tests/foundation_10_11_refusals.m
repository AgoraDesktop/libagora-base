/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_refusals.m — EVERY `FOUNDATION-REFUSE` DOOR, ASSERTED BY ITS OWN NAME AND ITS DOCUMENTED RETURN.
 *
 * W5 made the refusals measurable and M2 makes them TESTED. `tests/refusal_census.txt` counts the sites per file in
 * both directions; this suite is the other half: it calls each door ONCE, captures the line it writes to stderr, and
 * checks three things — that a named line appeared, that it names THIS door (not a neighbour's), and that the call's
 * documented answer holds (nil, NO, a handler called, a state moved, an exception raised).
 *
 * WHY STDERR IS REDIRECTED FOR THE WHOLE FILE: a refusal's contract is the LINE and the RETURN, and a suite that only
 * checked the return would pass for a door that silently answered nil. The capture is a regular file (mkstemp), so the
 * mark/read is an lseek away; every call is bracketed by `capture_mark()` then `capture_expect()`. Failures go to
 * STDOUT (stderr is the capture), and the captured text is dumped when anything failed.
 *
 * THE COUNT IS DELIBERATE: `g_doors` is checked against 52 — the census's door count — so a door added to a family
 * without a case here fails the suite rather than going untested. (The census counts the same fact from the other
 * direction; the two together are what "a refusal is a contract" means.)
 */
#import <Foundation/Foundation.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSXPCConnection.h>
#import <Foundation/NSUserScriptTask.h>
#import <Foundation/NSProgress.h>
#import <Foundation/NSExtensionContext.h>
#import <Foundation/NSDistantObject.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <objc/runtime.h>	/* the IMP of an NS_UNAVAILABLE door, without messaging it */

static int g_pass, g_fail;
static int g_doors;

static char g_capture_path[256];
static int g_capture_read = -1;
static long g_mark;

/* ---- the stderr capture ----------------------------------------------------- */

static void capture_begin(void)
{
	int fd;

	snprintf(g_capture_path, sizeof g_capture_path, "/tmp/agora-refusals-XXXXXX");
	fd = mkstemp(g_capture_path);
	if (fd < 0) {
		fprintf(stdout, "FAIL: could not make the stderr capture file\n");
		exit(2);
	}
	g_capture_read = open(g_capture_path, O_RDONLY);
	dup2(fd, 2);
	close(fd);
	g_mark = 0;
}

static void capture_mark(void)
{
	fflush(stderr);
	g_mark = lseek(2, 0, SEEK_CUR);
}

/* THE NEW TEXT SINCE THE MARK, as a static buffer that the next call overwrites. */
static const char *capture_take(void)
{
	static char text[8192];
	off_t end;
	size_t length;

	fflush(stderr);
	end = lseek(2, 0, SEEK_CUR);
	length = (size_t)(end - g_mark);
	if (length >= sizeof text) {
		length = sizeof text - 1;
	}
	text[0] = '\0';
	if (length > 0) {
		ssize_t got = pread(g_capture_read, text, length, g_mark);

		text[got > 0 ? (size_t)got : 0] = '\0';
	}
	g_mark = end;
	return text;
}

/* `needle` is what the line must NAME; `ok` is the documented answer. */
static void capture_expect(const char *needle, int ok, const char *what)
{
	const char *text = capture_take();
	int named = strstr(text, "FOUNDATION-REFUSE: ") != NULL &&
		    strstr(text, needle) != NULL;

	g_doors++;
	if (named && ok) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stdout, "FAIL: %s%s%s\n", what,
		named ? "" : " (no named FOUNDATION-REFUSE line)",
		ok ? "" : " (the documented return did not hold)");
}

/* ---- a one-shot HTTP server, for the session conversion case ---------------- */

struct listener {
	int fd;
	int port;
};

static int make_listener(struct listener *out)
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

static void *server_main(void *context)
{
	struct listener *listener = (struct listener *)context;
	int client = accept(listener->fd, NULL, NULL);
	static const char response[] =
		"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok";

	if (client >= 0) {
		char request[2048];
		ssize_t got = read(client, request, sizeof request - 1);

		(void)got;
		(void)write(client, response, sizeof response - 1);
		close(client);
	}
	close(listener->fd);
	return NULL;
}

/* ---- a waitable event ------------------------------------------------------- */

typedef struct {
	pthread_mutex_t mutex;
	pthread_cond_t cond;
	int fired;
} refusal_event;

static void event_init(refusal_event *e)
{
	memset(e, 0, sizeof *e);
	pthread_mutex_init(&e->mutex, NULL);
	pthread_cond_init(&e->cond, NULL);
}

static void event_fire(refusal_event *e)
{
	pthread_mutex_lock(&e->mutex);
	e->fired = 1;
	pthread_cond_broadcast(&e->cond);
	pthread_mutex_unlock(&e->mutex);
}

static int event_wait(refusal_event *e, int seconds)
{
	struct timespec deadline;
	int fired;

	clock_gettime(CLOCK_REALTIME, &deadline);
	deadline.tv_sec += seconds;
	pthread_mutex_lock(&e->mutex);
	while (!e->fired) {
		if (pthread_cond_timedwait(&e->cond, &e->mutex, &deadline) != 0) {
			break;
		}
	}
	fired = e->fired;
	pthread_mutex_unlock(&e->mutex);
	return fired;
}

static void event_destroy(refusal_event *e)
{
	pthread_cond_destroy(&e->cond);
	pthread_mutex_destroy(&e->mutex);
}

/* ---- the delegate the conversion case needs --------------------------------- */

@interface RefusalDelegate : NSObject <NSURLSessionDelegate, NSURLSessionDataDelegate>
{
@public
	refusal_event *done;
	BOOL askedForDownload;
}
@end

@implementation RefusalDelegate

/* A DATA TASK ASKED TO BECOME A DOWNLOAD: the transport refuses the conversion by name, and the task is cancelled.
 * This is the only public path to that site. */
- (void)URLSession:(NSURLSession *)session
	  dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
	(void)session;
	(void)dataTask;
	(void)response;
	askedForDownload = YES;
	completionHandler(NSURLSessionResponseBecomeDownload);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
	(void)session;
	(void)task;
	(void)error;
	event_fire(done);
}

@end

/* =================================================================================================== */

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	capture_begin();

	/* ---- NSProxy: the two NS_UNAVAILABLE doors, still bodied (2) ---- */
	{
		id proxy = [NSProxy alloc];
		BOOL weak, retained;
		/* NS_UNAVAILABLE, so the COMPILER refuses these two — which is the contract. The runtime does not, and the
		 * refusal is for the caller that reaches them through it, so the suite calls them the way that caller must:
		 * through the selector's IMP. */
		BOOL (*allows)(id, SEL) = (BOOL (*)(id, SEL))
			class_getMethodImplementation([NSProxy class], @selector(allowsWeakReference));
		BOOL (*retains)(id, SEL) = (BOOL (*)(id, SEL))
			class_getMethodImplementation([NSProxy class], @selector(retainWeakReference));

		capture_mark();
		weak = allows(proxy, @selector(allowsWeakReference));
		capture_expect("-[NSProxy allowsWeakReference]", weak == NO,
			       "a proxy refuses weak references");
		capture_mark();
		retained = retains(proxy, @selector(retainWeakReference));
		capture_expect("-[NSProxy retainWeakReference]", retained == NO,
			       "and retaining one is refused too");
		[proxy release];
	}

	/* ---- NSAppleEventDescriptor: the send with no transport (1) ---- */
	{
		NSError *error = nil;
		NSAppleEventDescriptor *event = [NSAppleEventDescriptor descriptorWithString:@"value"];
		id sent;

		capture_mark();
		sent = [event sendEventWithOptions:NSAppleEventSendDefaultOptions timeout:1.0 error:&error];
		capture_expect("-[NSAppleEventDescriptor sendEventWithOptions:timeout:error:]",
			       sent == nil && error != nil && [error code] == NSFeatureUnsupportedError,
			       "a descriptor cannot be sent, and says so with the feature-unsupported error");
	}

	/* ---- NSProgress: publishing with no URL to publish under (1) ---- */
	{
		NSProgress *progress = [NSProgress progressWithTotalUnitCount:4];
		__block int published = 0;
		id subscriber = [NSProgress addSubscriberForFileURL:[NSURL fileURLWithPath:@"/tmp/agora-publish"]
					      withPublishingHandler:^NSProgressUnpublishingHandler(NSProgress *object) {
			(void)object;
			published++;
			return nil;
		}];

		capture_mark();
		[progress publish];
		capture_expect("-[NSProgress publish]",
			       published == 0,
			       "a progress with no NSProgressFileURLKey is not published, so no subscriber hears it");
		[NSProgress removeSubscriber:subscriber];
	}

	/* ---- NSDistantObject: the two coder doors (2) ---- */
	{
		NSDistantObject *proxy = [NSDistantObject proxyWithTarget:nil connection:nil];
		NSDistantObject *decoded;
		BOOL raised = NO;

		capture_mark();
		decoded = [[NSDistantObject alloc] initWithCoder:nil];
		capture_expect("-[NSDistantObject initWithCoder:]", decoded == nil,
			       "a proxy cannot be rebuilt from an archive");
		capture_mark();
		@try {
			[proxy encodeWithCoder:nil];
		}
		@catch (NSException *exception) {
			raised = [[exception name] isEqualToString:NSInvalidArgumentException];
		}
		capture_expect("-[NSDistantObject encodeWithCoder:]", raised,
			       "and it cannot be written to one either, which raises");
	}

	/* ---- NSExtensionContext: the three requests with no extension process (3) ---- */
	{
		NSExtensionContext *context = [[NSExtensionContext alloc] init];
		__block int completed = -1;
		__block int opened = -1;

		capture_mark();
		[context completeRequestReturningItems:nil completionHandler:^(BOOL expired) {
			completed = expired ? 1 : 0;
		}];
		capture_expect("-[NSExtensionContext completeRequestReturningItems:completionHandler:]",
			       completed == 0, "completing a request answers the handler with NO");
		capture_mark();
		[context cancelRequestWithError:[NSError errorWithDomain:@"refusal.test" code:1 userInfo:nil]];
		capture_expect("-[NSExtensionContext cancelRequestWithError:]", YES,
			       "cancelling a request refuses by name");
		capture_mark();
		[context openURL:[NSURL URLWithString:@"http://example/"] completionHandler:^(BOOL success) {
			opened = success ? 1 : 0;
		}];
		capture_expect("-[NSExtensionContext openURL:completionHandler:]",
			       opened == 0, "and opening a URL through the host answers NO");
		[context release];
	}

	/* ---- NSUserNotificationCenter: delivery with no daemon (1) ---- */
	{
		NSUserNotificationCenter *centre = [NSUserNotificationCenter defaultUserNotificationCenter];
		NSUserNotification *notification = [[[NSUserNotification alloc] init] autorelease];
		NSUInteger before = [[centre deliveredNotifications] count];

		capture_mark();
		[centre deliverNotification:notification];
		capture_expect("-[NSUserNotificationCenter deliverNotification:]",
			       [[centre deliveredNotifications] count] == before,
			       "delivery is refused and nothing is recorded as delivered");
	}

	/* ---- NSUserScriptTask: the base and its two subclasses (4) ---- */
	{
		NSUserScriptTask *task = [[NSUserScriptTask alloc] init];
		NSUserAppleScriptTask *appleScript = [[NSUserAppleScriptTask alloc] init];
		NSUserAutomatorTask *automator = [[NSUserAutomatorTask alloc] init];
		NSError *error = nil;
		__block BOOL executeAnswered = NO;
		__block BOOL appleScriptAnswered = NO;
		__block BOOL automatorAnswered = NO;
		id refused;

		capture_mark();
		refused = [[NSUserScriptTask alloc] initWithURL:[NSURL fileURLWithPath:@"/tmp/agora-script"]
							  error:&error];
		capture_expect("-[NSUserScriptTask initWithURL:error:]",
			       refused == nil && error != nil &&
			       [[error domain] isEqualToString:NSUserScriptTaskErrorDomain],
			       "a user script cannot be constructed, and the error names the missing engine");
		capture_mark();
		[task executeWithCompletionHandler:^(NSError *e) {
			executeAnswered = e != nil;
		}];
		capture_expect("-[NSUserScriptTask executeWithCompletionHandler:]",
			       executeAnswered, "and executing one answers its handler with the error");
		capture_mark();
		[appleScript executeWithAppleEvent:nil completionHandler:^(NSAppleEventDescriptor *result, NSError *e) {
			(void)result;
			appleScriptAnswered = e != nil;
		}];
		capture_expect("-[NSUserAppleScriptTask executeWithAppleEvent:completionHandler:]",
			       appleScriptAnswered, "an AppleScript task answers its handler with the error");
		capture_mark();
		[automator executeWithInput:nil completionHandler:^(id result, NSError *e) {
			(void)result;
			automatorAnswered = e != nil;
		}];
		capture_expect("-[NSUserAutomatorTask executeWithInput:completionHandler:]",
			       automatorAnswered, "and an Automator task does the same");
		[task release];
		[appleScript release];
		[automator release];
	}

	/* ---- XPC: the whole family, every door (24) ---- */
	{
		NSXPCConnection *connection = [[NSXPCConnection alloc] init];
		NSXPCInterface *interface = [[NSXPCInterface alloc] init];
		NSXPCListener *listener = [[NSXPCListener alloc] init];
		__block BOOL proxyAnswered = NO;
		id made, proxy;
		NSArray *described;
		NSXPCInterface *nested;
		NSXPCListenerEndpoint *endpoint;

		capture_mark();
		made = [[NSXPCConnection alloc] initWithServiceName:@"com.example.refused"];
		capture_expect("-[NSXPCConnection initWithServiceName:]", made == nil,
			       "a connection by service name refuses");
		capture_mark();
		made = [[NSXPCConnection alloc] initWithMachServiceName:@"com.example.refused" options:0];
		capture_expect("-[NSXPCConnection initWithMachServiceName:options:]", made == nil,
			       "a Mach-service connection refuses");
		capture_mark();
		made = [[NSXPCConnection alloc] initWithListenerEndpoint:[[[NSXPCListenerEndpoint alloc] init] autorelease]];
		capture_expect("-[NSXPCConnection initWithListenerEndpoint:]", made == nil,
			       "a connection to an endpoint refuses");
		capture_mark();
		[connection setRemoteObjectInterface:interface];
		capture_expect("-[NSXPCConnection setRemoteObjectInterface:]", YES,
			       "there is no connection to hold a remote interface");
		capture_mark();
		[connection setExportedObject:@"object"];
		capture_expect("-[NSXPCConnection setExportedObject:]", YES,
			       "or to export an object over");
		capture_mark();
		[connection setExportedInterface:interface];
		capture_expect("-[NSXPCConnection setExportedInterface:]", YES,
			       "or to hold an exported interface");
		capture_mark();
		[connection resume];
		capture_expect("-[NSXPCConnection resume]", YES, "there is no connection to resume");
		capture_mark();
		[connection suspend];
		capture_expect("-[NSXPCConnection suspend]", YES, "or to suspend");
		capture_mark();
		[connection invalidate];
		capture_expect("-[NSXPCConnection invalidate]", YES, "or to invalidate");
		capture_mark();
		proxy = [connection remoteObjectProxy];
		capture_expect("-[NSXPCConnection remoteObjectProxy]", proxy == nil,
			       "a remote proxy cannot be made and answers nil");
		capture_mark();
		proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
			proxyAnswered = error != nil;
		}];
		capture_expect("-[NSXPCConnection remoteObjectProxyWithErrorHandler:]",
			       proxy == nil && proxyAnswered,
			       "and the error-handler form answers its handler with the error");

		capture_mark();
		made = [NSXPCInterface interfaceWithProtocol:@protocol(NSObject)];
		capture_expect("+[NSXPCInterface interfaceWithProtocol:]", made == nil,
			       "no XPC boundary exists, so an interface cannot be made");
		capture_mark();
		described = [interface classesForSelector:@selector(description) argumentIndex:0 ofReply:NO];
		capture_expect("-[NSXPCInterface classesForSelector:argumentIndex:ofReply:]", described == nil,
			       "and it has no classes to describe");
		capture_mark();
		[interface setClasses:[NSArray array] forSelector:@selector(description) argumentIndex:0 ofReply:NO];
		capture_expect("-[NSXPCInterface setClasses:forSelector:argumentIndex:ofReply:]", YES,
			       "or to set them on");
		capture_mark();
		nested = [interface interfaceForSelector:@selector(description) argumentIndex:0 ofReply:NO];
		capture_expect("-[NSXPCInterface interfaceForSelector:argumentIndex:ofReply:]", nested == nil,
			       "and no nested interface to hand back");
		capture_mark();
		[interface setInterface:nil forSelector:@selector(description) argumentIndex:0 ofReply:NO];
		capture_expect("-[NSXPCInterface setInterface:forSelector:argumentIndex:ofReply:]", YES,
			       "or to set one");

		capture_mark();
		made = [NSXPCListener anonymousListener];
		capture_expect("+[NSXPCListener anonymousListener]", made == nil,
			       "no listener can be made, anonymous or otherwise");
		capture_mark();
		made = [NSXPCListener serviceListener];
		capture_expect("+[NSXPCListener serviceListener]", made == nil,
			       "a service listener refuses too");
		capture_mark();
		made = [[NSXPCListener alloc] initWithMachServiceName:@"com.example.refused"];
		capture_expect("-[NSXPCListener initWithMachServiceName:]", made == nil,
			       "a listener by Mach service name refuses");
		capture_mark();
		endpoint = [listener endpoint];
		capture_expect("-[NSXPCListener endpoint]", endpoint == nil,
			       "and a listener has no endpoint to hand out");
		capture_mark();
		[listener resume];
		capture_expect("-[NSXPCListener resume]", YES, "no listener to resume");
		capture_mark();
		[listener suspend];
		capture_expect("-[NSXPCListener suspend]", YES, "none to suspend");
		capture_mark();
		[listener invalidate];
		capture_expect("-[NSXPCListener invalidate]", YES, "and none to invalidate");
		[connection release];
		[interface release];
		[listener release];
	}

	/* ---- NSURLSession: the transport's and the session's refusals (15) ---- */
	{
		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
		NSURLSessionConfiguration *background =
			[NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"agora.refusal"];
		NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
		NSURLSession *invalidated = [NSURLSession sessionWithConfiguration:configuration];
		NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/x"]];
		NSURL *missing = [NSURL fileURLWithPath:@"/tmp/agora-no-such-file"];
		NSNetService *service = [[[NSNetService alloc] initWithDomain:@"local."
								 type:@"_http._tcp."
								 name:@"unresolved"
								 port:1] autorelease];
		NSURLSession *made;
		id task;
		NSHTTPCookieStorage *store;

		capture_mark();
		made = [NSURLSession sessionWithConfiguration:background];
		capture_expect("-[NSURLSession sessionWithConfiguration:delegate:delegateQueue:]", made == nil,
			       "a background configuration makes no session");
		capture_mark();
		task = [session uploadTaskWithRequest:request fromFile:missing];
		capture_expect("-[NSURLSession uploadTaskWithRequest:fromFile:]", task == nil,
			       "an upload from a file that cannot be read makes no task");
		capture_mark();
		task = [session uploadTaskWithRequest:request
					    fromFile:missing
				   completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
			(void)d;
			(void)r;
			(void)e;
		}];
		capture_expect("-[NSURLSession uploadTaskWithRequest:fromFile:completionHandler:]", task == nil,
			       "and the completion-handler form refuses too");
		capture_mark();
		task = [session uploadTaskWithStreamedRequest:request];
		capture_expect("-[NSURLSession uploadTaskWithStreamedRequest:]", task == nil,
			       "a streamed upload has no body-stream read in the transport");
		capture_mark();
		task = [session downloadTaskWithResumeData:[NSData data]];
		capture_expect("-[NSURLSession downloadTaskWithResumeData:]", task == nil,
			       "resume data cannot resume a transfer");
		capture_mark();
		task = [session downloadTaskWithResumeData:[NSData data]
			       completionHandler:^(NSURL *l, NSURLResponse *r, NSError *e) {
			(void)l;
			(void)r;
			(void)e;
		}];
		capture_expect("-[NSURLSession downloadTaskWithResumeData:completionHandler:]", task == nil,
			       "and its completion-handler form does the same");
		capture_mark();
		task = [session streamTaskWithNetService:service];
		capture_expect("-[NSURLSession streamTaskWithNetService:]", task == nil,
			       "an unresolved NetService cannot become a stream task");

		/* THE INVALIDATED SESSION'S THREE: no new work after invalidation, which is Apple's rule. */
		[invalidated invalidateAndCancel];
		capture_mark();
		task = [invalidated streamTaskWithHostName:@"127.0.0.1" port:9];
		capture_expect("a stream task was asked of a session that has been invalidated", task == nil,
			       "an invalidated session makes no stream task");
		capture_mark();
		task = [invalidated downloadTaskWithRequest:request];
		capture_expect("a download task was asked of a session that has been invalidated", task == nil,
			       "and no download task");
		capture_mark();
		task = [invalidated dataTaskWithRequest:request];
		capture_expect("a task was asked of a session that has been invalidated", task == nil,
			       "and no data task");

		/* THE DATA-TO-DOWNLOAD CONVERSION, through its only public path: a loopback response and a delegate that
		 * asks for it. */
		{
			struct listener listener;
			pthread_t thread;
			RefusalDelegate *delegate = [[RefusalDelegate alloc] init];
			NSOperationQueue *queue = [[NSOperationQueue alloc] init];
			NSURLSession *conversion;
			NSURLSessionDataTask *dataTask;
			refusal_event done;

			event_init(&done);
			delegate->done = &done;
			[queue setMaxConcurrentOperationCount:1];
			if (make_listener(&listener) == 0) {
				pthread_create(&thread, NULL, server_main, &listener);
				conversion = [NSURLSession sessionWithConfiguration:configuration
									  delegate:delegate
								     delegateQueue:queue];
				dataTask = [conversion dataTaskWithURL:
					[NSURL URLWithString:[NSString stringWithFormat:
						@"http://127.0.0.1:%d/convert", listener.port]]];
				capture_mark();
				[dataTask resume];
				(void)event_wait(&done, 10);
				pthread_join(thread, NULL);
				capture_expect("a data task was asked to become a download task",
					       delegate->askedForDownload &&
					       [dataTask state] == NSURLSessionTaskStateCompleted,
					       "the conversion is refused by name and the task is cancelled to a completed state");
				[conversion invalidateAndCancel];
			} else {
				g_fail++;
				fprintf(stdout, "FAIL: the conversion listener did not bind\n");
			}
			[delegate release];
			[queue release];
			event_destroy(&done);
		}

		/* THE DOWNLOAD'S RESUME-DATA CANCELLATION: the handler answers nil and the task cancels. */
		{
			NSOperationQueue *queue = [[NSOperationQueue alloc] init];
			NSURLSession *downloads = [NSURLSession sessionWithConfiguration:configuration
									       delegate:nil
									  delegateQueue:queue];
			NSURLSessionDownloadTask *download =
				[downloads downloadTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/never"]];
			__block BOOL answered = NO;
			__block NSData *resume = nil;

			[queue setMaxConcurrentOperationCount:1];
			capture_mark();
			[download cancelByProducingResumeData:^(NSData *data) {
				answered = YES;
				resume = [data retain];
			}];
			[queue waitUntilAllOperationsAreFinished];
			capture_expect("-[NSURLSessionDownloadTask cancelByProducingResumeData:]",
				       answered && resume == nil &&
				       [download state] == NSURLSessionTaskStateCompleted,
				       "the cancellation answers nil resume data and completes the task");
			[resume release];
			[downloads invalidateAndCancel];
			[queue release];
		}

		/* THE STREAM TASK'S TLS PAIR: no handshake exists for a raw stream. */
		{
			NSURLSessionStreamTask *stream =
				[session streamTaskWithHostName:@"127.0.0.1" port:9];

			capture_mark();
			[stream startSecureConnection];
			capture_expect("-[NSURLSessionStreamTask startSecureConnection]", YES,
				       "a raw stream has no TLS handshake to start");
			capture_mark();
			[stream stopSecureConnection];
			capture_expect("-[NSURLSessionStreamTask stopSecureConnection]", YES,
				       "and none to stop");
			[stream cancel];
		}

		capture_mark();
		store = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:@"group.example"];
		capture_expect("+[NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:]", store == nil,
			       "there are no app-group containers, so no store is made");
		[session invalidateAndCancel];
	}

	/* ---- the instrument's own arithmetic ---- */
	if (g_doors != 52) {
		g_fail++;
		fprintf(stdout, "FAIL: %d refusal doors asserted, the census has 52\n", g_doors);
	} else {
		g_pass++;
		fprintf(stdout, "ok: every one of the %d refusal doors asserted its named line and return\n", g_doors);
	}

	if (g_fail > 0) {
		/* RESTORE THE REAL STDERR AND SHOW WHAT WAS CAPTURED: a failing suite whose evidence is in a temp file is a
		 * suite nobody can debug. */
		char text[65536];
		ssize_t got;

		dup2(STDOUT_FILENO, STDERR_FILENO);
		fprintf(stderr, "---- captured refusals ----\n");
		lseek(g_capture_read, 0, SEEK_SET);
		while ((got = read(g_capture_read, text, sizeof text - 1)) > 0) {
			text[got] = '\0';
			fputs(text, stderr);
		}
	}

	printf("foundation_10_11_refusals: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	unlink(g_capture_path);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
