/*
 * NSURLSession.h
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * `NSURLSession`, its task base and the data task — W3b of FOUNDATION-10.11-PLAN.md, over the transfer engine this
 * library already has.
 *
 * THE DESIGN IS §4.1's, AND IT IS ONE SENTENCE: a session is a TASK STATE MACHINE OVER `NSURLProtocol`, not a second
 * HTTP stack. `NSURLConnection` already drives one protocol instance per exchange with itself as the client; a task
 * does the same, and the protocol's seven client doors become the session delegate's messages. So the bytes, the
 * redirects, the challenges and the response are the ones `FNCURLURLProtocol` already produces, and this file adds
 * what a session has that a connection does not: an identifier per task, a state machine, byte counts, a delegate
 * QUEUE, and completion handlers.
 *
 * WHAT THIS SLICE DECLARES, AND WHAT IT DOES NOT. Apple's family is seven classes; this header carries the three the
 * data path needs (`NSURLSession`, `NSURLSessionTask`, `NSURLSessionDataTask`) and all five delegate protocols, whose
 * methods are declarations a client implements. The download, upload and stream CLASSES and the thirteen factory
 * doors that return them are W3c/W3d: declaring a factory that cannot make its object would be the stub §4.3 forbids,
 * so the class is present with the doors it can honour and the census counts the rest as missing until they land.
 *
 * THE DEVIATIONS, EACH STATED AT ITS DOOR RATHER THAN LEFT TO DISCOVERY:
 *
 *   * A SESSION RETAINS ITS DELEGATE, as Apple documents, until `-invalidate…` has told it the session is invalid.
 *   * THE DELEGATE QUEUE IS ALWAYS REAL. A nil queue is a serial queue the session owns, which is Apple's rule; the
 *     shared session has one too, so a completion handler has somewhere to run even with no delegate.
 *   * A BACKGROUND CONFIGURATION IS REFUSED BY NAME at session creation: this tree has no background-transfer
 *     daemon, and a session that accepted one would promise transfers across a process it cannot keep.
 *   * `-suspend` STOPS THE TRANSFER AND `-resume` MAKES THE REQUEST AGAIN. The engine has no resumable transfer, so
 *     "continue where it stopped" is not expressible; the task's bytes restart rather than pretending otherwise.
 *   * THE CONFIGURATION'S COOKIE STORE IS THE ONE A TRANSFER USES. The transport asks its client (the task) for the
 *     store through a private first-party selector, so `-HTTPCookieStorage` means what its name says: a Set-Cookie
 *     lands in the session's store and a stored cookie is sent, not in/from the process-wide one. The URL CACHE is
 *     still the engine's own (`NSURLCache sharedURLCache`) — that seam is a later slice, and the task-scoped cache
 *     doors answer from the store the cache family owns.
 */

#ifndef FOUNDATION_NSURLSESSION_H
#define FOUNDATION_NSURLSESSION_H

#import <Foundation/NSObject.h>
#import <Foundation/NSURLSessionConfiguration.h>
#import <Foundation/NSURLRequest.h>
#import <Foundation/NSURLResponse.h>
#import <Foundation/NSURLCache.h>
#import <Foundation/NSHTTPCookieStorage.h>
#import <Foundation/NSURLCredentialStorage.h>
#import <Foundation/NSURLProtocol.h>

@class NSCachedURLResponse;
@class NSArray;
@class NSData;
@class NSError;
@class NSHTTPURLResponse;
@class NSInputStream;
@class NSMutableData;
@class NSNetService;
@class NSOutputStream;
@class NSOperationQueue;
@class NSURLAuthenticationChallenge;
@class NSURLCredential;
@class NSURLSession;
@class NSURLSessionDataTask;
@class NSURLSessionDownloadTask;
@class NSURLSessionStreamTask;
@class NSURLSessionTask;
@class NSString;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

/* "It is not possible to know how many bytes will be transferred." Apple's value, and the reason the four byte
 * counters are signed: a task may report this rather than zero. */
FOUNDATION_EXPORT const int64_t NSURLSessionTransferSizeUnknown;

/* 0 is the lowest, 1 the highest; the three names are the documented stops on that scale. */
FOUNDATION_EXPORT const float NSURLSessionTaskPriorityDefault NS_AVAILABLE_MAC(10_10);
FOUNDATION_EXPORT const float NSURLSessionTaskPriorityLow NS_AVAILABLE_MAC(10_10);
FOUNDATION_EXPORT const float NSURLSessionTaskPriorityHigh NS_AVAILABLE_MAC(10_10);

/* HOW A DELEGATE ANSWERS A CHALLENGE. The four cases are Apple's, and the values are Apple's too (0-3): a caller
 * compares a disposition it received — or passes one it computed — and the numbers are not observable otherwise. */
typedef NS_ENUM(NSInteger, NSURLSessionAuthChallengeDisposition) {
	NSURLSessionAuthChallengeUseCredential = 0,
	NSURLSessionAuthChallengePerformDefaultHandling = 1,
	NSURLSessionAuthChallengeCancelAuthenticationChallenge = 2,
	NSURLSessionAuthChallengeRejectProtectionSpace = 3
};

/* HOW A DATA DELEGATE ANSWERS A RESPONSE. Allow and Cancel are honoured here; the two conversions need the classes
 * W3c/W3d add, so they are answered by a named refusal at the door. */
typedef NS_ENUM(NSInteger, NSURLSessionResponseDisposition) {
	NSURLSessionResponseCancel = 0,
	NSURLSessionResponseAllow = 1,
	NSURLSessionResponseBecomeDownload = 2,
	NSURLSessionResponseBecomeStream = 3
};

/* A TASK IS BORN SUSPENDED AND MUST BE RESUMED. The numbers are Apple's (0-3) for the same reason the dispositions'. */
typedef NS_ENUM(NSInteger, NSURLSessionTaskState) {
	NSURLSessionTaskStateRunning = 0,
	NSURLSessionTaskStateSuspended = 1,
	NSURLSessionTaskStateCanceling = 2,
	NSURLSessionTaskStateCompleted = 3
};

/* ---- the delegate protocols -------------------------------------------------- */

/* SESSION-WIDE MESSAGES. The last one a session sends is `-didBecomeInvalid…`, after which nothing is delivered. */
@protocol NSURLSessionDelegate <NSObject>
@optional
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error;
- (void)URLSession:(NSURLSession *)session
	didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
	  completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
				      NSURLCredential * _Nullable credential))completionHandler;
/* Background delivery only; this tree has no background session, so the door exists and is never sent. */
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session;
@end

/* ONE TASK'S MESSAGES. The task's delegate is consulted BEFORE the session's, per Apple's ordering. */
@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@optional
- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
	newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler;
- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
			     NSURLCredential * _Nullable credential))completionHandler;
/* Called when a body stream was spent and the transfer needs a fresh, unopened one. This engine does not retry with a
 * stream, so the door is declared for the shape and is not sent. */
- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream * _Nullable bodyStream))completionHandler;
- (void)URLSession:(NSURLSession *)session
	      task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
/* THE ENDING: sent for every task exactly once, error nil when it completed. */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
				  didCompleteWithError:(nullable NSError *)error;
@end

/* A DATA TASK'S MESSAGES. `-didReceiveResponse:` BLOCKS the payload until the completion block answers, which is why
 * the task buffers data that arrives while the disposition is pending. */
@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session
	  dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
					      didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
					      didBecomeStreamTask:(NSURLSessionStreamTask *)streamTask;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
- (void)URLSession:(NSURLSession *)session
	  dataTask:(NSURLSessionDataTask *)dataTask
willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse * _Nullable cachedResponse))completionHandler;
@end

/* DECLARED WITH THE FAMILY because Apple declares them here; their task classes are W3c/W3d. */
@protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location;
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didResumeAtOffset:(int64_t)fileOffset
 expectedTotalBytes:(int64_t)expectedTotalBytes;
@end

@protocol NSURLSessionStreamDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)streamTask;
- (void)URLSession:(NSURLSession *)session writeClosedForStreamTask:(NSURLSessionStreamTask *)streamTask;
- (void)URLSession:(NSURLSession *)session betterRouteDiscoveredForStreamTask:(NSURLSessionStreamTask *)streamTask;
- (void)URLSession:(NSURLSession *)session
	streamTask:(NSURLSessionStreamTask *)streamTask
didBecomeInputStream:(NSInputStream *)inputStream
      outputStream:(NSOutputStream *)outputStream;
@end

/* ---- the task base ----------------------------------------------------------- */

NS_CLASS_AVAILABLE_MAC(NSURLSESSION_AVAILABLE)
@interface NSURLSessionTask : NSObject <NSCopying>
{
@private
	id _session;			/* the owning session, NOT retained: the session owns its tasks */
	NSUInteger _taskIdentifier;
	NSURLRequest *_originalRequest;
	NSURLRequest *_currentRequest;
	NSURLResponse *_response;
	NSError *_error;
	NSString *_taskDescription;
	float _priority;
	NSURLSessionTaskState _state;
	signed char _suspendCount;
	signed char _cancelled;
	signed char _started;
	signed char _responsePending;
	signed char _finishPending;	/* the transport finished while a response disposition was pending */
	int64_t _bytesReceived;
	int64_t _bytesSent;
	int64_t _bytesExpectedToReceive;
	int64_t _bytesExpectedToSend;
	id _protocol;			/* the NSURLProtocol instance, retained while it loads */
	NSMutableData *_receivedData;
	NSMutableArray *_heldData;	/* chunks that arrived while a response disposition was pending */
	id _completionHandler;		/* the convenience door's block, if this task was made with one */
	id _taskScopedCredentials;	/* NSMutableDictionary, made on first use by the credential category */
}

@property (readonly) NSUInteger taskIdentifier;
@property (nullable, readonly, copy) NSURLRequest *originalRequest;
@property (nullable, readonly, copy) NSURLRequest *currentRequest;
@property (nullable, readonly, copy) NSURLResponse *response;
@property (readonly) int64_t countOfBytesReceived;
@property (readonly) int64_t countOfBytesSent;
@property (readonly) int64_t countOfBytesExpectedToSend;
@property (readonly) int64_t countOfBytesExpectedToReceive;
@property (nullable, copy) NSString *taskDescription;
@property (readonly) NSURLSessionTaskState state;
@property (nullable, readonly, copy) NSError *error;
@property float priority NS_AVAILABLE_MAC(10_10);

- (void)cancel;
- (void)suspend;
- (void)resume;
@end

/* "No additional functionality over NSURLSessionTask": the subclass exists to name the kind — and it is ONE RELEASE
 * LATER than the base (10.10), which is the reference's fact and the reason it carries its own era. */
NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSURLSessionDataTask : NSURLSessionTask
@end

/* "An NSURLSessionUploadTask does not currently provide any additional functionality over an NSURLSessionDataTask":
 * the kind is stated by the subclass so the task lists and the delegate doors can tell an upload from a data task.
 * Apple annotates neither this class nor the download below (their era is the base's), so neither carries a macro. */
@interface NSURLSessionUploadTask : NSURLSessionDataTask
@end

/* A DOWNLOAD'S BODY IS A FILE, and the class owns the three things that makes: the temporary path, the write handle,
 * and the point at which the file is handed over and then removed (Apple: read or copy it inside the delegate call,
 * because it is removed when that call returns). */
@interface NSURLSessionDownloadTask : NSURLSessionTask
{
@private
	NSString *_downloadPath;
	id _downloadFile;		/* NSFileHandle, while the body is being written */
	id _downloadCompletion;		/* the convenience door's block: (location, response, error) */
	signed char _downloadDelivered;
}
/* THE RESUME DOOR IS A NAMED REFUSAL: resume data is a platform artefact (an offset into a transfer the system can
 * re-attach), and this tree's engine has no resumable transfer. The handler is still CALLED, with nil, so a caller is
 * not left waiting; the task is then cancelled. */
- (void)cancelByProducingResumeData:(void (^ _Nullable)(NSData * _Nullable resumeData))completionHandler;
@end

/* A STREAM TASK OWNS A CONNECTED SOCKET and answers reads and writes over it. The reads and writes are QUEUED and
 * executed serially, which is Apple's contract; a read's timeout is the longest it waits for bytes. The two TLS doors
 * refuse by name: this tree's TLS lives in libcurl's HTTP transfer, not in a raw stream, so there is no handshake to
 * start or stop here. */
NS_CLASS_AVAILABLE_MAC(10_11)
@interface NSURLSessionStreamTask : NSURLSessionTask
{
@private
	NSString *_hostName;
	NSInteger _port;
	int _socket;
	signed char _readClosed;
	signed char _writeClosed;
	id _ioQueue;			/* NSOperationQueue, serial: the order reads and writes were asked in */
}
- (void)readDataOfMinLength:(NSUInteger)minBytes
		  maxLength:(NSUInteger)maxBytes
		    timeout:(NSTimeInterval)timeout
	  completionHandler:(void (^)(NSData * _Nullable data, BOOL atEOF, NSError * _Nullable error))completionHandler;
- (void)writeData:(NSData *)data
	  timeout:(NSTimeInterval)timeout
completionHandler:(void (^)(NSError * _Nullable error))completionHandler;
- (void)captureStreams;
- (void)closeRead;
- (void)closeWrite;
- (void)startSecureConnection;
- (void)stopSecureConnection;
@end

/* ---- the session ------------------------------------------------------------- */

NS_CLASS_AVAILABLE_MAC(NSURLSESSION_AVAILABLE)
@interface NSURLSession : NSObject
{
@private
	NSURLSessionConfiguration *_configuration;
	id<NSURLSessionDelegate> _delegate;	/* RETAINED until invalidation tells it the session is gone */
	NSOperationQueue *_delegateQueue;
	NSString *_sessionDescription;
	NSMutableArray *_tasks;
	NSUInteger _nextTaskIdentifier;
	signed char _invalidated;
	signed char _cancelOnInvalidate;
	signed char _invalidationSent;
}

/* THE SHARED SESSION: the default configuration, no delegate, its own queue. */
+ (NSURLSession *)sharedSession;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
				  delegate:(nullable id<NSURLSessionDelegate>)delegate
			     delegateQueue:(nullable NSOperationQueue *)queue;

@property (readonly, retain) NSOperationQueue *delegateQueue;
@property (nullable, readonly, retain) id<NSURLSessionDelegate> delegate;
@property (readonly, copy) NSURLSessionConfiguration *configuration;
@property (nullable, copy) NSString *sessionDescription;

- (void)finishTasksAndInvalidate;
- (void)invalidateAndCancel;
- (void)resetWithCompletionHandler:(void (^)(void))completionHandler;
- (void)flushWithCompletionHandler:(void (^)(void))completionHandler;
/* The block receives the outstanding tasks of each kind. The three arrays partition the same list: a download is not
 * also a data task, and an upload is not either even though its class descends from NSURLSessionDataTask. */
- (void)getTasksWithCompletionHandler:(void (^)(NSArray *dataTasks,
						NSArray *uploadTasks,
						NSArray *downloadTasks))completionHandler;
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray *tasks))completionHandler NS_AVAILABLE_MAC(10_11);

/* THE TASK FACTORIES THIS SLICE CAN HONOUR: the data task, in the delegate-delivered and completion forms. A task is
 * born SUSPENDED; `-resume` is what starts it. */
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
			    completionHandler:(void (^)(NSData * _Nullable data,
							NSURLResponse * _Nullable response,
							NSError * _Nullable error))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
		       completionHandler:(void (^)(NSData * _Nullable data,
						   NSURLResponse * _Nullable response,
						   NSError * _Nullable error))completionHandler;

/* UPLOADS take their body from data or a file; a STREAMED request would need a body-stream read the transport does
 * not have, so that door refuses by name instead of handing over a task that could never send. */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(nullable NSData *)bodyData;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL;
- (nullable NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
					 fromData:(nullable NSData *)bodyData
				completionHandler:(void (^)(NSData * _Nullable data,
							    NSURLResponse * _Nullable response,
							    NSError * _Nullable error))completionHandler;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
					 fromFile:(NSURL *)fileURL
				completionHandler:(void (^)(NSData * _Nullable data,
							    NSURLResponse * _Nullable response,
							    NSError * _Nullable error))completionHandler;

/* DOWNLOADS write the body to a temporary file and hand its URL over; the file is removed when the delegate call or
 * the completion handler returns. `downloadTaskWithResumeData:` refuses by name (see the class above). */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url;
- (nullable NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData;
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
				    completionHandler:(void (^)(NSURL * _Nullable location,
								NSURLResponse * _Nullable response,
								NSError * _Nullable error))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
				completionHandler:(void (^)(NSURL * _Nullable location,
							    NSURLResponse * _Nullable response,
							    NSError * _Nullable error))completionHandler;
- (nullable NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
					       completionHandler:(void (^)(NSURL * _Nullable location,
									   NSURLResponse * _Nullable response,
									   NSError * _Nullable error))completionHandler;

/* STREAMS. The `NSNetService` form uses the service's already-resolved host when it has one; a service that has not
 * been resolved refuses by name, because resolving it needs a run loop and a session factory cannot block on one. */
- (nullable NSURLSessionStreamTask *)streamTaskWithHostName:(NSString *)hostname port:(NSInteger)port NS_AVAILABLE_MAC(10_11);
- (nullable NSURLSessionStreamTask *)streamTaskWithNetService:(NSNetService *)service NS_AVAILABLE_MAC(10_11);
@end

/* ---- THE TASK-SCOPED CATEGORIES, where Apple declares them -------------------- */

/* A CACHE ANSWER FOR ONE TASK: the request is the task's, and the completion handler runs on the session's delegate
 * queue, which is why these doors live beside the session rather than in NSURLCache's own header. */
@interface NSURLCache (NSURLSessionTaskAdditions)
- (void)getCachedResponseForDataTask:(NSURLSessionDataTask *)dataTask
		   completionHandler:(void (^)(NSCachedURLResponse * _Nullable cachedResponse))completionHandler NS_AVAILABLE_MAC(10_10);
- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forDataTask:(NSURLSessionDataTask *)dataTask NS_AVAILABLE_MAC(10_10);
- (void)removeCachedResponseForDataTask:(NSURLSessionDataTask *)dataTask NS_AVAILABLE_MAC(10_10);
@end

/* PER-TASK CREDENTIALS: a credential set here belongs to the task alone and never reaches the shared store, which is the
 * difference between this category and the class's own doors. */
@interface NSURLCredentialStorage (NSURLSessionTaskAdditions)
- (void)getCredentialsForProtectionSpace:(NSURLProtectionSpace *)protectionSpace
				    task:(NSURLSessionTask *)task
		       completionHandler:(void (^)(NSDictionary * _Nullable credentials))completionHandler NS_AVAILABLE_MAC(10_10);
- (void)getDefaultCredentialForProtectionSpace:(NSURLProtectionSpace *)space
					  task:(NSURLSessionTask *)task
			     completionHandler:(void (^)(NSURLCredential * _Nullable credential))completionHandler NS_AVAILABLE_MAC(10_10);
- (void)setCredential:(NSURLCredential *)credential
   forProtectionSpace:(NSURLProtectionSpace *)protectionSpace
		 task:(NSURLSessionTask *)task NS_AVAILABLE_MAC(10_10);
- (void)setDefaultCredential:(NSURLCredential *)credential
	  forProtectionSpace:(NSURLProtectionSpace *)protectionSpace
			task:(NSURLSessionTask *)task NS_AVAILABLE_MAC(10_10);
@end

/* COOKIES FOR A TASK: the task's URL is the question, and the store's own URL-based doors are the answer. The
 * group-container factory refuses by name — this system has no app groups, and a store that shared one would leak
 * cookies between them. */
@interface NSHTTPCookieStorage (NSURLSessionTaskAdditions)
- (void)getCookiesForTask:(NSURLSessionTask *)task
	completionHandler:(void (^)(NSArray * _Nullable cookies))completionHandler NS_AVAILABLE_MAC(10_10);
- (void)storeCookies:(NSArray *)cookies forTask:(NSURLSessionTask *)task NS_AVAILABLE_MAC(10_10);
+ (nullable NSHTTPCookieStorage *)sharedCookieStorageForGroupContainerIdentifier:(NSString *)identifier NS_AVAILABLE_MAC(10_11);
@end

/* AND THE PROTOCOL'S TASK DOORS. `+canInitWithTask:` defaults to the request-based door (Apple's own default), and
 * `-task` answers the task the protocol instance was made for. */
@interface NSURLProtocol (NSURLSessionTaskAdditions)
+ (BOOL)canInitWithTask:(NSURLSessionTask *)task NS_AVAILABLE_MAC(10_10);
- (instancetype)initWithTask:(NSURLSessionTask *)task
	      cachedResponse:(nullable NSCachedURLResponse *)cachedResponse
		      client:(nullable id<NSURLProtocolClient>)client NS_AVAILABLE_MAC(10_10);
@property (nullable, readonly, retain) NSURLSessionTask *task NS_AVAILABLE_MAC(10_10);
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSURLSESSION_H */
