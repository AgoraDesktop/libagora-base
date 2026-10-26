/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_url_session.m — THE TASK STATE MACHINE, AGAINST A SERVER THIS TEST LISTENS ON (10.9/10.10).
 *
 * Every case is hermetic: the servers are POSIX sockets on 127.0.0.1 with a kernel-chosen port. What is measured is
 * what a session promises that a connection does not — a task born suspended, an identifier, byte counts, delegate
 * messages on the session's QUEUE, completion handlers, redirects the delegate decides, and cancellation that ends
 * with NSURLErrorCancelled.
 */

#import <Foundation/Foundation.h>
#import <Foundation/NSURLSession.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <signal.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

/* ---- a waitable event ------------------------------------------------------- */

typedef struct {
	pthread_mutex_t mutex;
	pthread_cond_t cond;
	int fired;
} fn_event;

static void event_init(fn_event *e)
{
	memset(e, 0, sizeof *e);
	pthread_mutex_init(&e->mutex, NULL);
	pthread_cond_init(&e->cond, NULL);
}

static void event_fire(fn_event *e)
{
	pthread_mutex_lock(&e->mutex);
	e->fired = 1;
	pthread_cond_broadcast(&e->cond);
	pthread_mutex_unlock(&e->mutex);
}

static int event_wait(fn_event *e, int seconds)
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

static void event_destroy(fn_event *e)
{
	pthread_cond_destroy(&e->cond);
	pthread_mutex_destroy(&e->mutex);
}

/* ---- a local HTTP server ---------------------------------------------------- */

struct listener {
	int fd;
	int port;
};

struct server_job {
	struct listener listener;
	char response[1024];
	int delay_ms;
	char captured[4096];
	size_t captured_len;
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
	struct server_job *job = (struct server_job *)context;
	char request[4096];
	int client;
	ssize_t got;

	client = accept(job->listener.fd, NULL, NULL);
	if (client >= 0) {
		/* READ THE WHOLE REQUEST, not whatever one read returned: a POST's body can arrive after its headers, and
		 * a capture that stops at the header boundary would make the body check flaky. A receive timeout bounds
		 * the loop, so a client that stops writing cannot hang the server. */
		struct timeval timeout;
		size_t used = 0;

		timeout.tv_sec = 0;
		timeout.tv_usec = 200 * 1000;
		setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
		while (used < sizeof request - 1) {
			got = read(client, request + used, sizeof request - 1 - used);
			if (got <= 0) {
				break;
			}
			used += (size_t)got;
			if (strstr(request, "\r\n\r\n") != NULL) {
				/* A COMPLETE HEADER IS ENOUGH FOR A GET; for a body, wait once more if Content-Length says there
				 * is one. Two reads are enough for every request this suite sends. */
				char *header = strstr(request, "\r\n\r\n");

				if (strstr(request, "Content-Length:") == NULL || (used > (size_t)(header - request) + 4)) {
					break;
				}
			}
		}
		request[used] = '\0';
		got = (ssize_t)used;
		if (got > 0 && job->captured_len > 0) {
			size_t keep = (size_t)got < job->captured_len - 1 ? (size_t)got : job->captured_len - 1;

			memcpy(job->captured, request, keep);
			job->captured[keep] = '\0';
		}
		if (job->delay_ms > 0) {
			usleep((useconds_t)job->delay_ms * 1000);
		}
		if (job->response[0] != '\0') {
			(void)write(client, job->response, strlen(job->response));
		}
		close(client);
	}
	close(job->listener.fd);
	return NULL;
}

/* TWO REQUESTS IN SEQUENCE, which is what a 401-then-retry needs: the first connection is answered with the challenge,
 * the second (the re-issue) with the final response, and its Authorization header is captured. */
struct auth_job {
	struct listener listener;
	char challenge[512];
	char final[512];
	char seen_auth[2048];
	int requests;
};

static ssize_t read_request(int client, char *buffer, size_t capacity)
{
	size_t used = 0;

	while (used < capacity - 1) {
		ssize_t got = read(client, buffer + used, capacity - 1 - used);

		if (got <= 0) {
			break;
		}
		used += (size_t)got;
		if (strstr(buffer, "\r\n\r\n") != NULL) {
			break;
		}
	}
	buffer[used] = '\0';
	return (ssize_t)used;
}

static void *auth_server_main(void *context)
{
	struct auth_job *job = (struct auth_job *)context;
	int i;

	for (i = 0; i < 2; i++) {
		int client = accept(job->listener.fd, NULL, NULL);
		char request[4096];

		if (client < 0) {
			break;
		}
		if (read_request(client, request, sizeof request) > 0) {
			job->requests++;
			if (strstr(request, "Authorization:") != NULL) {
				snprintf(job->seen_auth, sizeof job->seen_auth, "%s", request);
				(void)write(client, job->final, strlen(job->final));
			} else {
				(void)write(client, job->challenge, strlen(job->challenge));
			}
		}
		close(client);
	}
	close(job->listener.fd);
	return NULL;
}

static void *echo_stream_server(void *context)
{
	struct server_job *job = (struct server_job *)context;
	char buffer[16];
	ssize_t got;
	int client = accept(job->listener.fd, NULL, NULL);

	if (client >= 0) {
		got = read(client, buffer, job->delay_ms > 0 ? (size_t)job->delay_ms : 4);
		if (got > 0) {
			(void)write(client, "pong", 4);
		}
		close(client);
	}
	close(job->listener.fd);
	return NULL;
}

/* A GREETER WRITES AND CLOSES WITHOUT READING, which is what a capture test needs: the task hands its socket over
 * without sending anything, and the server must not be left blocked in read(2) when the test joins its thread. */
static void *greeting_stream_server(void *context)
{
	struct server_job *job = (struct server_job *)context;
	int client = accept(job->listener.fd, NULL, NULL);

	if (client >= 0) {
		(void)write(client, "pong", 4);
		close(client);
	}
	close(job->listener.fd);
	return NULL;
}

static void job_start(struct server_job *job, const char *response, int delay_ms, size_t capture)
{
	memset(job, 0, sizeof *job);
	if (response != NULL) {
		snprintf(job->response, sizeof job->response, "%s", response);
	}
	job->delay_ms = delay_ms;
	job->captured_len = capture;
}

/* ---- a delegate that records what a task told it ---------------------------- */

@interface RecordingDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate,
				    NSURLSessionDownloadDelegate>
{
@public
	NSMutableData *body;
	NSURLResponse *responseHead;
	NSHTTPURLResponse *redirectResponse;
	NSError *completionError;
	NSUInteger responseCalls, dataCalls, completionCalls;
	pthread_t firstCallbackThread;
	BOOL threadsDiffer;
	BOOL followRedirect;
	BOOL sawBodyProgress;
	int64_t lastBytesSent;
	int64_t lastBytesExpected;
	BOOL finishDownloadCalled;
	BOOL writeProgressCalled;
	NSURL *finishedLocation;
	NSData *finishedContents;
	int64_t lastWrittenTotal;
	NSInputStream *capturedInput;
	NSOutputStream *capturedOutput;
	BOOL readClosedCalled, writeClosedCalled;
	BOOL useCredentialForChallenge;
	int challengeCalls;
	BOOL sawSessionChallenge;
	fn_event *done;
}
@end

@implementation RecordingDelegate

- (void)URLSession:(NSURLSession *)session
	  dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
	if (responseCalls++ == 0) {
		firstCallbackThread = pthread_self();
	} else if (!pthread_equal(firstCallbackThread, pthread_self())) {
		threadsDiffer = YES;
	}
	[responseHead release];
	responseHead = [response retain];
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	if (dataCalls++ == 0) {
		firstCallbackThread = pthread_self();
	} else if (!pthread_equal(firstCallbackThread, pthread_self())) {
		threadsDiffer = YES;
	}
	if (body == nil) {
		body = [[NSMutableData alloc] init];
	}
	[body appendData:data];
}

- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
	newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler
{
	redirectResponse = [response retain];
	completionHandler(followRedirect ? request : nil);
}

- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
	sawBodyProgress = YES;
	lastBytesSent = totalBytesSent;
	lastBytesExpected = totalBytesExpectedToSend;
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
	finishDownloadCalled = YES;
	finishedLocation = [location retain];
	/* READ IT NOW: Apple removes the file when this call returns, which is the contract the test asserts. */
	finishedContents = [[NSData dataWithContentsOfURL:location] retain];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
	(void)bytesWritten;
	(void)totalBytesExpectedToWrite;
	writeProgressCalled = YES;
	lastWrittenTotal = totalBytesWritten;
}

- (void)URLSession:(NSURLSession *)session
	streamTask:(NSURLSessionStreamTask *)streamTask
didBecomeInputStream:(NSInputStream *)inputStream
      outputStream:(NSOutputStream *)outputStream
{
	capturedInput = [inputStream retain];
	capturedOutput = [outputStream retain];
	event_fire(done);
}

/* THE AUTHENTICATION DOORS, task first and session second, which is the ordering both headers state. The task's
 * answers with a Basic credential when the case asks for one; the session's only records that it was reached, so a case
 * can assert the task door won. */
- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
	(void)session;
	(void)task;
	(void)challenge;
	challengeCalls++;
	if (useCredentialForChallenge) {
		completionHandler(NSURLSessionAuthChallengeUseCredential,
				  [NSURLCredential credentialWithUser:@"agora"
							     password:@"secret"
							  persistence:NSURLCredentialPersistenceNone]);
	} else {
		completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
	}
}

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
	(void)session;
	(void)challenge;
	sawSessionChallenge = YES;
	completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)streamTask
{
	readClosedCalled = YES;
}

- (void)URLSession:(NSURLSession *)session writeClosedForStreamTask:(NSURLSessionStreamTask *)streamTask
{
	writeClosedCalled = YES;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
	completionCalls++;
	completionError = [error retain];
	event_fire(done);
}

- (void)dealloc
{
	[body release];
	[finishedLocation release];
	[finishedContents release];
	[capturedInput release];
	[capturedOutput release];
	[responseHead release];
	[redirectResponse release];
	[completionError release];
	[super dealloc];
}

@end

/* ---- the cases -------------------------------------------------------------- */

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	signal(SIGPIPE, SIG_IGN);

	/* 1. THE COMPLETION-HANDLER FORM, on the shared session (no delegate at all). */
	{
		struct server_job job;
		pthread_t thread;
		__block NSData *data = nil;
		__block NSURLResponse *response = nil;
		__block NSError *error = nil;
		__block fn_event done;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello", 0, 0);
		check(make_listener(&job.listener) == 0, "the completion-handler listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/one", job.listener.port];
		{
			NSURLSessionDataTask *task = [[NSURLSession sharedSession]
				dataTaskWithURL:[NSURL URLWithString:url]
			     completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
				data = [d retain];
				response = [r retain];
				error = [e retain];
				event_fire(&done);
			}];

			check([task state] == NSURLSessionTaskStateSuspended, "a new task is born suspended");
			check([task taskIdentifier] > 0, "and has a session-assigned identifier");
			[task resume];
			check([task state] == NSURLSessionTaskStateRunning, "resume moves it to running");
			check(event_wait(&done, 10), "the completion handler fires");
			pthread_join(thread, NULL);
			check(data != nil && [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
						autorelease] isEqualToString:@"hello"], "and carries the body");
			check([response isKindOfClass:[NSHTTPURLResponse class]] &&
			      [(NSHTTPURLResponse *)response statusCode] == 200, "with the HTTP response");
			check(error == nil, "and no error");
			check([task countOfBytesReceived] == 5, "the task counted the body bytes");
			check([task countOfBytesExpectedToReceive] == 5, "and the expected length from the header");
			check([task state] == NSURLSessionTaskStateCompleted, "and the task is completed");
			[data release];
			[response release];
		}
		event_destroy(&done);
	}

	/* 2. THE DELEGATE FORM on a session with a serial queue: every message arrives, on one thread, off this one. */
	{
		struct server_job job;
		pthread_t thread;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDataTask *task;
		__block fn_event done;
		NSString *url;
		pthread_t here = pthread_self();

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n"
				"Connection: close\r\n\r\nhello world", 0, 0);
		check(make_listener(&job.listener) == 0, "the delegate-form listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		check(session != nil, "a session with a delegate is made");
		check([session delegate] == delegate, "and retains the delegate it was given");
		check([session delegateQueue] == queue, "and reports the queue");
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/two", job.listener.port];
		task = [session dataTaskWithURL:[NSURL URLWithString:url]];
		check(task != nil, "the data-task factory answers a task");
		[task resume];
		check(event_wait(&done, 10), "the delegate hears the completion");
		pthread_join(thread, NULL);
		check(delegate->responseCalls == 1, "the response door was sent once");
		check(delegate->dataCalls >= 1, "data arrived through the data door");
		check(delegate->completionCalls == 1, "and completion exactly once");
		check(delegate->completionError == nil, "with no error");
		check(delegate->threadsDiffer == NO, "every callback ran on the serial queue, not on several threads");
		check(pthread_equal(delegate->firstCallbackThread, here) == 0, "and none of them on the calling thread");
		check(delegate->body != nil && [[[[NSString alloc] initWithData:delegate->body
								       encoding:NSUTF8StringEncoding] autorelease]
						isEqualToString:@"hello world"], "the delegate's body is the server's");
		check([task countOfBytesReceived] == 11, "the bytes are counted on the task too");
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		event_destroy(&done);
	}

	/* 3. A POST: the body is counted, and the transport reports its progress. */
	{
		struct server_job job;
		pthread_t thread;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSMutableURLRequest *request;
		NSURLSessionDataTask *task;
		__block fn_event done;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok", 0, sizeof job.captured);
		check(make_listener(&job.listener) == 0, "the POST listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/post", job.listener.port];
		request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
		[request setHTTPMethod:@"POST"];
		[request setHTTPBody:[@"payload" dataUsingEncoding:NSUTF8StringEncoding]];
		task = [session dataTaskWithRequest:request];
		check([task countOfBytesExpectedToSend] == 7, "the expected send count is the body's length");
		[task resume];
		check(event_wait(&done, 10), "the POST completes");
		pthread_join(thread, NULL);
		check(strstr(job.captured, "POST /post") != NULL, "the server saw the method and path");
		check(strstr(job.captured, "payload") != NULL, "and the body");
		check([task countOfBytesSent] == 7, "the task counted the bytes it sent");
		check(delegate->sawBodyProgress && delegate->lastBytesSent == 7 && delegate->lastBytesExpected == 7,
		      "and the upload-progress door reported them");
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		event_destroy(&done);
	}

	/* 4. A REDIRECT THE DELEGATE FOLLOWS: currentRequest moves, and the second server's body is the answer. */
	{
		struct server_job first, second;
		pthread_t t1, t2;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDataTask *task;
		__block fn_event done;
		NSString *url;

		event_init(&done);
		job_start(&second, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nfinal", 0, 0);
		check(make_listener(&second.listener) == 0, "the redirect target bound a port");
		{
			char response[512];

			snprintf(response, sizeof response,
				 "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:%d/final\r\n"
				 "Content-Length: 0\r\nConnection: close\r\n\r\n", second.listener.port);
			job_start(&first, response, 0, 0);
		}
		check(make_listener(&first.listener) == 0, "the redirect source bound a port");
		pthread_create(&t1, NULL, server_main, &first);
		pthread_create(&t2, NULL, server_main, &second);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		delegate->followRedirect = YES;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/start", first.listener.port];
		task = [session dataTaskWithURL:[NSURL URLWithString:url]];
		[task resume];
		check(event_wait(&done, 10), "the redirect run completes");
		pthread_join(t1, NULL);
		pthread_join(t2, NULL);
		check(delegate->redirectResponse != nil && [delegate->redirectResponse statusCode] == 302,
		      "the delegate was shown the 302");
		check([[[task currentRequest] URL].absoluteString hasSuffix:@"/final"],
		      "and currentRequest is the request the redirect chose");
		check(delegate->body != nil && [[[[NSString alloc] initWithData:delegate->body
								       encoding:NSUTF8StringEncoding] autorelease]
						isEqualToString:@"final"], "the final body is the answer");
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		event_destroy(&done);
	}

	/* 5. A REDIRECT THE DELEGATE REFUSES: the 3xx IS the answer, and currentRequest does not move. */
	{
		struct server_job first;
		pthread_t t1;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDataTask *task;
		__block fn_event done;
		NSString *url;

		event_init(&done);
		job_start(&first, "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/elsewhere\r\n"
				  "Content-Length: 0\r\nConnection: close\r\n\r\n", 0, 0);
		check(make_listener(&first.listener) == 0, "the refusing listener bound a port");
		pthread_create(&t1, NULL, server_main, &first);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		delegate->followRedirect = NO;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/refuse", first.listener.port];
		task = [session dataTaskWithURL:[NSURL URLWithString:url]];
		[task resume];
		check(event_wait(&done, 10), "the refused redirect completes");
		pthread_join(t1, NULL);
		check(delegate->completionError == nil, "a refused redirect is not an error");
		check([task response] != nil && [(NSHTTPURLResponse *)[task response] statusCode] == 302,
		      "the 3xx is the final response");
		check([[[task currentRequest] URL].absoluteString hasSuffix:@"/refuse"],
		      "and the request the task ran did not move");
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		event_destroy(&done);
	}

	/* 6. CANCELLATION: the task ends with NSURLErrorCancelled, and the state says so. */
	{
		struct server_job job;
		pthread_t thread;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDataTask *task;
		__block fn_event done;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello", 400, 0);
		check(make_listener(&job.listener) == 0, "the slow listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/slow", job.listener.port];
		task = [session dataTaskWithURL:[NSURL URLWithString:url]];
		[task resume];
		usleep(100 * 1000);
		[task cancel];
		check([task state] == NSURLSessionTaskStateCanceling || [task state] == NSURLSessionTaskStateCompleted,
		      "cancel moves the task out of running");
		check(event_wait(&done, 10), "the cancellation is reported");
		pthread_join(thread, NULL);
		check(delegate->completionError != nil &&
		      [delegate->completionError code] == NSURLErrorCancelled, "with NSURLErrorCancelled");
		check([task state] == NSURLSessionTaskStateCompleted, "and the task is completed");
		check([task error] != nil && [[task error] code] == NSURLErrorCancelled, "the task carries the error too");
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		event_destroy(&done);
	}

	/* 7. THE OUTSTANDING-TASK LIST: a running task is in it, and a completed one is not. */
	{
		struct server_job job;
		pthread_t thread;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDataTask *task;
		__block fn_event listed, after;
		__block NSUInteger during = 0, later = 0;
		__block BOOL arraysPresent = NO;
		NSString *url;

		event_init(&listed);
		event_init(&after);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok", 200, 0);
		check(make_listener(&job.listener) == 0, "the list listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:nil
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/list", job.listener.port];
		task = [session dataTaskWithURL:[NSURL URLWithString:url]
		       completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
			(void)d; (void)r; (void)e;
		}];
		[task resume];
		usleep(50 * 1000);
		[session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploads, NSArray *downloads) {
			during = [dataTasks count];
			arraysPresent = (uploads != nil && downloads != nil);
			event_fire(&listed);
		}];
		check(event_wait(&listed, 10), "the task list answered");
		check(during == 1, "a running task is in the outstanding list");
		check(arraysPresent, "and the other two lists are arrays, not nil");
		usleep(500 * 1000);
		[session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploads, NSArray *downloads) {
			later = [dataTasks count];
			(void)uploads; (void)downloads;
			event_fire(&after);
		}];
		check(event_wait(&after, 10), "the second list answered");
		check(later == 0, "a finished task has left the outstanding list");
		pthread_join(thread, NULL);
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		event_destroy(&listed);
		event_destroy(&after);
	}

	/* 8. THE TASK'S OWN VALUE DOORS, and the background refusal. */
	{
		NSURLSessionDataTask *a;
		NSURLSessionDataTask *b;
		NSURLSessionDataTask *copy;
		NSURLSessionConfiguration *background;
		NSURLSession *refused;

		a = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/a"]];
		b = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/b"]];
		check([a taskIdentifier] != [b taskIdentifier], "two tasks get two identifiers");
		[a setTaskDescription:@"probe"];
		check([[a taskDescription] isEqualToString:@"probe"], "the description reads back");
		[a setPriority:2.0f];
		check([a priority] == 1.0f, "priority is clamped to Apple's range");
		[a setPriority:-1.0f];
		check([a priority] == 0.0f, "at both ends");
		[a setPriority:NSURLSessionTaskPriorityHigh];
		check([a priority] == NSURLSessionTaskPriorityHigh, "and the named constants are on it");
		copy = [[a copy] autorelease];
		check(copy != a && [copy state] == NSURLSessionTaskStateSuspended &&
		      [[[copy currentRequest] URL] isEqual:[[a currentRequest] URL]] &&
		      [[copy taskDescription] isEqual:@"probe"], "a copy is a new suspended task with the same request");

		background = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.example.refused"];
		refused = [NSURLSession sessionWithConfiguration:background];
		check(refused == nil, "a background session is refused by name rather than faked");
		[a release];
		[b release];
	}

	/* 9. A DOWNLOAD WITH A DELEGATE: the file exists and carries the body INSIDE the callback, and is gone after. */
	{
		struct server_job job;
		pthread_t thread;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDownloadTask *task;
		__block fn_event done;
		NSURL *finishedURL;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nConnection: close\r\n\r\nhello download", 0, 0);
		check(make_listener(&job.listener) == 0, "the download listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/download", job.listener.port];
		task = [session downloadTaskWithURL:[NSURL URLWithString:url]];
		[task resume];
		check(event_wait(&done, 10), "the download completes");
		pthread_join(thread, NULL);
		check(delegate->finishDownloadCalled, "the download delegate was handed the file");
		check(delegate->finishedContents != nil && [[[[NSString alloc] initWithData:delegate->finishedContents
									     encoding:NSUTF8StringEncoding] autorelease]
							    isEqualToString:@"hello download"],
		      "and the file held the body at the moment of the call");
		check(delegate->writeProgressCalled && delegate->lastWrittenTotal == 14,
		      "the write-progress door reported the bytes");
		check(delegate->completionError == nil, "and the task completed without error");
		finishedURL = [delegate->finishedLocation retain];
		usleep(200 * 1000);
		check([[NSFileManager defaultManager] fileExistsAtPath:[finishedURL path]] == NO,
		      "the file is removed once the delegate call returns");
		[finishedURL release];
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		event_destroy(&done);
	}

	/* 10. A DOWNLOAD WITH A COMPLETION HANDLER: same file, delivered to the block, and removed after it returns. */
	{
		struct server_job job;
		pthread_t thread;
		__block fn_event done;
		__block NSURL *location = nil;
		__block NSData *contents = nil;
		__block NSError *completionError = nil;
		NSURLSessionDownloadTask *task;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nfinal", 0, 0);
		check(make_listener(&job.listener) == 0, "the completion-download listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/d2", job.listener.port];
		task = [[NSURLSession sharedSession]
			downloadTaskWithURL:[NSURL URLWithString:url]
			  completionHandler:^(NSURL *l, NSURLResponse *r, NSError *e) {
			(void)r;
			location = [l retain];
			contents = [[NSData dataWithContentsOfURL:l] retain];
			completionError = [e retain];
			event_fire(&done);
		}];
		[task resume];
		check(event_wait(&done, 10), "the download completion handler fires");
		pthread_join(thread, NULL);
		check(location != nil && contents != nil &&
		      [[[[NSString alloc] initWithData:contents encoding:NSUTF8StringEncoding] autorelease]
			isEqualToString:@"final"], "with a readable file carrying the body");
		check(completionError == nil, "and no error");
		/* APPLE'S RULE IS "REMOVED WHEN THE HANDLER RETURNS", so the check must let the block finish. */
		usleep(200 * 1000);
		check([[NSFileManager defaultManager] fileExistsAtPath:[location path]] == NO,
		      "the file is removed once the handler returns");
		[location release];
		[contents release];
		[completionError release];
		event_destroy(&done);
	}

	/* 11. AN UPLOAD FROM DATA: the body reaches the server, and the response is the task's answer. */
	{
		struct server_job job;
		pthread_t thread;
		__block fn_event done;
		__block NSData *data = nil;
		__block NSError *completionError = nil;
		NSMutableURLRequest *request;
		NSURLSessionUploadTask *task;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok", 0, sizeof job.captured);
		check(make_listener(&job.listener) == 0, "the upload listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/u", job.listener.port];
		request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
		[request setHTTPMethod:@"POST"];
		task = [[NSURLSession sharedSession]
			uploadTaskWithRequest:request
				     fromData:[@"uploaded-body" dataUsingEncoding:NSUTF8StringEncoding]
			    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
			(void)r;
			data = [d retain];
			completionError = [e retain];
			event_fire(&done);
		}];
		check(task != nil && [task isKindOfClass:[NSURLSessionUploadTask class]], "an upload task is made");
		[task resume];
		check(event_wait(&done, 10), "the upload completes");
		pthread_join(thread, NULL);
		check(strstr(job.captured, "POST /u") != NULL, "the server saw the POST");
		check(strstr(job.captured, "uploaded-body") != NULL, "with the data body the caller supplied");
		check(data != nil && [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]
				      isEqualToString:@"ok"] && completionError == nil, "and answered the response body");
		[data release];
		[completionError release];
		event_destroy(&done);
	}

	/* 12. AN UPLOAD FROM A FILE, and the two refusals: a streamed body and resume data. */
	{
		struct server_job job;
		pthread_t thread;
		__block fn_event done;
		NSMutableURLRequest *request;
		NSString *file = @"/tmp/agora-session-upload.txt";
		NSURLSessionUploadTask *task;
		NSString *url;

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok", 0, sizeof job.captured);
		check(make_listener(&job.listener) == 0, "the file-upload listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		[[@"from-file" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:file atomically:NO];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/uf", job.listener.port];
		request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
		[request setHTTPMethod:@"POST"];
		task = [[NSURLSession sharedSession]
			uploadTaskWithRequest:request
				     fromFile:[NSURL fileURLWithPath:file]
			    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
			(void)d; (void)r; (void)e;
			event_fire(&done);
		}];
		[task resume];
		check(event_wait(&done, 10), "the file upload completes");
		pthread_join(thread, NULL);
		check(strstr(job.captured, "from-file") != NULL, "the file's bytes were the body");
		[[NSFileManager defaultManager] removeItemAtPath:file error:NULL];

		url = [NSString stringWithFormat:@"http://127.0.0.1:1/never", 0];
		request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/never"]];
		check([[NSURLSession sharedSession] uploadTaskWithStreamedRequest:request] == nil,
		      "a streamed upload is refused by name (no body-stream read in the transport)");
		check([[NSURLSession sharedSession] downloadTaskWithResumeData:[NSData data]] == nil,
		      "a resume-data download is refused by name");
		event_destroy(&done);
	}

	/* 13. A DOWNLOAD CANCELLED WITH RESUME DATA: the handler is told nil, and the task is cancelled. */
	{
		struct server_job job;
		pthread_t thread;
		__block fn_event resumed;
		__block fn_event done;
		__block BOOL handlerCalled = NO;
		__block NSData *resumeData = nil;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionDownloadTask *task;
		NSString *url;

		event_init(&resumed);
		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello", 400, 0);
		check(make_listener(&job.listener) == 0, "the slow-download listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &done;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/slowdownload", job.listener.port];
		task = [session downloadTaskWithURL:[NSURL URLWithString:url]];
		[task resume];
		usleep(100 * 1000);
		[task cancelByProducingResumeData:^(NSData *d) {
			handlerCalled = YES;
			resumeData = [d retain];
			event_fire(&resumed);
		}];
		check(event_wait(&resumed, 10), "the resume-data handler is called");
		check(handlerCalled && resumeData == nil, "with nil, because there is no resumable transfer");
		check(event_wait(&done, 10), "and the task completes");
		pthread_join(thread, NULL);
		check(delegate->completionError != nil && [delegate->completionError code] == NSURLErrorCancelled,
		      "as a cancellation");
		[session finishTasksAndInvalidate];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		[delegate release];
		[resumeData release];
		event_destroy(&resumed);
		event_destroy(&done);
	}

	/* 14. THE TASK LISTS PARTITION BY KIND: an upload is not a data task, a download is neither. */
	{
		struct server_job job;
		pthread_t thread;
		NSURLSession *session;
		NSURLSessionUploadTask *task;
		__block fn_event listed;
		__block NSUInteger datas = 0, uploads = 0, downloads = 0;
		NSMutableURLRequest *request;
		NSString *url;

		event_init(&listed);
		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok", 300, 0);
		check(make_listener(&job.listener) == 0, "the partition listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:nil
						   delegateQueue:nil];
		url = [NSString stringWithFormat:@"http://127.0.0.1:%d/partition", job.listener.port];
		request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
		[request setHTTPMethod:@"POST"];
		task = [session uploadTaskWithRequest:request fromData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]];
		[task resume];
		usleep(50 * 1000);
		[session getTasksWithCompletionHandler:^(NSArray *d, NSArray *u, NSArray *dl) {
			datas = [d count];
			uploads = [u count];
			downloads = [dl count];
			event_fire(&listed);
		}];
		check(event_wait(&listed, 10), "the partition list answered");
		check(datas == 0 && uploads == 1 && downloads == 0,
		      "an outstanding upload is an upload, not a data task");
		usleep(600 * 1000);
		[session finishTasksAndInvalidate];
		pthread_join(thread, NULL);
		event_destroy(&listed);
	}

	/* 15. A STREAM TASK: a write and a read over a connected socket, in the order they were asked for. */
	{
		struct server_job job;
		pthread_t thread;
		NSURLSession *session;
		NSURLSessionStreamTask *task;
		__block fn_event wrote, readBack;
		__block NSError *writeError = nil;
		__block NSData *readData = nil;
		__block NSError *readError = nil;

		event_init(&wrote);
		event_init(&readBack);
		job_start(&job, NULL, 4, 0);
		check(make_listener(&job.listener) == 0, "the stream listener bound a port");
		pthread_create(&thread, NULL, echo_stream_server, &job);
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:nil
						   delegateQueue:nil];
		task = [session streamTaskWithHostName:@"127.0.0.1" port:job.listener.port];
		check(task != nil && [task isKindOfClass:[NSURLSessionStreamTask class]], "a stream task is made");
		[task resume];
		usleep(100 * 1000);
		[task writeData:[@"ping" dataUsingEncoding:NSUTF8StringEncoding] timeout:5.0
	     completionHandler:^(NSError *e) {
			writeError = [e retain];
			event_fire(&wrote);
		}];
		check(event_wait(&wrote, 10), "the write completes");
		check(writeError == nil, "without error");
		[task readDataOfMinLength:4 maxLength:4 timeout:5.0
		completionHandler:^(NSData *d, BOOL atEOF, NSError *e) {
			(void)atEOF;
			readData = [d retain];
			readError = [e retain];
			event_fire(&readBack);
		}];
		check(event_wait(&readBack, 10), "the read completes");
		pthread_join(thread, NULL);
		check(readError == nil && readData != nil &&
		      [[[[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding] autorelease]
			isEqualToString:@"pong"], "and answers the server's bytes");
		[task cancel];
		[readData release];
		[readError release];
		[writeError release];
		event_destroy(&wrote);
		event_destroy(&readBack);
	}

	/* 16. captureStreams: the socket becomes a stream pair, handed to the delegate, and the task completes. */
	{
		struct server_job job;
		pthread_t thread;
		RecordingDelegate *delegate;
		NSOperationQueue *queue;
		NSURLSession *session;
		NSURLSessionStreamTask *task;
		__block fn_event handed;

		event_init(&handed);
		job_start(&job, NULL, 4, 0);
		check(make_listener(&job.listener) == 0, "the capture listener bound a port");
		pthread_create(&thread, NULL, greeting_stream_server, &job);
		delegate = [[RecordingDelegate alloc] init];
		delegate->done = &handed;
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:1];
		session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
							delegate:delegate
						   delegateQueue:queue];
		task = [session streamTaskWithHostName:@"127.0.0.1" port:job.listener.port];
		[task resume];
		usleep(100 * 1000);
		[task captureStreams];
		check(event_wait(&handed, 10), "the capture hands the streams over");
		pthread_join(thread, NULL);
		check(delegate->capturedInput != nil && delegate->capturedOutput != nil,
		      "both streams are real");
		{
			uint8_t buffer[8];
			NSInteger got;

			[delegate->capturedInput open];
			got = [delegate->capturedInput read:buffer maxLength:4];
			check(got == 4 && memcmp(buffer, "pong", 4) == 0,
			      "and the input stream reads the bytes the server sent over the captured socket");
			[delegate->capturedInput close];
		}
		check([task state] == NSURLSessionTaskStateCompleted, "and the task is complete once they are handed over");
		[session finishTasksAndInvalidate];
		[delegate release];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		event_destroy(&handed);
	}

	/* 17. THE TASK-SCOPED CACHE: store, get and remove through the task doors. */
	{
		NSURLCache *cache = [NSURLCache sharedURLCache];
		NSURLSessionDataTask *task = [[NSURLSession sharedSession]
			dataTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/cached"]];
		NSURLResponse *response = [[[NSURLResponse alloc] initWithURL:[[task currentRequest] URL]
								   MIMEType:@"text/plain"
						      expectedContentLength:2
							   textEncodingName:nil] autorelease];
		NSCachedURLResponse *cached = [[[NSCachedURLResponse alloc]
			initWithResponse:response data:[@"hi" dataUsingEncoding:NSUTF8StringEncoding]] autorelease];
		__block fn_event got, removed;
		__block NSCachedURLResponse *answer = nil;
		__block id removedAnswer = (id)0x1;

		event_init(&got);
		event_init(&removed);
		[cache storeCachedResponse:cached forDataTask:task];
		[cache getCachedResponseForDataTask:task completionHandler:^(NSCachedURLResponse *c) {
			answer = [c retain];
			event_fire(&got);
		}];
		check(event_wait(&got, 10), "the task-scoped cache answers");
		check(answer != nil && [[answer data] isEqual:[@"hi" dataUsingEncoding:NSUTF8StringEncoding]],
		      "with the response stored for the task's request");
		[cache removeCachedResponseForDataTask:task];
		[cache getCachedResponseForDataTask:task completionHandler:^(NSCachedURLResponse *c) {
			removedAnswer = c;
			event_fire(&removed);
		}];
		check(event_wait(&removed, 10), "and answers after the removal");
		check(removedAnswer == nil, "with nothing");
		[answer release];
		event_destroy(&got);
		event_destroy(&removed);
	}

	/* 18. THE TASK-SCOPED COOKIES, and the group-container refusal. */
	{
		NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
		NSURLSessionDataTask *task = [[NSURLSession sharedSession]
			dataTaskWithURL:[NSURL URLWithString:@"http://cookies.example/path"]];
		NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"name", NSHTTPCookieName, @"value", NSHTTPCookieValue,
				@"/", NSHTTPCookiePath, @"cookies.example", NSHTTPCookieDomain, nil]];
		__block fn_event got;
		__block NSArray *answer = nil;

		event_init(&got);
		[store storeCookies:[NSArray arrayWithObject:cookie] forTask:task];
		[store getCookiesForTask:task completionHandler:^(NSArray *cookies) {
			answer = [cookies retain];
			event_fire(&got);
		}];
		check(event_wait(&got, 10), "the task-scoped cookie doors answer");
		check([answer count] == 1 && [[[answer objectAtIndex:0] name] isEqualToString:@"name"],
		      "with the cookie stored for the task's URL");
		check([NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:@"group.example"] == nil,
		      "the group-container store is refused by name");
		[answer release];
		event_destroy(&got);
	}

	/* 19. THE TASK-SCOPED CREDENTIALS: visible to the task, invisible to the shared store. */
	{
		NSURLCredentialStorage *storage = [NSURLCredentialStorage sharedCredentialStorage];
		NSURLSessionDataTask *task = [[NSURLSession sharedSession]
			dataTaskWithURL:[NSURL URLWithString:@"http://auth.example/"]];
		NSURLProtectionSpace *space = [[[NSURLProtectionSpace alloc] initWithHost:@"auth.example"
										    port:80
										protocol:@"http"
										   realm:@"realm"
									  authenticationMethod:NSURLAuthenticationMethodHTTPBasic] autorelease];
		NSURLCredential *credential = [NSURLCredential credentialWithUser:@"user"
									 password:@"secret"
								      persistence:NSURLCredentialPersistenceNone];
		__block fn_event got;
		__block NSDictionary *answer = nil;

		event_init(&got);
		[storage setCredential:credential forProtectionSpace:space task:task];
		[storage getCredentialsForProtectionSpace:space task:task completionHandler:^(NSDictionary *credentials) {
			answer = [credentials retain];
			event_fire(&got);
		}];
		check(event_wait(&got, 10), "the task-scoped credential doors answer");
		check([answer count] == 1, "with the credential set for the task");
		check([[storage allCredentials] objectForKey:space] == nil,
		      "and the shared store did not learn it");
		[answer release];
		event_destroy(&got);
	}

	/* 20. THE PROTOCOL'S TASK DOORS: the loader's own protocol answers them. */
	{
		NSURLSessionDataTask *task = [[NSURLSession sharedSession]
			dataTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/protocol"]];
		FNCURLURLProtocol *protocol;

		check([FNCURLURLProtocol canInitWithTask:task], "the transport claims the task's request");
		protocol = [[FNCURLURLProtocol alloc] initWithTask:task cachedResponse:nil client:nil];
		check(protocol != nil && [protocol task] == task, "and an instance made for the task answers -task");
		[protocol release];
	}


	/* 21. THE SESSION'S COOKIE STORE IS THE ONE THE TRANSFER USES. W3 recorded this as an honest debt: the transport
	 * kept cookies in the process-wide store and a session's -HTTPCookieStorage was configuration nothing consulted.
	 * Now a Set-Cookie lands in the configured store, the shared store stays empty, and a seeded cookie is SENT. */
	{
		struct server_job job;
		pthread_t thread;
		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
		NSHTTPCookieStorage *privateStore = [[[NSHTTPCookieStorage alloc] init] autorelease];
		NSHTTPCookieStorage *shared = [NSHTTPCookieStorage sharedHTTPCookieStorage];
		NSURLSession *session;
		__block fn_event done;
		__block NSData *body = nil;
		NSURL *url;
		NSHTTPCookie *seeded;

		[shared removeCookiesSinceDate:[NSDate distantPast]];
		[configuration setHTTPCookieStorage:privateStore];
		session = [NSURLSession sessionWithConfiguration:configuration];

		event_init(&done);
		job_start(&job, "HTTP/1.1 200 OK\r\nSet-Cookie: agora=1; Path=/\r\nContent-Length: 2\r\n"
				"Connection: close\r\n\r\nok", 0, 0);
		check(make_listener(&job.listener) == 0, "the cookie listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/cookie", job.listener.port]];
		[[session dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
			(void)r;
			(void)e;
			body = [d retain];
			event_fire(&done);
		}] resume];
		check(event_wait(&done, 10), "the cookie response arrives");
		pthread_join(thread, NULL);
		check(body != nil && [body length] == 2, "with its body");
		check([[privateStore cookiesForURL:url] count] == 1,
		      "a Set-Cookie lands in the session's configured store");
		check([[shared cookiesForURL:url] count] == 0,
		      "and not in the process-wide store");

		/* THE SENDING HALF: seed the configured store with a cookie for the next request's host and path. */
		seeded = [NSHTTPCookie cookieWithProperties:
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"agora", NSHTTPCookieName,
				@"sent", NSHTTPCookieValue,
				[url host], NSHTTPCookieDomain,
				@"/", NSHTTPCookiePath,
				nil]];
		check(seeded != nil, "a cookie can be made for the host");
		[privateStore setCookie:seeded];
		[body release];
		body = nil;

		job_start(&job, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
			  0, sizeof job.captured);
		check(make_listener(&job.listener) == 0, "the seeded-cookie listener bound a port");
		pthread_create(&thread, NULL, server_main, &job);
		url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/again", job.listener.port]];
		[[session dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
			(void)r;
			(void)e;
			body = [d retain];
			event_fire(&done);
		}] resume];
		check(event_wait(&done, 10), "the seeded-cookie response arrives");
		pthread_join(thread, NULL);
		check(strstr(job.captured, "Cookie: agora=sent") != NULL,
		      "a stored cookie is sent by the transfer");
		[body release];
		[session invalidateAndCancel];
		event_destroy(&done);
	}

	/* 22. THE AUTHENTICATION CHALLENGE, END TO END. A server answers 401 with a Basic challenge; the TASK's delegate
	 * door answers with a credential; the transport re-issues ONCE with it and the server's second request carries
	 * Authorization. Before this case the dispatch was implemented and untested - and the wait it needed was missing,
	 * so a 401 through a session never retried. */
	{
		struct auth_job job;
		pthread_t thread;
		RecordingDelegate *delegate = [[RecordingDelegate alloc] init];
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
		NSURLSession *session;
		__block fn_event done;
		NSURL *url;

		event_init(&done);
		delegate->done = &done;
		delegate->useCredentialForChallenge = YES;
		[queue setMaxConcurrentOperationCount:1];

		memset(&job, 0, sizeof job);
		snprintf(job.challenge, sizeof job.challenge,
			 "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"agora\"\r\n"
			 "Content-Length: 0\r\nConnection: close\r\n\r\n");
		snprintf(job.final, sizeof job.final,
			 "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\nauthenticated");
		check(make_listener(&job.listener) == 0, "the challenge listener bound a port");
		pthread_create(&thread, NULL, auth_server_main, &job);

		session = [NSURLSession sessionWithConfiguration:configuration
							delegate:delegate
						   delegateQueue:queue];
		url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/auth", job.listener.port]];
		[[session dataTaskWithURL:url] resume];
		check(event_wait(&done, 20), "the challenged transfer completes");
		pthread_join(thread, NULL);
		check(delegate->challengeCalls == 1, "the task's challenge door was consulted once");
		check(!delegate->sawSessionChallenge, "and the session's door was not needed");
		check(job.requests == 2, "the server saw the first request and the re-issue");
		check(strstr(job.seen_auth, "Authorization: Basic YWdvcmE6c2VjcmV0") != NULL,
		      "the re-issued request carries the Basic credential");
		check(delegate->body != nil &&
		      [[[[NSString alloc] initWithData:delegate->body encoding:NSUTF8StringEncoding] autorelease]
			isEqualToString:@"authenticated"],
		      "and the final body is the authenticated response");
		check(delegate->completionError == nil && [delegate->responseHead isKindOfClass:[NSHTTPURLResponse class]] &&
		      [(NSHTTPURLResponse *)delegate->responseHead statusCode] == 200,
		      "with a 200 and no error");
		[session invalidateAndCancel];
		[delegate release];
		/* NO CALLBACK MAY OUTLIVE THE EVENT IT FIRES: the section waited for ONE message, and a later one
		 * (a stream's completion behind didBecomeInputStream:, a cancelled task's completion) can still be
		 * queued. Draining is what makes the event's lifetime the section's. */
		[queue waitUntilAllOperationsAreFinished];
		[queue release];
		event_destroy(&done);
	}

	printf("foundation_10_11_url_session: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
