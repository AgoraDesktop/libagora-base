/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSOperationQueue — the thing that decides WHEN. F13.19.
 *
 * A QUEUE RUNS OPERATIONS ON ITS OWN THREADS, one per operation while it is under its limit, and
 * RE-EXAMINES WHAT IS READY every time one finishes — because finishing an operation is what makes the
 * next one ready, and a queue that only looked when work was ADDED would stall a graph at its second
 * step. That re-examination is the whole of the scheduler, and it is why the completion path takes the
 * same lock the addition path does.
 *
 * `-maxConcurrentOperationCount` IS HONOURED AND NEGATIVE MEANS UNLIMITED, which is Cocoa's own
 * spelling of "no limit" — so a program that sets it to a small number gets a serial queue, and in a
 * serial queue the START ORDER IS THE ADDITION ORDER, which is a thing a probe can measure.
 *
 * WHAT IS NOT HERE, named: `NSOperationQueuePriority` ordering (operations run in the order they became
 * ready), and THE MAIN QUEUE RUNS ON THE MAIN THREAD — this library's run loop has timers and no sources, so
 * `+mainQueue` is a SERIAL queue whose operations run on worker threads like any other. That is a real difference from
 * Cocoa and it is stated rather than implied.
 *
 * `-qualityOfService` IS A STORED HINT (10.10), like the operation's: this scheduler orders by readiness. `-underlyingQueue`
 * IS REAL: when it is set, each operation runs on that dispatch queue instead of on the worker thread the queue would
 * otherwise detach — which is what Apple's property means, and what makes a caller's serial dispatch queue actually
 * serialize the operations.
 */

#ifndef FOUNDATION_NSOPERATIONQUEUE_H
#define FOUNDATION_NSOPERATIONQUEUE_H

#import <Foundation/NSObject.h>

/* THE INTERFACE, NOT A FORWARD DECLARATION: `NSArray<__kindof NSOperation *>` is a LIGHTWEIGHT GENERIC, and clang
 * rejects type arguments on a class it has only seen forward-declared ("non-parameterized class 'NSArray'"). */
#import <Foundation/NSArray.h>
#include <dispatch/dispatch.h>	/* dispatch_queue_t: -underlyingQueue's type, as Apple's header has it */
@class NSMutableArray;	/* the two queues the ivars hold: a pointer ivar needs the NAME, not the interface */
@class FNCondition;	/* §63.170 re-homed this; see the note in NSOperation.h */
@class NSOperation;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(OperationQueue)
NS_CLASS_AVAILABLE_MAC(10_5)
@interface NSOperationQueue : NSObject
{
	NSMutableArray *_operations;
	/* OPERATIONS HANDED TO A WORKER THAT HAS NOT STARTED THEM YET. A worker marks an operation
	 * started only when its thread RUNS, so before this existed the scheduler still saw a
	 * dispatched operation as "ready" and handed it to a SECOND worker: measured, the same pointer
	 * detached twice and `-start` then sent to a chunk whose memory had already been freed and
	 * reused (plan §15.3). */
	NSMutableArray *_pending;
	FNCondition *_condition;
	NSInteger _maxConcurrent;
	NSUInteger _running;
	BOOL _suspended;
	NSString *_name;
	NSQualityOfService _qualityOfService;
	dispatch_queue_t _underlyingQueue;
}

/* THE QUEUE AN OPERATION IS RUNNING IN, from inside it, and the process's serial main queue. */
+ (nullable NSOperationQueue *)currentQueue NS_AVAILABLE_MAC(10_6);
+ (NSOperationQueue *)mainQueue NS_AVAILABLE_MAC(10_6);

- (void)addOperation:(NSOperation *)operation;
/* THE BATCH FORM (10.5). `waitUntilFinished:YES` adds every operation and then waits for the QUEUE to drain, which
 * is -waitUntilAllOperationsAreFinished's contract rather than a wait per operation: a later operation may depend
 * on an earlier one, and waiting for each in turn would still be right but would do it in the wrong order. */
- (void)addOperations:(NSArray *)operations waitUntilFinished:(BOOL)wait NS_AVAILABLE_MAC(10_6);
- (NSArray<__kindof NSOperation *> *)operations;
- (NSUInteger)operationCount NS_AVAILABLE_MAC(10_6);

- (NSInteger)maxConcurrentOperationCount;
- (void)setMaxConcurrentOperationCount:(NSInteger)count;

/* APPLE'S −1 (§62.103): 'let the queue decide', which is what `maxConcurrentOperationCount` answers until a
 * caller sets one. */
extern const NSInteger NSOperationQueueDefaultMaxConcurrentOperationCount;

- (void)cancelAllOperations;
- (void)waitUntilAllOperationsAreFinished;

- (BOOL)isSuspended;
- (void)setSuspended:(BOOL)suspended;

- (nullable NSString *)name NS_AVAILABLE_MAC(10_6);
- (void)setName:(nullable NSString *)name NS_AVAILABLE_MAC(10_6);

/* THE SERVICE CLASS, STORED AND REPORTED (10.10): the scheduler here orders by readiness, so nothing consults it. */
@property NSQualityOfService qualityOfService NS_AVAILABLE_MAC(10_10);

/* THE DISPATCH QUEUE THE OPERATIONS RUN ON (10.10). nil means this queue's own worker threads, which is the default;
 * a non-nil queue receives each operation as a dispatch block, so a SERIAL dispatch queue really does serialize them.
 * Retained on assignment and released on replacement/dealloc, the way a dispatch object is owned. */
@property (nullable, assign) dispatch_queue_t underlyingQueue NS_AVAILABLE_MAC(10_10);


/* THE BLOCK DOOR: the same act as -addOperation:, for a caller holding a block rather than an operation.
 * THE BLOCK IS COPIED WITH Block_copy() AND RELEASED WITH Block_release() - a block is not an ordinary
 * object to own, because -copy is a MESSAGE SEND and the runtime reads the block's isa to find its class.
 *
 * THE QUEUE IS EXPECTED TO BE SERIAL WHEN THE ORDER OF WHAT IT RUNS MATTERS. */
- (void)addOperationWithBlock:(void (^)(void))block NS_AVAILABLE_MAC(10_6);
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSOPERATIONQUEUE_H */
