/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSThread — a thread as an object. F13.17, docs/design/foundation-plan.md §10.
 *
 * THE MECHANISM IS PTHREADS, as §10's table says, and THE IDENTITY IS A THREAD-LOCAL KEY: a thread's
 * object is made the first time anything asks for it and then belongs to that thread, so
 * `+currentThread` answers the same object for as long as the thread lives — through the key rather
 * than through a table keyed by thread id, which would need locking to read.
 *
 * WHAT IS HERE is the part a program uses: identity (`+currentThread`, `+mainThread`, `-isMainThread`),
 * a name, starting a thread by target and selector — the pre-blocks API, because this library has no
 * blocks in its public headers — sleeping, and cancellation as a FLAG the thread may consult.
 *
 * `-threadDictionary` IS HERE, and it is the per-thread ASSOCIATIVE store: the current-thread object
 * is already resolved through a key, so the dictionary hangs off that object and a program gets one
 * per thread for free. It arrived for the assertion handler (W2d), whose home Apple files here.
 *
 * WHAT IS NOT, named: `-stackSize`; the quality-of-service and priority doors; and `-main`, which is a
 * run-loop concept. Cancellation is a flag and NOT a signal: nothing here interrupts a thread, so a
 * thread that never asks is never cancelled — which is Cocoa's contract too, and worth stating
 * because it is the one thing about cancellation that surprises people.
 */

#ifndef FOUNDATION_NSTHREAD_H
#define FOUNDATION_NSTHREAD_H

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
/* NSTimeInterval IS DECLARED IN NSDate.h and this header names it — the same dependency NSProcessInfo
 * had to declare, and the compiler says so rather than accepting an implicit int. */
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>

@class NSString;
@class NSArray;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(Thread)
@interface NSThread : NSObject
{
	id _threadDictionary;	/* the per-thread store, made on first ask */
	id _target;
	SEL _selector;
	id _argument;
	NSString *_name;
	unsigned long _threadID;	/* a pthread_t, kept as an integer so pthreads stays out of here */
	BOOL _isMain;
	BOOL _cancelled;
	BOOL _executing;
	BOOL _finished;
	/* §63.195: a thread whose body is a BLOCK, and the values a thread carries about itself. */
	id _block;
	double _priority;
	NSUInteger _stackSize;
	NSQualityOfService _qualityOfService;
}

+ (NSThread *)currentThread;
+ (NSThread *)mainThread;
+ (BOOL)isMainThread;

/* THE STACK OF THE CALLING THREAD (10.5 return addresses, 10.6 symbols). `+callStackReturnAddresses` answers
 * NSNumbers holding the addresses, and `+callStackSymbols` answers the same frames as `backtrace_symbols(3)`
 * strings. Both begin at the CALLER, not at this class. */
+ (NSArray *)callStackReturnAddresses;
+ (NSArray *)callStackSymbols;
- (BOOL)isMainThread;

- (nullable NSString *)name;
- (void)setName:(nullable NSString *)name;

- (BOOL)isCancelled;
- (void)cancel;

/* THE PER-THREAD STORE: one per THREAD, created on first ask, and the receiver is the thread whose
 * dictionary it is — which is Apple's contract and why this is an ivar rather than a table keyed by
 * thread id (a table would need locking to read). */
- (NSMutableDictionary *)threadDictionary;
- (BOOL)isExecuting;
- (BOOL)isFinished;

+ (void)sleepForTimeInterval:(NSTimeInterval)interval;
+ (void)sleepUntilDate:(NSDate *)date;

/* -main IS THE BODY, which is why a subclass may override it: the default runs the target/selector or the
 * block, and the pthread entry calls THIS. `+exit` terminates the current thread.
 * PRIORITY IS 0.0-1.0, Apple's scale, MAPPED onto this kernel's nice range — a stated reading, because
 * Apple's scale names a scheduling class this kernel has no equivalent of. `qualityOfService` is recorded
 * and used as the same hint, and `stackSize` is applied through the pthread this class creates. */
- (void)main;
+ (void)exit;
+ (BOOL)isMultiThreaded;
+ (double)threadPriority;
+ (BOOL)setThreadPriority:(double)priority;
@property (readwrite) double threadPriority;
@property (readwrite) NSUInteger stackSize;
@property (readwrite) NSQualityOfService qualityOfService;

+ (void)detachNewThreadWithBlock:(void (^)(void))block;
- (instancetype)initWithBlock:(void (^)(void))block;

- (instancetype)initWithTarget:(id)target
		      selector:(SEL)selector
			object:(nullable id)argument;
+ (void)detachNewThreadSelector:(SEL)selector
		       toTarget:(id)target
		     withObject:(nullable id)argument;
- (void)start;

- (NSString *)description;

@end

/*
 * THE THREADED PERFORM FAMILY (10.2 and 10.5), declared in NSThread.h because that is Apple's placement: the
 * receiver is an NSObject, but the subject is a THREAD, and `NSObject (NSThreadPerformAdditions)` is where the SDK
 * puts all five doors. The delayed pair is in NSRunLoop.h for the same reason.
 *
 * WHAT EACH ONE MEANS, because the differences are the point:
 *   * `...waitUntilDone:YES` BLOCKS THE CALLER until the selector has run on the other thread;
 *   * `...waitUntilDone:NO` returns immediately, and the request is queued on that thread's run loop;
 *   * called ON the target thread, the selector is performed IMMEDIATELY and `wait` is irrelevant;
 *   * a thread with no run loop cannot receive one, and that is an exception rather than a silent drop.
 * `-performSelectorInBackground:` starts a NEW detached thread, so there is no loop to reach: the selector runs as
 * the thread's body.
 */
@interface NSObject (NSThreadPerformAdditions)

- (void)performSelectorOnMainThread:(SEL)aSelector
			 withObject:(nullable id)arg
		      waitUntilDone:(BOOL)wait
			      modes:(nullable NSArray *)array;
- (void)performSelectorOnMainThread:(SEL)aSelector
			 withObject:(nullable id)arg
		      waitUntilDone:(BOOL)wait;
- (void)performSelector:(SEL)aSelector
	       onThread:(NSThread *)thr
	     withObject:(nullable id)arg
	  waitUntilDone:(BOOL)wait
		  modes:(nullable NSArray *)array;
- (void)performSelector:(SEL)aSelector
	       onThread:(NSThread *)thr
	     withObject:(nullable id)arg
	  waitUntilDone:(BOOL)wait;
- (void)performSelectorInBackground:(SEL)aSelector withObject:(nullable id)arg;

@end

/* NSQualityOfService LIVES IN NSObjCRuntime.h, and this header includes that one, so a
 * program that used it by way of this header still compiles. It moved on 2026-09-20:
 * Apple declares the type in the runtime header, and NSOperation.h's legacy aliases
 * (see there) depend on that being where a name-only include finds it. */

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSTHREAD_H */
