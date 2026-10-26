/*
 * NSURLSession.m
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The design is in the header; what is here is the task state machine, the protocol client conformance that turns
 * the transport's seven doors into the session delegate's messages, and the bookkeeping that makes invalidation and
 * the task lists mean something.
 *
 * THE ONE ARRANGEMENT WORTH STATING TWICE: a TASK IS AN `NSURLProtocolClient`. `+fnProtocolClassForRequest:` names the
 * class that claims the request, one instance is made with the task as its client, and `-startLoading` begins the
 * transfer on the transport's own thread. Every callback after that arrives on that thread, so every delegate message
 * is handed to the session's queue before it is sent — that is what makes the queue a contract rather than a detail.
 *
 * AND THE ENDING OWNS THE LIFETIME, exactly as `NSURLConnection` records it: the session keeps an outstanding task
 * alive, the protocol keeps its client alive, and the ending is the moment both are given up. Every ending takes a
 * guard retain first, because the teardown can be the release that frees the task while it is the receiver.
 */

#import <Foundation/NSURLSession.h>
#import <Foundation/NSURLProtocol.h>
#import <Foundation/NSURLRequest.h>
#import <Foundation/NSURLResponse.h>
#import <Foundation/NSError.h>
#import <Foundation/NSURLError.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSData.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSOperationQueue.h>
#import <Foundation/NSURLAuthenticationChallenge.h>	/* the sender protocol's answer doors */
#import <Foundation/NSURLCredential.h>
#import <Foundation/NSURLCache.h>
#import <Foundation/NSHTTPCookieStorage.h>
#import <Foundation/NSURLCredentialStorage.h>
#import <Foundation/NSURLProtectionSpace.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSAutoreleasePool.h>

#include <Block.h>		/* Block_copy/Block_release: a block is not owned with a message send */
#include <stdio.h>		/* the FOUNDATION-REFUSE line */

const int64_t NSURLSessionTransferSizeUnknown = -1LL;
const float NSURLSessionTaskPriorityDefault = 0.5f;
const float NSURLSessionTaskPriorityLow = 0.25f;
const float NSURLSessionTaskPriorityHigh = 0.75f;

static NSError *fn_url_error(NSInteger code, NSString *description)
{
	return [NSError errorWithDomain:NSURLErrorDomain
				   code:code
			       userInfo:(description != nil
					 ? [NSDictionary dictionaryWithObject:description
								       forKey:NSLocalizedDescriptionKey]
					 : nil)];
}

/* ---- private interface ------------------------------------------------------ */

@class NSURLSession;

@interface NSURLSession (FNPrivate)
- (NSUInteger)fnNextTaskIdentifier;
- (NSOperationQueue *)fnDelegateQueue;
- (BOOL)fnDelegateRespondsTo:(SEL)selector;
- (void)fnSendToDelegate:(SEL)selector block:(void (^)(id delegate))work;
- (void)fnRegisterTask:(NSURLSessionTask *)task;
- (void)fnTaskDidFinish:(NSURLSessionTask *)task;
- (void)fnTaskDidBecomeInvalid:(NSURLSessionTask *)task;
@end

@interface NSURLSessionTask () <NSURLProtocolClient>
- (instancetype)fnInitWithSession:(NSURLSession *)session
			  request:(NSURLRequest *)request
		       completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
- (void)fnStartTransfer;
- (void)fnFinishWithError:(NSError *)error;
- (void)fnOrphan;
@end

@implementation NSURLSession

/* ---- the factories ---------------------------------------------------------- */

static NSURLSession *fn_sharedSession = nil;

+ (NSURLSession *)sharedSession
{
	/* ONE SLOT, WRITTEN ONCE: the shared session has no delegate and its own serial queue, so a completion handler
	 * has somewhere to run even when nothing else in the process cares. */
	if (fn_sharedSession == nil) {
		fn_sharedSession = [[NSURLSession alloc] fnInitWithConfiguration:
					[NSURLSessionConfiguration defaultSessionConfiguration]
								      delegate:nil
								 delegateQueue:nil];
	}
	return fn_sharedSession;
}

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
{
	return [self sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];
}

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
				  delegate:(id<NSURLSessionDelegate>)delegate
			     delegateQueue:(NSOperationQueue *)queue
{
	/* A BACKGROUND CONFIGURATION IS REFUSED BY NAME, not with a session that would pretend to survive a process
	 * it cannot: this tree has no background-transfer daemon, and the plan's §4.1 says so. */
	if ([[configuration identifier] length] > 0) {
		fprintf(stderr, "FOUNDATION-REFUSE: -[NSURLSession sessionWithConfiguration:delegate:delegateQueue:] was "
				"handed the background configuration \"%s\"; this system has no background-transfer "
				"daemon, so no session was made\n",
			[[configuration identifier] UTF8String]);
		return nil;
	}
	return [[[self alloc] fnInitWithConfiguration:configuration delegate:delegate delegateQueue:queue] autorelease];
}

- (instancetype)fnInitWithConfiguration:(NSURLSessionConfiguration *)configuration
			       delegate:(id<NSURLSessionDelegate>)delegate
			  delegateQueue:(NSOperationQueue *)queue
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* THE CONFIGURATION IS COPIED at creation, which is the reason the class copies its own mutable values: the
	 * caller may keep editing the object it handed over. */
	_configuration = [configuration copy];
	_delegate = [delegate retain];
	if (queue != nil) {
		_delegateQueue = [queue retain];
	} else {
		_delegateQueue = [[NSOperationQueue alloc] init];
		[_delegateQueue setMaxConcurrentOperationCount:1];
	}
	_tasks = [[NSMutableArray alloc] init];
	_nextTaskIdentifier = 1;
	return self;
}

- (void)dealloc
{
	/* THE TASKS ARE ORPHANED RATHER THAN CANCELLED THROUGH THE SESSION, because `-cancel` would call back into a
	 * session that is already going away. */
	NSArray *tasks = [_tasks copy];

	[tasks makeObjectsPerformSelector:@selector(fnOrphan)];
	[tasks release];
	[_tasks release];
	[_configuration release];
	[_delegate release];
	[_delegateQueue release];
	[_sessionDescription release];
	[super dealloc];
}

/* ---- the properties --------------------------------------------------------- */

- (NSOperationQueue *)delegateQueue { return _delegateQueue; }
- (id<NSURLSessionDelegate>)delegate { return _delegate; }
- (NSURLSessionConfiguration *)configuration { return _configuration; }
- (NSString *)sessionDescription { return _sessionDescription; }

- (void)setSessionDescription:(NSString *)description
{
	NSString *copied = [description copy];

	[_sessionDescription release];
	_sessionDescription = copied;
}

/* ---- the task factories ----------------------------------------------------- */

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
{
	return (NSURLSessionDataTask *)[self fnTaskOfClass:[NSURLSessionDataTask class]
						  request:request
					       completion:nil];
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
{
	return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
			    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
	return (NSURLSessionDataTask *)[self fnTaskOfClass:[NSURLSessionDataTask class]
						  request:request
					       completion:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
		       completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
	return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:completionHandler];
}

- (NSURLSessionTask *)fnTaskOfClass:(Class)taskClass
			    request:(NSURLRequest *)request
			 completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion
{
	NSURLSessionTask *task;

	if (_invalidated) {
		/* APPLE'S RULE: an invalidated session creates no new task. Answering nil is the documented shape. */
		fprintf(stderr, "FOUNDATION-REFUSE: a task was asked of a session that has been invalidated\n");
		return nil;
	}
	task = [[taskClass alloc] fnInitWithSession:self request:request completion:completion];
	[self fnRegisterTask:task];
	return [task autorelease];
}

/* ---- invalidation and the task lists ---------------------------------------- */

- (void)finishTasksAndInvalidate
{
	_invalidated = 1;
	[self fnMaybeSendInvalidation];
}

- (void)invalidateAndCancel
{
	NSArray *outstanding = [_tasks copy];

	_invalidated = 1;
	_cancelOnInvalidate = 1;
	[outstanding makeObjectsPerformSelector:@selector(cancel)];
	[outstanding release];
	[self fnMaybeSendInvalidation];
}

- (void)fnMaybeSendInvalidation
{
	if (!_invalidated || _invalidationSent || [_tasks count] > 0) {
		return;
	}
	_invalidationSent = 1;
	if (_delegate != nil) {
		id delegate = _delegate;

		[self fnSendToDelegate:@selector(URLSession:didBecomeInvalidWithError:)
				 block:^(id d) {
			[d URLSession:self didBecomeInvalidWithError:nil];
			(void)delegate;
		}];
	}
}

- (void)resetWithCompletionHandler:(void (^)(void))completionHandler
{
	/* THE CONFIGURATION'S STORES ARE WHAT "EMPTY" MEANS, and each is emptied through the door it has: the cache
	 * discards its entries, the cookie store forgets everything before now, and the credential store removes each
	 * credential it can enumerate. Doing it through the PROPERTIES keeps a configuration that replaced a store
	 * honest — the session empties the stores it was given, not the process's. */
	NSURLCache *cache = [_configuration URLCache];
	NSHTTPCookieStorage *cookies = [_configuration HTTPCookieStorage];
	NSURLCredentialStorage *credentials = [_configuration URLCredentialStorage];
	NSDictionary *all;

	if (cache != nil) {
		[cache removeAllCachedResponses];
	}
	if (cookies != nil) {
		[cookies removeCookiesSinceDate:[NSDate distantPast]];
	}
	all = (credentials != nil ? [credentials allCredentials] : nil);
	for (NSURLProtectionSpace *space in all) {
		NSDictionary *forSpace = [all objectForKey:space];

		for (id key in forSpace) {
			NSURLCredential *credential = [forSpace objectForKey:key];

			[credentials removeCredential:credential forProtectionSpace:space];
		}
	}
	if (completionHandler != nil) {
		[_delegateQueue addOperationWithBlock:^{
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

			completionHandler();
			[pool release];
		}];
	}
}

- (void)flushWithCompletionHandler:(void (^)(void))completionHandler
{
	/* A DOCUMENTED NO-OP, AND THAT IS THE HONEST ANSWER: nothing in this engine buffers writes behind the caller,
	 * so "flush" has nothing to make happen. The completion still runs on the delegate queue, because a caller
	 * that asked for a callback gets one. */
	if (completionHandler != nil) {
		[_delegateQueue addOperationWithBlock:^{
			completionHandler();
		}];
	}
}

- (void)getTasksWithCompletionHandler:(void (^)(NSArray *, NSArray *, NSArray *))completionHandler
{
	NSArray *snapshot = [_tasks copy];

	if (completionHandler == nil) {
		[snapshot release];
		return;
	}
	[_delegateQueue addOperationWithBlock:^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		/* ONLY DATA TASKS EXIST IN THIS SLICE, so the two other arrays are empty rather than absent: a caller
		 * that inspects them sees "none of that kind", which is true. */
		completionHandler(snapshot, [NSArray array], [NSArray array]);
		[snapshot release];
		[pool release];
	}];
}

- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray *))completionHandler
{
	NSArray *snapshot = [_tasks copy];

	if (completionHandler == nil) {
		[snapshot release];
		return;
	}
	[_delegateQueue addOperationWithBlock:^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		completionHandler(snapshot);
		[snapshot release];
		[pool release];
	}];
}

/* ---- the private bookkeeping ------------------------------------------------ */

- (NSUInteger)fnNextTaskIdentifier
{
	return _nextTaskIdentifier++;
}

- (NSOperationQueue *)fnDelegateQueue
{
	return _delegateQueue;
}

- (BOOL)fnDelegateRespondsTo:(SEL)selector
{
	return _delegate != nil && [_delegate respondsToSelector:selector];
}

- (void)fnSendToDelegate:(SEL)selector block:(void (^)(id))work
{
	id delegate = _delegate;

	if (delegate == nil || ![delegate respondsToSelector:selector]) {
		return;
	}
	[delegate retain];
	[_delegateQueue addOperationWithBlock:^{
		work(delegate);
		[delegate release];
	}];
}

- (void)fnRegisterTask:(NSURLSessionTask *)task
{
	/* **A SESSION STAYS ALIVE WHILE IT HAS OUTSTANDING TASKS**, which is Apple's documented rule and also the only
	 * thing that keeps the task's unretained session pointer valid when a caller lets go of the session. The retain
	 * is balanced by an AUTORELEASE on finish, because this method may be called from inside the session's own
	 * method and a plain release could free it under that frame. */
	[_tasks addObject:task];
	[self retain];
}

- (void)fnTaskDidFinish:(NSURLSessionTask *)task
{
	[_tasks removeObjectIdenticalTo:task];
	[self fnMaybeSendInvalidation];
	[self autorelease];
}

- (void)fnTaskDidBecomeInvalid:(NSURLSessionTask *)task
{
	(void)task;
}

@end

/* ===================================================================================================
 * THE TASK
 * =================================================================================================== */

@implementation NSURLSessionTask

- (instancetype)fnInitWithSession:(NSURLSession *)session
			  request:(NSURLRequest *)request
		       completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_session = session;		/* NOT retained: the session owns its tasks, and a retain would be a cycle */
	_taskIdentifier = [session fnNextTaskIdentifier];
	_originalRequest = [request copy];
	_currentRequest = [request copy];
	_taskDescription = nil;
	_priority = NSURLSessionTaskPriorityDefault;
	_state = NSURLSessionTaskStateSuspended;
	_suspendCount = 1;		/* BORN SUSPENDED, as Apple documents */
	_cancelled = 0;
	_started = 0;
	_responsePending = 0;
	_receivedData = [[NSMutableData alloc] init];
	_heldData = nil;
	_bytesReceived = 0;
	_bytesSent = 0;
	_bytesExpectedToReceive = NSURLSessionTransferSizeUnknown;
	_bytesExpectedToSend = 0;
	if ([request HTTPBody] != nil) {
		_bytesExpectedToSend = (int64_t)[[request HTTPBody] length];
	} else if ([request HTTPBodyStream] != nil) {
		_bytesExpectedToSend = NSURLSessionTransferSizeUnknown;
	}
	_completionHandler = (completion != nil ? Block_copy(completion) : NULL);
	return self;
}

- (void)dealloc
{
	[_originalRequest release];
	[_currentRequest release];
	[_response release];
	[_error release];
	[_taskDescription release];
	[_protocol release];
	[_receivedData release];
	[_heldData release];
	if (_completionHandler != NULL) {
		Block_release(_completionHandler);
	}
	[super dealloc];
}

/* ---- the published properties ----------------------------------------------- */

- (NSUInteger)taskIdentifier { return _taskIdentifier; }
- (NSURLRequest *)originalRequest { return _originalRequest; }
- (NSURLRequest *)currentRequest { return _currentRequest; }
- (NSURLResponse *)response { return _response; }
- (int64_t)countOfBytesReceived { return _bytesReceived; }
- (int64_t)countOfBytesSent { return _bytesSent; }
- (int64_t)countOfBytesExpectedToSend { return _bytesExpectedToSend; }
- (int64_t)countOfBytesExpectedToReceive { return _bytesExpectedToReceive; }
- (NSString *)taskDescription { return _taskDescription; }
- (NSURLSessionTaskState)state { return _state; }
- (NSError *)error { return _error; }
- (float)priority { return _priority; }

- (void)setTaskDescription:(NSString *)description
{
	NSString *copied = [description copy];

	[_taskDescription release];
	_taskDescription = copied;
}

- (void)setPriority:(float)priority
{
	/* APPLE'S RANGE, CLAMPED: the documentation calls 0 the lowest and 1 the highest, and a value outside the
	 * range is a caller's arithmetic rather than a fourth priority level. */
	if (priority < 0.0f) {
		priority = 0.0f;
	} else if (priority > 1.0f) {
		priority = 1.0f;
	}
	_priority = priority;
}

- (id)copyWithZone:(NSZone *)zone
{
	/* A COPY IS A NEW SUSPENDED TASK ON THE SAME SESSION with the same request — not a second handle on the
	 * running transfer, which no resume could make meaningful. The completion handler is not copied: it belongs to
	 * the task that was made with it. */
	NSURLSessionTask *copy = [[[self class] allocWithZone:zone] fnInitWithSession:(NSURLSession *)_session
									     request:_originalRequest
									  completion:nil];

	copy->_priority = _priority;
	copy->_taskDescription = [_taskDescription copy];
	return copy;
}

/* ---- the state machine ------------------------------------------------------ */

- (void)resume
{
	if (_state == NSURLSessionTaskStateCompleted || _cancelled) {
		return;
	}
	if (_suspendCount > 0) {
		_suspendCount--;
	}
	if (_suspendCount > 0) {
		_state = NSURLSessionTaskStateSuspended;
		return;
	}
	if (_started && _state == NSURLSessionTaskStateRunning) {
		return;			/* a second resume is not a second transfer */
	}
	_state = NSURLSessionTaskStateRunning;
	if (!_started) {
		[self fnStartTransfer];
	}
}

- (void)suspend
{
	if (_state == NSURLSessionTaskStateCompleted) {
		return;
	}
	_suspendCount++;
	_state = NSURLSessionTaskStateSuspended;
	if (_protocol != nil) {
		/* THE ENGINE HAS NO RESUMABLE TRANSFER, so a suspend stops it and a later resume asks again from the
		 * beginning. The header says so; what must NOT happen is a stopped transfer that reports itself running. */
		[_protocol stopLoading];
		[_protocol autorelease];	/* the transport's own frame may be on the stack */
		_protocol = nil;
		_started = 0;
	}
}

- (void)cancel
{
	if (_state == NSURLSessionTaskStateCompleted || _cancelled) {
		return;
	}
	_cancelled = 1;
	_state = NSURLSessionTaskStateCanceling;
	if (_protocol != nil) {
		[_protocol stopLoading];
	}
	[self fnFinishWithError:fn_url_error(NSURLErrorCancelled, @"cancelled")];
}

- (void)fnStartTransfer
{
	Class protocolClass;
	NSURLRequest *canonical;
	NSURLProtocol *protocol;
	NSURLProtocol *previous;

	protocolClass = [NSURLProtocol fnProtocolClassForRequest:_currentRequest];
	if (protocolClass == Nil) {
		[self fnFinishWithError:fn_url_error(NSURLErrorUnsupportedURL,
						     @"no NSURLProtocol class claims this request")];
		return;
	}
	canonical = [protocolClass canonicalRequestForRequest:_currentRequest];
	protocol = [[protocolClass alloc] initWithRequest:canonical cachedResponse:nil client:self];
	if (protocol == nil) {
		[self fnFinishWithError:fn_url_error(NSURLErrorUnsupportedURL,
						     @"the NSURLProtocol class made no instance")];
		return;
	}
	/* THE NEW ONE IS IN PLACE BEFORE THE OLD ONE IS GIVEN UP, and the old one is AUTORELEASED: on a redirect the
	 * old protocol's own frame is on the stack, so freeing it here would be a use-after-free in the transport.
	 * This is NSURLConnection's arrangement, kept because it is the one that survives the transport's stack. */
	previous = _protocol;
	_protocol = protocol;
	_started = 1;
	[_receivedData setLength:0];
	_bytesReceived = 0;
	[previous autorelease];
	[protocol startLoading];
}

- (void)fnFinishWithError:(NSError *)error
{
	NSURLSession *session;
	id completion;

	if (_state == NSURLSessionTaskStateCompleted) {
		return;
	}
	[self retain];			/* the ending may be the release that frees the receiver */
	_state = NSURLSessionTaskStateCompleted;
	if (error != nil) {
		[_error release];
		_error = [error retain];
	}
	if (_protocol != nil) {
		NSURLProtocol *protocol = _protocol;

		_protocol = nil;
		[protocol autorelease];	/* the transport's frame may still be on the stack */
	}
	/* THE DATA WHICH ARRIVED IS STILL THE TASK'S ANSWER: a completion-handler task hands it over even on an
	 * error, which is Apple's shape (data is nil only when nothing arrived). */
	session = (NSURLSession *)_session;
	completion = _completionHandler;
	_completionHandler = NULL;
	if (completion != NULL) {
		/* THE CONVENIENCE DOOR'S BLOCK RUNS ON THE DELEGATE QUEUE EVEN WHEN THERE IS NO DELEGATE — that queue is
		 * where Apple promises it, and the shared session has one for exactly this reason. */
		if (session == nil) {
			Block_release(completion);
		} else {
			NSData *data = [[_receivedData copy] autorelease];
			NSURLResponse *response = [[_response retain] autorelease];

			[[session fnDelegateQueue] addOperationWithBlock:^{
				NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

				((void (^)(NSData *, NSURLResponse *, NSError *))completion)(data, response, error);
				Block_release(completion);
				[pool release];
			}];
		}
	} else {
		[session fnSendToDelegate:@selector(URLSession:task:didCompleteWithError:)
				    block:^(id delegate) {
			[delegate URLSession:session task:self didCompleteWithError:error];
		}];
	}
	_session = nil;
	if (session != nil) {
		[session fnTaskDidFinish:self];
	}
	[self release];
}

- (void)fnOrphan
{
	_session = nil;
	if (_protocol != nil) {
		[_protocol stopLoading];
		[_protocol autorelease];
		_protocol = nil;
	}
	if (_state != NSURLSessionTaskStateCompleted) {
		_state = NSURLSessionTaskStateCompleted;
	}
}

/* ---- the response disposition, which BLOCKS the payload --------------------- */

- (void)fnHandleResponse:(NSURLResponse *)response
{
	[_response release];
	_response = [response retain];
	_bytesExpectedToReceive = [response expectedContentLength];
	if (_completionHandler != NULL) {
		return;			/* the convenience door bypasses the response/data delegate messages */
	}
	if (![_session fnDelegateRespondsTo:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
		return;
	}
	_responsePending = 1;
	[_session fnSendToDelegate:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)
			     block:^(id delegate) {
		[delegate URLSession:(NSURLSession *)_session
			    dataTask:(NSURLSessionDataTask *)self
		  didReceiveResponse:response
		   completionHandler:^(NSURLSessionResponseDisposition disposition) {
			[self fnResolveResponseWith:disposition];
		}];
	}];
}

- (void)fnResolveResponseWith:(NSURLSessionResponseDisposition)disposition
{
	NSArray *held;

	if (!_responsePending || _state == NSURLSessionTaskStateCompleted) {
		return;
	}
	_responsePending = 0;
	switch (disposition) {
	case NSURLSessionResponseAllow:
		/* THE DATA THAT ARRIVED WHILE THE DELEGATE DECIDED IS DELIVERED NOW, in arrival order. */
		held = _heldData;
		_heldData = nil;
		for (NSData *chunk in held) {
			[self fnSendData:chunk];
		}
		[held release];
		break;
	case NSURLSessionResponseCancel:
		[self cancel];
		break;
	case NSURLSessionResponseBecomeDownload:
	case NSURLSessionResponseBecomeStream:
		/* THE CONVERSIONS NEED THE CLASSES W3c/W3d ADD. A named refusal is honest; pretending to convert would
		 * leave a task the caller cannot name. */
		fprintf(stderr, "FOUNDATION-REFUSE: a data task was asked to become a %s task; that conversion is not "
				"implemented in this slice\n",
			(disposition == NSURLSessionResponseBecomeDownload ? "download" : "stream"));
		[self cancel];
		break;
	}
}

- (void)fnSendData:(NSData *)data
{
	if (_completionHandler != NULL) {
		[_receivedData appendData:data];
		return;
	}
	if (![_session fnDelegateRespondsTo:@selector(URLSession:dataTask:didReceiveData:)]) {
		return;
	}
	[_session fnSendToDelegate:@selector(URLSession:dataTask:didReceiveData:)
			     block:^(id delegate) {
		[delegate URLSession:(NSURLSession *)_session dataTask:(NSURLSessionDataTask *)self didReceiveData:data];
	}];
}

/* ---- NSURLProtocolClient ---------------------------------------------------- */

- (void)URLProtocol:(NSURLProtocol *)protocol
    wasRedirectedToRequest:(NSURLRequest *)request
	 redirectResponse:(NSURLResponse *)redirectResponse
{
	NSURLRequest *next = request;

	(void)protocol;
	if ([_session fnDelegateRespondsTo:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]) {
		[_session fnSendToDelegate:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)
				     block:^(id delegate) {
			[delegate URLSession:(NSURLSession *)_session
					task:self
	     willPerformHTTPRedirection:(NSHTTPURLResponse *)redirectResponse
			    newRequest:request
		     completionHandler:^(NSURLRequest *chosen) {
				if (chosen != nil) {
					[self fnFollowRedirectWith:chosen];
				} else {
					[self fnRefuseRedirectWithResponse:redirectResponse];
				}
			}];
		}];
		return;
	}
	/* NO DELEGATE MEANS FOLLOW, which is Apple's default. */
	[self fnFollowRedirectWith:next];
}

- (void)fnFollowRedirectWith:(NSURLRequest *)request
{
	NSURLRequest *copied = [request copy];

	[_currentRequest release];
	_currentRequest = copied;
	[self fnStartTransfer];
}

- (void)fnRefuseRedirectWithResponse:(NSURLResponse *)response
{
	/* "DO NOT FOLLOW" MAKES THE 3xx THE ANSWER. Apple also delivers the redirect body as the payload; this
	 * engine's bridge stops at the 3xx and reports rather than carrying that body (the same limitation
	 * NSURLConnection's header records), so the task ends with the response and no payload. */
	[_response release];
	_response = [response retain];
	[self fnFinishWithError:nil];
}

- (void)URLProtocol:(NSURLProtocol *)protocol cachedResponseIsValid:(NSCachedURLResponse *)cachedResponse
{
	/* THIS TASK NEVER HANDS A CACHED ANSWER TO A PROTOCOL, so the notification cannot arise from here; the client
	 * protocol requires every client to implement it. */
	(void)protocol;
	(void)cachedResponse;
}

- (void)URLProtocol:(NSURLProtocol *)protocol
    didReceiveResponse:(NSURLResponse *)response
     cacheStoragePolicy:(NSURLCacheStoragePolicy)policy
{
	(void)protocol;
	(void)policy;			/* the session's URLCache is not wired in this slice (see the header) */
	[self fnHandleResponse:response];
}

- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data
{
	(void)protocol;
	_bytesReceived += (int64_t)[data length];
	if (_responsePending) {
		if (_heldData == nil) {
			_heldData = [[NSMutableArray alloc] init];
		}
		[_heldData addObject:data];
		return;
	}
	[self fnSendData:data];
}

- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)protocol
{
	(void)protocol;
	if (_responsePending) {
		/* THE DELEGATE NEVER ANSWERED THE RESPONSE. Ending now rather than hanging is the only answer that does
		 * not leave the task running forever; the disposition was required and was not given. */
		_responsePending = 0;
	}
	[self fnFinishWithError:nil];
}

- (void)URLProtocol:(NSURLProtocol *)protocol didFailWithError:(NSError *)error
{
	(void)protocol;
	[self fnFinishWithError:error];
}

- (void)URLProtocol:(NSURLProtocol *)protocol
    didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	/* THE TASK DELEGATE IS ASKED BEFORE THE SESSION'S, which is the ordering both headers state: one object may
	 * implement both, and the task's door is the more specific one. */
	if ([_session fnDelegateRespondsTo:@selector(URLSession:task:didReceiveChallenge:completionHandler:)]) {
		[_session fnSendToDelegate:@selector(URLSession:task:didReceiveChallenge:completionHandler:)
				     block:^(id delegate) {
			[delegate URLSession:(NSURLSession *)_session
					task:self
		    didReceiveChallenge:challenge
		     completionHandler:^(NSURLSessionAuthChallengeDisposition disposition,
					 NSURLCredential *credential) {
				[self fnAnswerChallenge:challenge disposition:disposition credential:credential];
			}];
		}];
		return;
	}
	if ([_session fnDelegateRespondsTo:@selector(URLSession:didReceiveChallenge:completionHandler:)]) {
		[_session fnSendToDelegate:@selector(URLSession:didReceiveChallenge:completionHandler:)
				     block:^(id delegate) {
			[delegate URLSession:(NSURLSession *)_session
		     didReceiveChallenge:challenge
		      completionHandler:^(NSURLSessionAuthChallengeDisposition disposition,
					  NSURLCredential *credential) {
				[self fnAnswerChallenge:challenge disposition:disposition credential:credential];
			}];
		}];
		return;
	}
	/* NOBODY IMPLEMENTED A DOOR MEANS THE DEFAULT, WITHOUT WAITING: the transport is blocked until it is answered,
	 * so a delegate that cares about none of this must not hang the transfer. */
	[challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
}

- (void)fnAnswerChallenge:(NSURLAuthenticationChallenge *)challenge
	      disposition:(NSURLSessionAuthChallengeDisposition)disposition
	       credential:(NSURLCredential *)credential
{
	/* THE FOUR DISPOSITIONS BECOME THE SENDER'S FIVE ACTIONS, and the extra one is named rather than folded: a
	 * rejection of the protection space is not a cancellation of the transfer. */
	switch (disposition) {
	case NSURLSessionAuthChallengeUseCredential:
		[challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
		break;
	case NSURLSessionAuthChallengePerformDefaultHandling:
		[challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
		break;
	case NSURLSessionAuthChallengeCancelAuthenticationChallenge:
		[challenge.sender cancelAuthenticationChallenge:challenge];
		break;
	case NSURLSessionAuthChallengeRejectProtectionSpace:
		[challenge.sender rejectProtectionSpaceAndContinueWithChallenge:challenge];
		break;
	}
}

- (void)URLProtocol:(NSURLProtocol *)protocol
    didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	(void)protocol;
	(void)challenge;
}

/* ---- the transport's two first-party doors (NSURLProtocol.h) --------------- */

- (NSInputStream *)URLProtocol:(NSURLProtocol *)protocol fnNewBodyStreamForReSend:(NSURLRequest *)request
{
	/* THIS TASK DOES NOT RE-SEND WITH A STREAM: it hands the protocol the request's own body (or its stream), and
	 * a re-send that needs a fresh stream is a 401 retry the bridge performs itself. Answering the request's own
	 * stream is the honest answer; nil would refuse the retry outright. */
	(void)protocol;
	return [request HTTPBodyStream];
}

- (void)URLProtocol:(NSURLProtocol *)protocol
    fnDidSendBodyData:(int64_t)bytesSent
      totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
	(void)protocol;
	_bytesSent = totalBytesSent;
	_bytesExpectedToSend = totalBytesExpectedToSend;
	if (_completionHandler != NULL) {
		return;
	}
	if (![_session fnDelegateRespondsTo:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)]) {
		return;
	}
	[_session fnSendToDelegate:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)
			     block:^(id delegate) {
		[delegate URLSession:(NSURLSession *)_session
				task:self
		   didSendBodyData:bytesSent
		    totalBytesSent:totalBytesSent
	  totalBytesExpectedToSend:totalBytesExpectedToSend];
	}];
}

@end

@implementation NSURLSessionDataTask
@end
