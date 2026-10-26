/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSRunLoop.m — the timer, the sources and the loop, ON TOP OF CORE FOUNDATION'S RUN LOOP.
 *
 * **THIS CLASS USED TO BE A RUN LOOP IMPLEMENTATION AND IS NOW A FACADE.** It kept its own timer array, its own
 * fd-source array, its own performer queue and its own `select(2)` wait, and nothing else in the tree could see
 * any of it: `-getCFRunLoop` raised because "this run loop is not CF-backed", `NSTimer` fired only if something
 * called `-runUntilDate:`, and the main dispatch queue was never serviced because nothing ever ran
 * `CFRunLoopRunInMode`. Meanwhile `libagora-core` has the real swift-corelibs `CFRunLoop` — timers, sources,
 * observers, thread ownership, and `_dispatch_main_queue_callback_4CF` wired in — which the desktop never ran.
 *
 * So the four mechanisms became one:
 *
 *   * A TIMER IS A `CFRunLoopTimer`. `NSTimer` owns one, and its date, repeat interval, tolerance, validity and
 *     removal from the loop are CoreFoundation's answers rather than a parallel bookkeeping that had to agree.
 *   * AN FD SOURCE IS A `CFRunLoopSource` whose readiness is detected by a `dispatch_source` on a private queue.
 *     Dispatch does the watching (it owns an epoll selector already); the CF source carries the callback back to
 *     the loop's own thread, which is the half `NSFileHandle`'s `-readabilityHandler` contract depends on.
 *   * A PERFORMER IS ONE `CFRunLoopSource` in the common modes, signalled by whichever thread enqueued it, so
 *     `-performSelector:onThread:…` and `-performSelectorOnMainThread:` are delivered by the same wait as
 *     everything else instead of by a poll the loop had to remember to do.
 *   * THE NOTIFICATION QUEUE'S TWO PHASES ARE A `CFRunLoopObserver` at `kCFRunLoopBeforeWaiting`, which is what
 *     "when idle" means, plus the end-of-pass ladder `-runMode:beforeDate:` runs for a zero-second pass (a pass
 *     that does not wait never reaches BeforeWaiting — CoreFoundation skips the observers when it polls).
 *
 * AND THE WAIT IS COREFOUNDATION'S, which is the point of the exercise: `CFRunLoopRunInMode` polls an epoll set
 * that already contains the loop's wakeup port and — on the main thread, in a common mode — the main dispatch
 * queue's port. `dispatch_async(dispatch_get_main_queue(), ^{…})` from any thread runs on the next pass of an
 * application's loop; so does `dispatch_source` on an fd. That is measured, not assumed: `tests/runloop_cf.m`
 * holds the dispatch main queue, a timer, a signalled source and an fd source to their contracts, and
 * `libagora-app`'s `appkit-runloop-timer` proves a timer fires inside `-[NSApplication run]`.
 *
 * THE MODE RULE IS UNCHANGED AND IS STILL DEFINED ONCE (`FNRunLoopModeAllows`, §62.62): a timer added for a mode
 * fires in that mode, in the common modes, and when the loop runs the common modes. What changed is where that
 * rule is enforced — CoreFoundation's mode sets express it directly, with one translation this file makes: **every
 * mode a loop is asked to RUN is registered as a common mode of its CF loop**, so "common" behaves as it did here
 * and a source added for the common modes fires in every mode the desktop uses. A mode that is never run and never
 * added to stays unknown to CoreFoundation, which is exactly as inert as an unused mode should be.
 */

#import <Foundation/NSRunLoop.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>	/* NSMutableSet, the delayed-perform registry */
#import <Foundation/NSThread.h>	/* the loop records itself in its owner thread's dictionary */
#import <Foundation/NSString.h>
#import <Foundation/NSInvocation.h>
/* THE NOTIFICATION QUEUE'S SEAM (§62.61). Two of NSNotificationQueue's posting styles are DEFINED as points in
 * a run loop — "as soon as possible" is "when the current callout completes" and "when idle" is "when the loop
 * is about to wait" — so the loop has to tell the queue which phase it reached. This is the only file that
 * knows, and FNRunLoopQueue.h is the internal contract between them. */
#import <Foundation/FNRunLoopQueue.h>
/* AND THE MODE RULE ALL THREE OF THEM SHARE (§62.62) — a timer, a notification and a performer all ask "may this
 * be delivered in the mode the loop is running?", and they must not answer it differently. */
#import <Foundation/FNRunLoopModes.h>

#include <CoreFoundation/CFRunLoop.h>
#include <CoreFoundation/CFString.h>
#include <dispatch/dispatch.h>
#include <Block.h>	/* AT THE TOP: it sat below the NSTimer code, so that code could not see the
			 * runtime entry points while the performer further down could (§63.190). */
/* THE WEAK API LIVES HERE (objc_storeWeak/objc_loadWeak, documented as zeroing), not in
 * <objc/runtime.h>. THE FOUNDATION LIBRARY IS MRC - ARC is a per-file choice and no file in this
 * directory takes it - so a non-owning reference is spelled with the runtime's own functions,
 * exactly as NSNotificationCenter.m does it. */
#include <objc/objc-arc.h>
#include <pthread.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

NSString *const NSDefaultRunLoopMode = @"NSDefaultRunLoopMode";
NSString *const NSRunLoopCommonModes = @"NSRunLoopCommonModes";

/* THE PERFORMER QUEUE IS THE ONE PART OF THIS CLASS ANOTHER THREAD WRITES. `-performSelector:onThread:` reaches a
 * loop it does not own, so an enqueue can land while the owner is walking the array. One process-wide mutex is
 * enough: a performer list is touched for microseconds, and a per-loop lock would need a pthread_mutex_t in a public
 * header for no measured gain. */
static pthread_mutex_t fn_performer_queue_lock = PTHREAD_MUTEX_INITIALIZER;

/* AND THE RUN LOOP A THREAD OWNS IS RECORDED IN THAT THREAD'S DICTIONARY, because the pthread-specific this class
 * uses is readable only by its owner. The dictionary is the one per-thread object every thread can read. */
static NSString *const FNRunLoopThreadStoreKey = @"FNRunLoop";
static pthread_mutex_t fn_loop_owner_lock = PTHREAD_MUTEX_INITIALIZER;

/* **THE REGISTRY THAT MAKES A `CFRunLoopRef` ANSWER AN `NSRunLoop`.** Two doors need it and neither can work
 * without it: `+mainRunLoop` must answer the wrapper for `CFRunLoopGetMain()` even when the main thread has not
 * asked for one yet, and the timer and performer callbacks — which run on the loop's thread but are handed nothing
 * but themselves — have to find the loop they are delivering for, to bump its work counter. Small N (one per
 * thread that has one), linear scan, under a lock. */
/* **THE DOORS THIS FILE USES BEFORE THEIR IMPLEMENTATIONS**, declared once here rather than as scattered forward
 * statements: the source trampolines call into the loop, and the timer callback does too, and a category is how
 * this tree spells "private to the file". */
@interface NSRunLoop (FNPrivate)
- (CFRunLoopRef)fn_cfLoop;
- (void)fnNoteWork;
- (void)fnSetCurrentMode:(NSString *)mode;
- (void)fnPruneTimers;
- (void)fnRunPerformersInMode:(NSString *)mode;
- (BOOL)fnHasPendingPerformerForMode:(NSString *)mode;
@end

static pthread_mutex_t fn_loops_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray *fn_loops = nil;	/* NSRunLoop, retained */

static void fn_loops_add(NSRunLoop *loop)
{
	pthread_mutex_lock(&fn_loops_lock);
	if (fn_loops == nil) {
		fn_loops = [[NSMutableArray alloc] init];
	}
	[fn_loops addObject:loop];
	pthread_mutex_unlock(&fn_loops_lock);
}

static void fn_loops_remove(NSRunLoop *loop)
{
	pthread_mutex_lock(&fn_loops_lock);
	[fn_loops removeObjectIdenticalTo:loop];
	pthread_mutex_unlock(&fn_loops_lock);
}

/* **THE LOOKUP IS BORROWED, AND THE TWO DOORS THAT NEED OWNERSHIP TAKE IT.** This is called from the timer callback,
 * i.e. once per firing, so an autoreleased answer would be one autorelease per timer per pass for no gain: a loop in
 * the registry is alive for its thread's lifetime, and the loop asking the question is the loop that is running —
 * it cannot be deallocated under this call. */
static NSRunLoop *fn_loop_for_cfloop(CFRunLoopRef rl)
{
	NSRunLoop *found = nil;
	NSUInteger i;

	if (rl == NULL) {
		return nil;
	}
	pthread_mutex_lock(&fn_loops_lock);
	for (i = 0; i < [fn_loops count]; i++) {
		NSRunLoop *loop = [fn_loops objectAtIndex:i];

		if ([loop fn_cfLoop] == rl) {
			found = loop;
			break;
		}
	}
	pthread_mutex_unlock(&fn_loops_lock);
	return found;
}

/* THE THREAD-SPECIFIC THAT MAKES `+currentRunLoop` CHEAP, kept from the implementation this replaced: a run loop is
 * per-thread, and `+currentRunLoop` is asked on every pass of every loop. */
static pthread_key_t fn_loop_key;
static pthread_once_t fn_loop_key_once = PTHREAD_ONCE_INIT;
static BOOL fn_loop_key_ready = NO;

static void fn_make_loop_key(void)
{
	if (pthread_key_create(&fn_loop_key, NULL) == 0) {
		fn_loop_key_ready = YES;
	}
}


@interface NSTimer (FNPrivate)
- (CFRunLoopTimerRef)fn_cfTimer;
@end

static CFStringRef fn_cf_mode(NSRunLoop *loop, NSString *mode);
static void fn_performer_source_perform(void *info);
static void fn_phase_observer(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);
static void fn_runloop_source_dispatch_ready(void *context);
static void fn_source_finalize(void *context);

/* ====================================================================================================
 * THE FILE-DESCRIPTOR SOURCE
 *
 * A source is TWO objects now, and each has the half of the job it is good at. The DISPATCH source watches the
 * descriptor: libdispatch owns an epoll selector, so asking it is free of new threads and new fds, and it is the
 * only thing in the process that can answer "is this readable" without blocking the loop's own thread. The CF
 * SOURCE is how that answer reaches the loop: it is signalled from the dispatch queue and performed on the loop's
 * thread, which is where a target's selector must be sent (NSFileHandle's `-readabilityHandler` and NSSocketPort's
 * callback both say so).
 *
 * **ONE READINESS, ONE CALL.** A level-triggered dispatch source stays ready until the descriptor is drained, and
 * the first version of this design fired the target twice for one readiness (a spin this project has measured
 * before, in the select-based version: 29862 fires in two seconds). So the dispatch source SUSPENDS ITSELF when it
 * reports, and the CF source's perform RE-ARMS it after the target has run: one report, one call, and a descriptor
 * that is still readable reports again on the next pass — which is what "level-triggered" means and what the
 * source's contract has always been.
 * ==================================================================================================== */
@interface FNRunLoopSource : NSObject
{
	int _fd;
	BOOL _readable;
	NSString *_mode;		/* RETAINED */
	id _target;			/* ZEROING WEAK: the loop does not keep it alive */
	SEL _selector;
	CFRunLoopRef _cfLoop;		/* NOT RETAINED: the loop owns this source */
	CFRunLoopSourceRef _cfSource;	/* RETAINED (this object holds it; the loop holds it too while added) */
	dispatch_source_t _fdSource;	/* RETAINED (this object holds it) */
	pthread_mutex_t _lock;		/* guards `_armed`/`_removed`, which the dispatch queue and the loop both touch */
	BOOL _armed;			/* NO while the dispatch source is suspended awaiting the perform */
	BOOL _removed;			/* set by -uninstall: no report or re-arm may start after it */
}
- (instancetype)initWithFileDescriptor:(int)fd
				  mode:(NSString *)mode
			      readable:(BOOL)readable
				target:(id)target
			      selector:(SEL)selector;
- (int)fileDescriptor;
- (BOOL)isReadable;
- (NSString *)mode;
- (BOOL)hasTarget:(id)target;
- (BOOL)targetIsAlive;
/* TOLD WHICH LOOP IT IS BEING INSTALLED IN, THEN ADDED TO IT. `-uninstall` is the other half and is safe from
 * inside the perform (the array that owns this object may drop it while its own method is on the stack). */
- (void)installInRunLoop:(NSRunLoop *)loop;
- (void)uninstall;
/* THE DISPATCH QUEUE'S DOOR, declared here so the C trampoline above the implementation can reach it. */
- (void)fn_descriptorReady;
@end

static const void *fn_source_retain(const void *info)
{
	return [(id)info retain];
}

static void fn_source_release(const void *info)
{
	[(id)info release];
}

static void fn_source_perform(void *info);

@implementation FNRunLoopSource

- (instancetype)initWithFileDescriptor:(int)fd
				  mode:(NSString *)mode
			      readable:(BOOL)readable
				target:(id)target
			      selector:(SEL)selector
{
	self = [super init];
	if (self != nil) {
		_fd = fd;
		_readable = readable;
		_mode = [mode copy];
		objc_storeWeak(&_target, target);
		_selector = selector;
		_armed = YES;
		_removed = NO;
		pthread_mutex_init(&_lock, NULL);
	}
	return self;
}

- (int)fileDescriptor
{
	return _fd;
}

- (BOOL)isReadable
{
	return _readable;
}

- (NSString *)mode
{
	return _mode;
}

- (BOOL)hasTarget:(id)target
{
	return objc_loadWeak(&_target) == target;
}

- (BOOL)targetIsAlive
{
	return objc_loadWeak(&_target) != nil;
}

/* THE TARGET'S TURN, ON THE LOOP'S THREAD. Sent from the CF source's perform, and it re-arms the dispatch source
 * afterwards — unless the target removed this very source, in which case `_fdSource` is already gone and there is
 * nothing to re-arm. THE RETAIN/AUTORELEASE PAIR IS LOAD-BEARING: `-removeSourceForTarget:` called from inside the
 * target's selector drops the array's reference to this object, and without the pair that is a dealloc in the
 * middle of its own method. */
- (void)fireIfAlive
{
	id target;

	[self retain];
	target = objc_loadWeak(&_target);
	if (target != nil && _selector != NULL) {
		[target performSelector:_selector];
	}
	pthread_mutex_lock(&_lock);
	if (!_removed && !_armed && _fdSource != NULL) {
		_armed = YES;
		dispatch_resume(_fdSource);
	}
	pthread_mutex_unlock(&_lock);
	[self autorelease];
}

/* **THE DISPATCH QUEUE'S HALF: REPORT ONCE, THEN STAY QUIET UNTIL THE LOOP HAS CALLED THE TARGET.** Every step is
 * taken under the same lock `-uninstall` takes, and that is not tidiness: a suspend that lands after the loop has
 * already balanced it is a source released with a suspend count of one, which libdispatch treats as a programming
 * error and HALTS on. MEASURED as a ~45%-of-runs SIGILL in `_dispatch_queue_xref_dispose` at process exit before
 * the lock covered the suspend. Signalling under the lock is safe — `CFRunLoopSourceSignal` takes no callout. */
- (void)fn_descriptorReady
{
	pthread_mutex_lock(&_lock);
	if (!_armed || _removed) {
		pthread_mutex_unlock(&_lock);
		return;		/* a queued report for a readiness the loop has not answered yet, or one for a dead source */
	}
	_armed = NO;
	dispatch_suspend(_fdSource);
	if (_cfSource != NULL) {
		CFRunLoopSourceSignal(_cfSource);
	}
	if (_cfLoop != NULL) {
		CFRunLoopWakeUp(_cfLoop);
	}
	pthread_mutex_unlock(&_lock);
}

- (void)installInRunLoop:(NSRunLoop *)loop
{
	CFRunLoopSourceContext cfContext;
	static dispatch_queue_t fdQueue;

	if (_cfSource != NULL) {
		return;		/* already installed: a second install would watch one descriptor twice */
	}
	_cfLoop = [loop fn_cfLoop];
	memset(&cfContext, 0, sizeof(cfContext));
	cfContext.info = self;
	cfContext.retain = fn_source_retain;
	cfContext.release = fn_source_release;
	cfContext.perform = fn_source_perform;
	_cfSource = CFRunLoopSourceCreate(NULL, 0, &cfContext);
	if (_cfSource == NULL) {
		return;
	}
	CFRunLoopAddSource(_cfLoop, _cfSource, fn_cf_mode(loop, _mode));
	/* **A REGULAR FILE IS NOT A SOURCE, AND THE REASON MOVED RATHER THAN THE RULE.** `select(2)` never reported a
	 * file's descriptor as readable, which is what this tree's headers used to record; epoll reports one as ALWAYS
	 * readable, which is worse rather than better — MEASURED, a dispatch READ source on a regular file fired 9673
	 * times in 400 ms. So the rule stands (a file is not a readiness source here) and its mechanism is now a check
	 * rather than a kernel accident: the CF source is installed and never signalled, so the handler does not fire,
	 * which is what `NSFileHandle.h` promises a caller. The file remains fully usable synchronously. */
	{
		struct stat info;

		if (fstat(_fd, &info) == 0 && (S_ISREG(info.st_mode) || S_ISDIR(info.st_mode))) {
			return;
		}
	}
	/* THE WATCHING QUEUE IS ONE FOR THE PROCESS, serial, and never released: it outlives every source on it and a
	 * queue per descriptor would be a thread per descriptor in libdispatch's accounting. */
	if (fdQueue == NULL) {
		fdQueue = dispatch_queue_create("org.agora.foundation.runloop-fds", DISPATCH_QUEUE_SERIAL);
	}
	_fdSource = dispatch_source_create(_readable ? DISPATCH_SOURCE_TYPE_READ : DISPATCH_SOURCE_TYPE_WRITE,
					   (uintptr_t)_fd, 0, fdQueue);
	if (_fdSource == NULL) {
		CFRunLoopRemoveSource(_cfLoop, _cfSource, fn_cf_mode(loop, _mode));
		return;
	}
	/* THE HANDLER IS A C FUNCTION OVER THE CONTEXT RATHER THAN A BLOCK, because this library is MRC and a block
	 * here would need its own copy/release pair for no gain. **AND THE CONTEXT OWNS A REFERENCE**: a dispatch
	 * source's handler can run on its queue after the loop has dropped this object, so the source holds one
	 * reference and its FINALIZER gives it back — which is what makes `-uninstall` safe from any thread and from
	 * inside the perform. */
	dispatch_set_context(_fdSource, self);
	[self retain];		/* RELEASED by fn_source_finalize when the dispatch source is done */
	dispatch_set_finalizer_f(_fdSource, fn_source_finalize);
	dispatch_source_set_event_handler_f(_fdSource, fn_runloop_source_dispatch_ready);
	dispatch_resume(_fdSource);
}

- (void)uninstall
{
	dispatch_source_t fdSource;
	CFRunLoopSourceRef cfSource;
	BOOL resumeFirst = NO;

	/* **THE DECISION IS TAKEN UNDER THE LOCK AND THE CALLS ARE MADE OUTSIDE IT.** Releasing a dispatch source can
	 * run its finalizer synchronously, and the finalizer releases this object, which may deallocate it and call
	 * this door again — a non-recursive mutex held across that is a deadlock. So the lock protects the state, and
	 * only the state: which objects to release, and whether a suspended one has to be resumed first (libdispatch
	 * HALTS on a source released with a suspend count). */
	pthread_mutex_lock(&_lock);
	_removed = YES;
	if (_fdSource != NULL && !_armed) {
		_armed = YES;
		resumeFirst = YES;
	}
	fdSource = _fdSource;
	cfSource = _cfSource;
	_fdSource = NULL;
	_cfSource = NULL;
	_cfLoop = NULL;
	pthread_mutex_unlock(&_lock);

	if (fdSource != NULL) {
		if (resumeFirst) {
			dispatch_resume(fdSource);
		}
		dispatch_source_set_event_handler_f(fdSource, NULL);
		dispatch_source_cancel(fdSource);
		dispatch_release(fdSource);
	}
	if (cfSource != NULL) {
		CFRunLoopSourceInvalidate(cfSource);
		CFRelease(cfSource);
	}
}

- (void)dealloc
{
	[self uninstall];
	objc_storeWeak(&_target, nil);
	pthread_mutex_destroy(&_lock);
	[_mode release];
	[super dealloc];
}

@end

static void fn_runloop_source_dispatch_ready(void *context)
{
	[(FNRunLoopSource *)context fn_descriptorReady];
}

static void fn_source_perform(void *info)
{
	[(FNRunLoopSource *)info fireIfAlive];
}

/* THE DISPATCH SOURCE'S FINALIZER: the reference `-installInRunLoop:` took for it. It runs once the source has been
 * cancelled and released by every party, which is exactly the moment no handler can be queued any more. */
static void fn_source_finalize(void *context)
{
	[(id)context release];
}

/* ====================================================================================================
 * NSTimer — now a thin body over a CFRunLoopTimer.
 *
 * THE TIMER OWNS THE CF TIMER; THE CF TIMER BORROWS THE NSTIMER. That asymmetry is the lifetime rule: `NSRunLoop`
 * retains every timer it has scheduled (see `-_timers`), so a scheduled `NSTimer` cannot be deallocated out from
 * under a running loop, and the CF callback's `info` is therefore always live. The reverse reference is NOT a CF
 * context retain on purpose: an invalidation that released the context's reference would be able to run
 * `-dealloc` inside `CFRunLoopTimerInvalidate`, and `-dealloc` releases the very timer being invalidated.
 * ==================================================================================================== */

static NSRunLoop *fn_loop_being_run(void)
{
	return fn_loop_for_cfloop(CFRunLoopGetCurrent());
}

static void fn_timer_callback(CFRunLoopTimerRef cfTimer, void *info)
{
	NSTimer *timer = (NSTimer *)info;

	(void)cfTimer;
	[fn_loop_being_run() fnNoteWork];
	[timer fire];
}

@implementation NSTimer

/* CFRunLoopTimerGetNextFireDate DISPATCHES TO THIS, AND IT ANSWERS A CFAbsoluteTime (CFRunLoop.c:4577) --
 * this Foundation's reference-date convention already, so the date door is the whole implementation.
 * Found by the surface survey. */
- (CFAbsoluteTime)_cffireTime
{
	NSDate *fire = [self fireDate];

	return (fire != nil) ? (CFAbsoluteTime)[fire timeIntervalSinceReferenceDate] : (CFAbsoluteTime)0.0;
}

- (CFRunLoopTimerRef)fn_cfTimer
{
	return (CFRunLoopTimerRef)_cfTimer;
}

- (void)fnMakeCFTimer
{
	CFRunLoopTimerContext context;
	CFTimeInterval interval = 0.0;

	memset(&context, 0, sizeof(context));
	context.info = self;	/* BORROWED: see the block above NSTimer's implementation */
	if (_repeats) {
		/* CF's rule is interval > 0 = repeat; a repeating timer with a zero or negative interval would fire as
		 * fast as the loop can turn, which is what Apple's does too, so it is clamped to the smallest interval
		 * CF will honour rather than silently becoming a one-shot. */
		interval = (_interval > 0.0) ? _interval : 1.0e-6;
	}
	_cfTimer = (struct __CFRunLoopTimer *)CFRunLoopTimerCreate(NULL,
					(CFAbsoluteTime)[_fireDate timeIntervalSinceReferenceDate],
					interval, 0, 0, fn_timer_callback, &context);
	if (_cfTimer != NULL && _tolerance > 0.0) {
		CFRunLoopTimerSetTolerance(_cfTimer, _tolerance);
	}
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval
			    target:(id)target
			  selector:(SEL)selector
			  userInfo:(nullable id)userInfo
			   repeats:(BOOL)repeats
{
	return [[[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:interval]
				      interval:interval
					target:target
				      selector:selector
				      userInfo:userInfo
				       repeats:repeats] autorelease];
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
				     target:(id)target
				   selector:(SEL)selector
				   userInfo:(nullable id)userInfo
				    repeats:(BOOL)repeats
{
	NSTimer *timer = [self timerWithTimeInterval:interval
					      target:target
					    selector:selector
					    userInfo:userInfo
					     repeats:repeats];

	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
	return timer;
}

- (instancetype)initWithFireDate:(NSDate *)date
			interval:(NSTimeInterval)interval
			  target:(id)target
			selector:(SEL)selector
			userInfo:(nullable id)userInfo
			 repeats:(BOOL)repeats
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_interval = interval;
	_target = target;
	_selector = selector;
	/* RETAINED, BECAUSE THE TIMER OUTLIVES THE CALL: a fire date is usually `+dateWithTimeIntervalSinceNow:`,
	 * which is AUTORELEASED — so a timer that stored it would read a recycled object at its next fire, and
	 * the symptom is a fire date that keeps LOOKING 10ms in the future (measured). -dealloc releases both. */
	_userInfo = [userInfo retain];
	_fireDate = [(date != nil ? date : [NSDate date]) retain];
	_repeats = repeats;
	/* VALID FROM THE START, because a timer handed to a caller is one they may FIRE even if they
	 * never add it — which is what +timerWithTimeInterval: is for. */
	_valid = YES;
	[self fnMakeCFTimer];
	return self;
}

- (void)fire
{
	if (_cfTimer == NULL || !CFRunLoopTimerIsValid(_cfTimer)) {
		return;
	}
	/* A BODY THAT IS A BLOCK OR AN INVOCATION FIRES THE SAME WAY A TARGET DOES. There is no rescheduling here any
	 * more: COREFOUNDATION MOVES A REPEATING TIMER'S FIRE DATE BEFORE IT CALLS OUT, so a body that reads the clock
	 * or calls -fireDate sees the next fire rather than the one that is happening. */
	if (_firing) {
		return;		/* a body that fires its own timer is a loop; Apple's does nothing either */
	}
	_firing = YES;
	if (_block != nil) {
		((void (^)(NSTimer *))_block)(self);
	} else if (_invocation != nil) {
		id argument = self;

		[_invocation setArgument:&argument atIndex:2];
		[_invocation invoke];
	} else if (_target != nil && _selector != NULL) {
		[_target performSelector:_selector withObject:self];
	}
	_firing = NO;
	/* AND THE DATE MIRROR FOLLOWS THE ENGINE, so a repeating timer's -fireDate answers the NEXT firing. */
	if (CFRunLoopTimerIsValid(_cfTimer)) {
		CFAbsoluteTime at = CFRunLoopTimerGetNextFireDate(_cfTimer);

		if (at != 0.0) {
			NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)at];

			[_fireDate release];
			_fireDate = next;
		}
	}
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval
			   repeats:(BOOL)repeats
			     block:(void (^)(NSTimer *timer))block
{
	return [[[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:interval]
				      interval:interval
				       repeats:repeats
					 block:block] autorelease];
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
				    repeats:(BOOL)repeats
				      block:(void (^)(NSTimer *timer))block
{
	NSTimer *timer = [self timerWithTimeInterval:interval repeats:repeats block:block];

	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
	return timer;
}

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval
			invocation:(NSInvocation *)invocation
			   repeats:(BOOL)repeats
{
	NSTimer *timer = [[self alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:interval]
					       interval:interval
						 target:nil
					       selector:NULL
					       userInfo:nil
						repeats:repeats];

	timer->_invocation = [invocation retain];
	return [timer autorelease];
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
				 invocation:(NSInvocation *)invocation
				    repeats:(BOOL)repeats
{
	NSTimer *timer = [self timerWithTimeInterval:interval invocation:invocation repeats:repeats];

	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
	return timer;
}

- (instancetype)initWithFireDate:(NSDate *)date
			interval:(NSTimeInterval)interval
			 repeats:(BOOL)repeats
			   block:(void (^)(NSTimer *timer))block
{
	self = [self initWithFireDate:date interval:interval target:nil selector:NULL userInfo:nil repeats:repeats];
	if (self != nil) {
		/* A HEAP COPY, TAKEN WITH THE RUNTIME'S OWN ENTRY POINT: a stack block does not outlive the call
		 * that handed it over, and the copy cannot depend on the block's isa. The rule and the gate that
		 * enforces it are in NSBlockOperation.m and make foundation-gate. */
		_block = Block_copy(block);
	}
	return self;
}

- (NSTimeInterval)tolerance
{
	return _tolerance;
}

- (void)setTolerance:(NSTimeInterval)tolerance
{
	_tolerance = tolerance;
	if (_cfTimer != NULL) {
		CFRunLoopTimerSetTolerance(_cfTimer, tolerance);
	}
}

- (void)dealloc
{
	if (_cfTimer != NULL) {
		CFRunLoopTimerInvalidate(_cfTimer);
		CFRelease(_cfTimer);
		_cfTimer = NULL;
	}
	Block_release(_block);
	[_invocation release];
	[_fireDate release];
	[_userInfo release];
	[super dealloc];
}

/* **INVALIDATE IS COREFOUNDATION'S, AND THE RELEASE IS -dealloc's.** CF's invalidation removes the timer from every
 * loop and mode it is in; the reference this object holds to the CF timer is dropped once, in -dealloc, so a timer
 * that is invalidated by a fire (a one-shot) and one that is invalidated by hand take the same path. */
- (void)invalidate
{
	if (_cfTimer != NULL) {
		CFRunLoopTimerInvalidate(_cfTimer);
	}
	_valid = NO;
}

- (BOOL)isValid
{
	if (_cfTimer == NULL) {
		return NO;
	}
	return CFRunLoopTimerIsValid(_cfTimer) ? YES : NO;
}

- (NSDate *)fireDate
{
	/* **COREFOUNDATION IS THE AUTHORITY WHILE THE TIMER IS VALID**, which is what makes a repeating timer's date
	 * answer the NEXT firing: CF moves `_nextFireDate` after the callout returns (CFRunLoop.c's
	 * `__CFRunLoopDoTimer`), so reading through it is right for a caller asking between fires — and a caller asking
	 * inside the body gets the fire that is happening, which is also what CF's own answer is. AFTER INVALIDATION
	 * the mirror answers: a timer that has fired is spent, and Apple's `-fireDate` keeps naming the date it was
	 * scheduled for rather than becoming nil. */
	if (_cfTimer != NULL && CFRunLoopTimerIsValid(_cfTimer)) {
		CFAbsoluteTime at = CFRunLoopTimerGetNextFireDate(_cfTimer);

		if (at != 0.0) {
			return [NSDate dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)at];
		}
	}
	return _fireDate;
}

- (void)setFireDate:(NSDate *)fireDate
{
	/* THE OLD ONE IS RELEASED AND THE NEW ONE RETAINED, so the ownership stays paired with -dealloc. */
	[fireDate retain];
	[_fireDate release];
	_fireDate = fireDate;
	if (_cfTimer != NULL && fireDate != nil) {
		CFRunLoopTimerSetNextFireDate(_cfTimer, (CFAbsoluteTime)[fireDate timeIntervalSinceReferenceDate]);
	}
}

- (NSTimeInterval)timeInterval
{
	return _interval;
}

- (nullable id)userInfo
{
	return _userInfo;
}

/* THE PRIMITIVE THE OTHER DOORS DO NOT NAME, and it exists because -description reads it: a Core
 * Foundation-owned timer has no `_repeats`, and CF's own door for the question is
 * CFRunLoopTimerDoesRepeat. */
- (BOOL)fnRepeats
{
	return _repeats;
}

- (NSString *)description
{
	/* OVER THE ACCESSORS AND NOT THE IVARS, for the reason every other type's description was routed: a Core
	 * Foundation-owned timer has none of them, and CFCopyDescription reaches this through NSObject's
	 * -_copyDescription. THE TEXT IS UNCHANGED. */
	return [NSString stringWithFormat:@"<%@: %p interval=%.3f repeats=%d valid=%d>", [self class],
				  self, [self timeInterval], (int)[self fnRepeats], (int)[self isValid]];
}

@end

/* ====================================================================================================
 * THE PERFORMER OBJECT (§62.62) — declared HERE, before the class that keeps them, because an object type has to
 * be known before it is used and the doors belong in the class's own block, where Apple declares them.
 *
 * A PERFORMER IS A REQUEST, NOT A CALL: Apple's -performSelector:target:argument:order:modes: "sets up a timer to
 * perform the aSelector message ... at the start of the next run loop iteration", so nothing sends a message when
 * the door is called — the door SCHEDULES. It used to be scheduled by a poll at the top of every pass; it is now
 * scheduled by SIGNALLING THE LOOP'S PERFORMER SOURCE, which is what makes a performer enqueued by another thread
 * wake a loop that is blocked in CoreFoundation's wait rather than waiting out any poll.
 *
 * AND THE RECEIVER OWNS WHAT IT WAS GIVEN: Apple's own words — "the receiver retains the target and anArgument
 * objects until the timer for the message fires". Both are RETAINED for as long as the request is pending, which
 * is the difference between a request that survives its caller and one that does not. The block forms hold a
 * Block_copy for the same reason.
 * ==================================================================================================== */

@interface FNPerformer : NSObject
{
@public
	BOOL _isBlock;
	SEL _selector;
	id _target;		/* RETAINED while pending (Apple's rule, above) */
	id _argument;		/* RETAINED */
	id _block;		/* Block_copy'd, released in -dealloc */
	NSUInteger _order;
	NSArray *_modes;	/* retained; never nil and never empty */
}
@end

@implementation FNPerformer

- (void)dealloc
{
	[_target release];
	[_argument release];
	[_modes release];
	if (_block != nil) {
		Block_release(_block);
	}
	[super dealloc];		/* NSObject's -dealloc is what frees the instance */
}

@end

/* CALL A BLOCK WITHOUT SPELLING ITS CAST AT THE CALL SITE, and that is a GATE requirement rather than a style
 * one: tools/foundation-gate.py collects the names a file's block declarations introduce with a regex whose
 * second alternative matches a block-CAST expression followed by an identifier, so an inline cast at a call site
 * makes the CAST'S RECEIVER a "block name" for the whole file — and every later release send to that receiver is
 * then reported as a block owned with a message send. The cast lives in one place instead. */
static void fn_invoke_block(id block)
{
	if (block != nil) {
		((void (^)(void))block)();
	}
}

/* MAY THIS PERFORMER BE SENT IN `mode`? The list-walking half of the shared rule (§62.62's FNRunLoopModes.h). */
static BOOL fn_performer_modes_allow(FNPerformer *performer, NSString *mode)
{
	NSUInteger i;

	if (mode == nil || [performer->_modes count] == 0) {
		return NO;
	}
	for (i = 0; i < [performer->_modes count]; i++) {
		if (FNRunLoopModeAllows([performer->_modes objectAtIndex:i], mode)) {
			return YES;
		}
	}
	return NO;
}

/* **THE PERFORMER SOURCE'S PERFORM, AND THE PHASE OBSERVER'S CALLOUT.** Both run on the loop's own thread and both
 * do exactly one thing: hand the loop the work it was woken for. The performer drain is kept whole (all due
 * performers in one call) so that a performer scheduling another performer belongs to the NEXT pass. */
static void fn_performer_source_perform(void *info)
{
	NSRunLoop *loop = (NSRunLoop *)info;

	[loop fnNoteWork];
	[loop fnRunPerformersInMode:[loop currentMode]];
}

/* THE QUEUE'S TWO PHASES, IN APPLE'S ORDER: "as soon as possible" is the end of the callout that just ran, and
 * "when idle" is the wait that is about to begin. Both are posted through the queue's own seam, so the queue keeps
 * owning what is pending and this file only says when. */
static void fn_phase_observer(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
	NSRunLoop *loop = (NSRunLoop *)info;

	(void)observer;
	if ((activity & kCFRunLoopBeforeWaiting) == 0) {
		return;
	}
	[NSNotificationQueue fnPostPendingWhenIdle:NO mode:[loop currentMode]];
	[NSNotificationQueue fnPostPendingWhenIdle:YES mode:[loop currentMode]];
}

/* ====================================================================================================
 * THE MODE RULE, DEFINED ONCE (§62.62) — AND IT IS STILL THE ONLY DEFINITION.
 *
 * It used to live here as a static for timers while NSNotificationQueue.m kept a SECOND, WRONGER copy
 * (`-isEqual:` on the names, no common-modes clause), so a notification enqueued `forModes:@[NSRunLoopCommonModes]`
 * could never be posted even though a timer added for the common modes fires in every mode. One function now, with
 * three callers: the performers, the notification queue and the block below that translates a mode for
 * CoreFoundation.
 * ==================================================================================================== */
BOOL FNRunLoopModeAllows(NSString *entryMode, NSString *runningMode)
{
	if (entryMode == nil || runningMode == nil) {
		return NO;
	}
	if ([entryMode isEqualToString:runningMode]) {
		return YES;
	}
	if ([entryMode isEqualToString:NSRunLoopCommonModes]) {
		return YES;			/* the common set is everything */
	}
	return [runningMode isEqualToString:NSRunLoopCommonModes];
}

/* **THE TRANSLATION, AND THE ONE DECISION IN IT.** A mode name goes to CoreFoundation as itself, except the two
 * special ones; and every ordinary mode this loop is asked to run is ALSO registered as a common mode of its CF
 * loop. That is what keeps `FNRunLoopModeAllows`'s rule true on the other side: a timer added for mode X fires
 * when the loop runs the common modes (X is a common mode now), and a source added for the common modes fires in
 * X (CoreFoundation copies common-mode items into a mode when it becomes common). Registering is idempotent and
 * does nothing for a mode CoreFoundation already knows. */
static CFStringRef fn_cf_mode(NSRunLoop *loop, NSString *mode)
{
	CFStringRef name;

	if (mode == nil || [mode isEqualToString:NSDefaultRunLoopMode]) {
		return kCFRunLoopDefaultMode;
	}
	if ([mode isEqualToString:NSRunLoopCommonModes]) {
		return kCFRunLoopCommonModes;
	}
	name = (CFStringRef)mode;
	CFRunLoopAddCommonMode([loop fn_cfLoop], name);
	return name;
}

@implementation NSRunLoop

static void fn_register_loop_with_thread(NSRunLoop *loop, NSThread *thread)
{
	if (thread == nil) {
		return;
	}
	pthread_mutex_lock(&fn_loop_owner_lock);
	/* THE DICTIONARY RETAINS THE LOOP, and the loop already lives for the thread's lifetime (the pthread-specific
	 * owns it), so this is one reference held as long as both do rather than a leak with no owner. */
	[[thread threadDictionary] setObject:loop forKey:FNRunLoopThreadStoreKey];
	pthread_mutex_unlock(&fn_loop_owner_lock);
}

+ (NSRunLoop *)fn_runLoopForThread:(NSThread *)thread
{
	NSRunLoop *loop;

	if (thread == nil) {
		return nil;
	}
	pthread_mutex_lock(&fn_loop_owner_lock);
	loop = [[[thread threadDictionary] objectForKey:FNRunLoopThreadStoreKey] retain];
	pthread_mutex_unlock(&fn_loop_owner_lock);
	return [loop autorelease];
}

/* THE DESIGNATED (INTERNAL) INITIALISER: bind to a thread's CF loop and contribute the two sources this class adds
 * to it. `+currentRunLoop` passes `CFRunLoopGetCurrent()`; `+mainRunLoop` passes `CFRunLoopGetMain()`, which is why
 * a wrapper for the main loop can be made from a thread that is not main. */
- (instancetype)fn_initWithCFRunLoop:(CFRunLoopRef)rl
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_cfLoop = (rl != NULL) ? rl : CFRunLoopGetCurrent();
	CFRetain(_cfLoop);
	_currentMode = [NSDefaultRunLoopMode copy];
	fn_loops_add(self);
	/* THE PERFORMER SOURCE: one, in the common modes, performed on this loop's thread. */
	{
		CFRunLoopSourceContext context;

		memset(&context, 0, sizeof(context));
		context.info = self;
		context.perform = fn_performer_source_perform;
		_performerSource = CFRunLoopSourceCreate(NULL, 0, &context);
		if (_performerSource != NULL) {
			CFRunLoopAddSource(_cfLoop, _performerSource, kCFRunLoopCommonModes);
		}
	}
	/* AND THE PHASE OBSERVER: the queue's two points, which are observer activities rather than a loop detail. */
	{
		CFRunLoopObserverContext context;

		memset(&context, 0, sizeof(context));
		context.info = self;
		_phaseObserver = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting, true, 0,
							 fn_phase_observer, &context);
		if (_phaseObserver != NULL) {
			CFRunLoopAddObserver(_cfLoop, _phaseObserver, kCFRunLoopCommonModes);
		}
	}
	return self;
}

- (instancetype)init
{
	return [self fn_initWithCFRunLoop:CFRunLoopGetCurrent()];
}

- (void)dealloc
{
	if (_performerSource != NULL) {
		CFRunLoopRemoveSource(_cfLoop, _performerSource, kCFRunLoopCommonModes);
		CFRunLoopSourceInvalidate(_performerSource);
		CFRelease(_performerSource);
		_performerSource = NULL;
	}
	if (_phaseObserver != NULL) {
		CFRunLoopRemoveObserver(_cfLoop, _phaseObserver, kCFRunLoopCommonModes);
		CFRelease(_phaseObserver);
		_phaseObserver = NULL;
	}
	if (_sources != nil) {
		NSArray *snapshot = [_sources copy];
		NSUInteger i;

		for (i = 0; i < [snapshot count]; i++) {
			[[snapshot objectAtIndex:i] uninstall];
		}
		[snapshot release];
		[_sources release];
		_sources = nil;
	}
	fn_loops_remove(self);
	[_timers release];
	[_performers release];
	[_currentMode release];
	if (_cfLoop != NULL) {
		CFRelease(_cfLoop);
		_cfLoop = NULL;
	}
	[super dealloc];
}

+ (NSRunLoop *)currentRunLoop
{
	NSRunLoop *loop;

	pthread_once(&fn_loop_key_once, fn_make_loop_key);
	loop = fn_loop_key_ready ? (NSRunLoop *)pthread_getspecific(fn_loop_key) : nil;
	if (loop == nil) {
		CFRunLoopRef cf = CFRunLoopGetCurrent();

		/* **THE REGISTRY IS CONSULTED BEFORE A WRAPPER IS MADE**, because `+mainRunLoop` (or a sibling thread) may
		 * already have made one for this very CF loop: two wrappers around one loop would be two mode strings, two
		 * performer sources and two phase observers delivering the same events. */
		loop = [fn_loop_for_cfloop(cf) retain];
		if (loop == nil) {
			loop = [[NSRunLoop alloc] fn_initWithCFRunLoop:cf];
		}
		if (fn_loop_key_ready) {
			pthread_setspecific(fn_loop_key, (void *)loop);
		}
		fn_register_loop_with_thread(loop, [NSThread currentThread]);
	}
	return loop;
}

+ (NSRunLoop *)mainRunLoop
{
	NSRunLoop *loop = fn_loop_for_cfloop(CFRunLoopGetMain());

	if (loop != nil) {
		return loop;	/* alive for the main thread's lifetime, which is this process's */
	}
	/* NO WRAPPER YET: make one for the MAIN loop rather than for whichever loop the CALLING thread owns — that was
	 * the old answer (`fn_first_loop`), and it made `+mainRunLoop` from a worker thread answer the worker's loop. */
	return [[[NSRunLoop alloc] fn_initWithCFRunLoop:CFRunLoopGetMain()] autorelease];
}

- (NSString *)currentMode
{
	return _currentMode;
}

- (void)fnSetCurrentMode:(NSString *)mode
{
	NSString *wanted = (mode != nil ? mode : NSDefaultRunLoopMode);

	/* A PASS NAMES ITS MODE EVERY TIME, and the mode it names is almost always the one already current: copying it
	 * per frame would be sixty allocations a second for a string that did not change. */
	if (_currentMode != nil && [_currentMode isEqualToString:wanted]) {
		return;
	}
	[_currentMode release];
	_currentMode = [wanted copy];
}

- (void)fnNoteWork
{
	_workCount++;
}

/* ---- TIMERS ------------------------------------------------------------------------------------------ */

/* **THE LIFETIME HOLDER, PRUNED AT THE TOP OF EVERY PASS.** A scheduled timer's CF timer is retained by
 * CoreFoundation, but the CF timer does not retain the NSTIMER (see the note above NSTimer's implementation), so
 * this array is what keeps one alive across a caller that let go of it — Apple's own rule, and the old
 * implementation's too. A timer is pruned the pass after it is invalidated, which is when a one-shot expires. */
- (void)fnPruneTimers
{
	NSUInteger i = 0;

	while (i < [_timers count]) {
		NSTimer *timer = [_timers objectAtIndex:i];

		if ([timer isValid]) {
			i++;
			continue;
		}
		[_timers removeObjectAtIndex:i];
	}
}

- (void)addTimer:(NSTimer *)timer forMode:(NSString *)mode
{
	CFRunLoopTimerRef cfTimer;

	if (timer == nil || mode == nil) {
		return;
	}
	cfTimer = [timer fn_cfTimer];
	if (cfTimer == NULL) {
		return;
	}
	if (_timers == nil) {
		_timers = [[NSMutableArray alloc] init];
	}
	if (![_timers containsObject:timer]) {
		[_timers addObject:timer];	/* RETAINED: see -fnPruneTimers */
	}
	CFRunLoopAddTimer(_cfLoop, cfTimer, fn_cf_mode(self, mode));
}

/* ---- FILE-DESCRIPTOR SOURCES ------------------------------------------------------------------------- */

- (NSMutableArray *)fnSources
{
	if (_sources == nil) {
		_sources = [[NSMutableArray alloc] init];
	}
	return _sources;
}

- (void)addSourceForFileDescriptor:(int)fd
			      mode:(NSRunLoopMode)mode
			  readable:(BOOL)readable
			    target:(id)target
			  selector:(SEL)selector
{
	FNRunLoopSource *source = [[FNRunLoopSource alloc] initWithFileDescriptor:fd
									   mode:(mode != nil ? mode : NSDefaultRunLoopMode)
								       readable:readable
									 target:target
								       selector:selector];

	[source installInRunLoop:self];
	[[self fnSources] addObject:source];
	[source release];
}

- (void)removeSourceForTarget:(id)target
{
	NSMutableArray *sources = [self fnSources];
	NSUInteger i = 0;

	while (i < [sources count]) {
		FNRunLoopSource *source = [sources objectAtIndex:i];

		if ([source hasTarget:target]) {
			[source uninstall];
			[sources removeObjectAtIndex:i];	/* the array releases it */
			continue;
		}
		i++;
	}
}

/* ---- THE MODE QUESTION AND THE PASSES ----------------------------------------------------------------- */

- (BOOL)fnHasLiveWorkForMode:(NSString *)mode
{
	NSUInteger i;

	for (i = 0; i < [_timers count]; i++) {
		if ([(NSTimer *)[_timers objectAtIndex:i] isValid]) {
			return YES;
		}
	}
	for (i = 0; i < [_sources count]; i++) {
		FNRunLoopSource *source = [_sources objectAtIndex:i];

		if ([source targetIsAlive] && [source mode] != nil) {
			return YES;
		}
	}
	return [NSNotificationQueue fnHasPendingWorkForMode:mode] || [self fnHasPendingPerformerForMode:mode];
}

/* **ONE PASS, WHICH IS `CFRunLoopRunInMode` WITH A ZERO TIMEOUT.** The door is documented as one pass and that is
 * exactly what a zero-length run is: CoreFoundation fires the timers that are due, performs the sources that are
 * signalled, services the dispatch main queue's port if this is the main loop, and returns. Nothing waits, so this
 * is the call the AppKit makes once per frame. */
- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limit
{
	unsigned long before;

	(void)limit;		/* one pass: the deadline is -runUntilDate:'s and -run's business */
	[self fnSetCurrentMode:mode];
	[self fnPruneTimers];
	before = _workCount;
	CFRunLoopRunInMode(fn_cf_mode(self, _currentMode), 0.0, true);
	/* **THE TWO NOTIFICATION PHASES FOR A PASS THAT NEVER WAITS.** CoreFoundation runs the BeforeWaiting observer
	 * only when the pass is going to block (it skips observers when polling), so a zero-second pass — the AppKit's
	 * frame — has to give the queue its points itself, in Apple's order: "as soon as possible" is the end of this
	 * pass's callouts, and "when idle" is immediately after it because the pass is over. */
	[NSNotificationQueue fnPostPendingWhenIdle:NO mode:_currentMode];
	[NSNotificationQueue fnPostPendingWhenIdle:YES mode:_currentMode];
	return (_workCount != before) || [self fnHasLiveWorkForMode:_currentMode];
}

/* THE WAITING PASSES ARE COREFOUNDATION'S TOO, and nothing is polled: `CFRunLoopRunInMode` blocks in an epoll
 * selector that already contains the loop's wakeup port (so `-performSelector:onThread:` and
 * `CFRunLoopSourceSignal` reach it at once) and, on the main loop, the dispatch main queue's port. The one case it
 * does not cover is a loop with NOTHING in it: CoreFoundation answers `kCFRunLoopRunFinished` at once, and a loop
 * that returned immediately would spin — so that one answer sleeps the wait cap, which is what lets a request
 * enqueued by another thread be noticed rather than spun past. */
- (void)fnPumpForSeconds:(double)seconds
{
	SInt32 result;

	if (seconds > 1.0e10) {
		seconds = 1.0e10;
	}
	[self fnPruneTimers];
	result = CFRunLoopRunInMode(fn_cf_mode(self, _currentMode), seconds, false);
	if (result == kCFRunLoopRunFinished) {
		struct timespec pause;

		pause.tv_sec = 0;
		pause.tv_nsec = 50 * 1000 * 1000;	/* the old wait cap, now only for an empty loop */
		nanosleep(&pause, NULL);
	}
}

- (void)runUntilDate:(NSDate *)limit
{
	for (;;) {
		double left = (limit != nil) ? [limit timeIntervalSinceNow] : 1.0e10;

		if (left <= 0.0) {
			return;
		}
		[self fnPumpForSeconds:left];
	}
}

- (void)run
{
	[self fnSetCurrentMode:NSDefaultRunLoopMode];
	for (;;) {
		[self fnPumpForSeconds:1.0e10];
	}
}

- (BOOL)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate
{
	/* APPLE'S ONE-TURN DOOR, and this loop already has that turn: run it. The return is the same answer
	 * -runMode:beforeDate: gives — whether anything was processed. */
	return [self runMode:mode beforeDate:limitDate];
}

- (NSDate *)limitDateForMode:(NSRunLoopMode)mode
{
	CFAbsoluteTime at = CFRunLoopGetNextTimerFireDate(_cfLoop, fn_cf_mode(self, mode));

	if (at == 0.0) {
		return nil;
	}
	return [NSDate dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)at];
}

/* ---- PORTS AND THE SERVER DOOR ----------------------------------------------------------------------- */

/* APPLE'S PORT DOOR: IT IS THE FORWARD AND NOTHING ELSE. A port already knows how to be watched —
 * NSPort declares `-scheduleInRunLoop:forMode:`, and NSSocketPort implements it by registering its
 * descriptor with THIS loop's source seam (§43) — so the run loop's job is to say "watch yourself
 * here" and let the concrete port decide what that means. A loop that kept its own port list would be
 * a second registry to keep in step with the first. */
- (void)addPort:(NSPort *)aPort forMode:(NSRunLoopMode)mode
{
	[aPort scheduleInRunLoop:self forMode:mode];
}

- (void)removePort:(NSPort *)aPort forMode:(NSRunLoopMode)mode
{
	[aPort removeFromRunLoop:self forMode:mode];
}

- (void)configureAsServer
{
	/* APPLE: "This method does nothing." Kept so source that calls it links and runs. */
}

/* ---- THE PERFORMERS (§62.62) ------------------------------------------------------------------------- */

- (NSMutableArray *)fnPerformers
{
	if (_performers == nil) {
		_performers = [[NSMutableArray alloc] init];
	}
	return _performers;
}

/* **AN ENQUEUE WAKES THE LOOP, WHICHEVER THREAD MADE IT.** The source is signalled and the loop is woken, so a
 * `-performSelector:onThread:` from a worker reaches a loop that is blocked in CoreFoundation's wait immediately
 * rather than at the next poll. Signalling an unscheduled source is not possible — the source is added in -init —
 * and signalling twice before a pass is idempotent (a source is either signalled or not). */
- (void)fnSignalPerformers
{
	if (_performerSource != NULL) {
		CFRunLoopSourceSignal(_performerSource);
		CFRunLoopWakeUp(_cfLoop);
	}
}

- (void)performSelector:(SEL)aSelector
		 target:(id)target
	       argument:(nullable id)arg
		  order:(NSUInteger)order
		  modes:(NSArray *)modes
{
	FNPerformer *performer;

	if (target == nil) {
		return;		/* there is nothing to send to; Apple publishes no meaning for a nil target here */
	}
	performer = [[FNPerformer alloc] init];
	performer->_selector = aSelector;
	performer->_target = [target retain];
	performer->_argument = [arg retain];
	performer->_order = order;
	performer->_modes = [[NSArray alloc] initWithArray:(modes != nil && [modes count] > 0)
				   ? modes : [NSArray arrayWithObject:NSDefaultRunLoopMode]];
	/* THE ONLY QUEUE IN THIS CLASS THAT ANOTHER THREAD WRITES. `-performSelector:onThread:` reaches a loop it does
	 * not own, and a request appended while the owner is walking the array is a crash rather than a race. */
	pthread_mutex_lock(&fn_performer_queue_lock);
	[[self fnPerformers] addObject:performer];
	pthread_mutex_unlock(&fn_performer_queue_lock);
	[performer release];		/* ... the array owns it now */
	[self fnSignalPerformers];
}

- (void)performBlock:(void (^)(void))block
{
	/* APPLE'S PAGE DOES NOT STATE THE MODES; the developer-forum resolution cited in the header does — the
	 * default mode — and it is implemented here rather than inferred. */
	[self performInModes:[NSArray arrayWithObject:NSDefaultRunLoopMode] block:block];
}

- (void)performInModes:(NSArray *)modes block:(void (^)(void))block
{
	FNPerformer *performer;

	if (block == nil) {
		return;
	}
	performer = [[FNPerformer alloc] init];
	performer->_isBlock = YES;
	performer->_block = Block_copy(block);	/* the runtime's own entry point: the run loop holds it past the call */
	performer->_modes = [[NSArray alloc] initWithArray:(modes != nil && [modes count] > 0)
				   ? modes : [NSArray arrayWithObject:NSDefaultRunLoopMode]];
	pthread_mutex_lock(&fn_performer_queue_lock);
	[[self fnPerformers] addObject:performer];
	pthread_mutex_unlock(&fn_performer_queue_lock);
	[performer release];
	[self fnSignalPerformers];
}

/* THE TWO CANCELS DIFFER IN WHAT THEY MATCH, and Apple states the difference in as many words:
 * -cancelPerformSelector:target:argument: requires "the selector and argument as well as the target", while
 * -cancelPerformSelectorsWithTarget: "cancels the previously scheduled messages associated with the target,
 * IGNORING THE SELECTOR AND ARGUMENT ... from ALL MODES". Neither touches a block performer, which has no
 * target to match. */
- (void)cancelPerformSelector:(SEL)aSelector target:(id)target argument:(nullable id)arg
{
	NSUInteger i = 0;

	pthread_mutex_lock(&fn_performer_queue_lock);
	while (_performers != nil && i < [_performers count]) {
		FNPerformer *performer = [_performers objectAtIndex:i];

		if (!performer->_isBlock && performer->_selector == aSelector &&
		    performer->_target == target && performer->_argument == arg) {
			[_performers removeObjectAtIndex:i];	/* the array releases it */
			continue;
		}
		i++;
	}
	pthread_mutex_unlock(&fn_performer_queue_lock);
}

- (void)cancelPerformSelectorsWithTarget:(id)target
{
	NSUInteger i = 0;

	pthread_mutex_lock(&fn_performer_queue_lock);
	while (_performers != nil && i < [_performers count]) {
		FNPerformer *performer = [_performers objectAtIndex:i];

		if (!performer->_isBlock && performer->_target == target) {
			[_performers removeObjectAtIndex:i];
			continue;
		}
		i++;
	}
	pthread_mutex_unlock(&fn_performer_queue_lock);
}

/* THE SENDING, AND IT TAKES THE DUE ONES OUT FIRST so that a performer scheduling another performer cannot loop
 * this call forever — the new request belongs to the NEXT pass, which is what "at the start of the next run loop
 * iteration" means for it. */
- (void)fnRunPerformersInMode:(NSString *)mode
{
	NSMutableArray *due = [NSMutableArray array];
	NSUInteger i, j;

	if (_performers == nil) {
		return;
	}
	pthread_mutex_lock(&fn_performer_queue_lock);
	i = 0;
	while (i < [_performers count]) {
		FNPerformer *performer = [_performers objectAtIndex:i];

		if (fn_performer_modes_allow(performer, mode)) {
			[due addObject:performer];
			[_performers removeObjectAtIndex:i];
			continue;
		}
		i++;
	}
	pthread_mutex_unlock(&fn_performer_queue_lock);
	/* "MESSAGES WITH A LOWER ORDER VALUE ARE SENT BEFORE MESSAGES WITH A HIGHER ORDER VALUE" — and an insertion
	 * sort is STABLE, so two performers with the same order keep the order they were scheduled in.
	 *
	 * `key` IS RETAINED FOR THE DURATION, WHICH IS NOT OPTIONAL UNDER MRC: `[due objectAtIndex:i]` is a BORROWED
	 * reference, and the first `-replaceObjectAtIndex:` below releases whatever sat in index i — which for the
	 * first swap IS `key`. Without the retain the sort reads freed memory (measured: SIGSEGV inside -objc_retain
	 * the first time two performers with different orders were scheduled). The sibling sort in
	 * NSNotificationQueue.m had the same shape and was fixed with it. */
	for (i = 1; i < [due count]; i++) {
		FNPerformer *key = [[due objectAtIndex:i] retain];

		j = i;
		while (j > 0 && ((FNPerformer *)[due objectAtIndex:j - 1])->_order > key->_order) {
			[due replaceObjectAtIndex:j withObject:[due objectAtIndex:j - 1]];
			j--;
		}
		[due replaceObjectAtIndex:j withObject:key];
		[key release];
	}
	for (i = 0; i < [due count]; i++) {
		FNPerformer *performer = [due objectAtIndex:i];

		if (performer->_isBlock) {
			fn_invoke_block(performer->_block);
		} else if (performer->_target != nil) {
			[performer->_target performSelector:performer->_selector
						 withObject:performer->_argument];
		}
	}
}

- (BOOL)fnHasPendingPerformerForMode:(NSString *)mode
{
	NSUInteger i;
	BOOL pending = NO;

	pthread_mutex_lock(&fn_performer_queue_lock);
	for (i = 0; _performers != nil && i < [_performers count]; i++) {
		if (fn_performer_modes_allow([_performers objectAtIndex:i], mode)) {
			pending = YES;
			break;
		}
	}
	pthread_mutex_unlock(&fn_performer_queue_lock);
	return pending;
}

- (CFRunLoopRef)fn_cfLoop
{
	return _cfLoop;
}

- (CFRunLoopRef)getCFRunLoop
{
	/* **THE ANSWER THIS CLASS USED TO REFUSE.** It raised because the loop was not CoreFoundation's and handing
	 * back CF's own current loop would have made a caller wait on the wrong one. There is only one loop now. */
	return _cfLoop;
}

@end

/* ==================================================================================================================
 * NSDelayedPerforming — the four doors, and the registry that makes the cancels possible.
 *
 * A DELAYED PERFORM IS A ONE-SHOT TIMER, so the request is an object the timer can address and the registry can
 * find. The registry is what `+cancelPreviousPerformRequestsWithTarget:` searches, and it holds the request (and
 * through it the target and the argument) until the message is sent or cancelled — Apple's ownership rule, and the
 * reason a target cannot be collected out from under a pending perform.
 *
 * THE THREE-WAY MATCH IS DELIBERATE. The one-argument cancel names only a target and cancels everything queued for
 * it; the three-argument cancel names target, selector and argument, because two requests can share a selector (two
 * different arguments is the ordinary case) and cancelling one must not cancel both.
 * ================================================================================================================ */

@interface FNDelayedPerform : NSObject
{
	id _target;
	SEL _selector;
	id _argument;
	NSTimer *_timer;
}
- (instancetype)initWithTarget:(id)target selector:(SEL)aSelector argument:(nullable id)anArgument;
- (void)scheduleInModes:(nullable NSArray *)modes delay:(NSTimeInterval)delay;
- (void)cancel;
- (BOOL)matchesTarget:(id)target selector:(SEL)aSelector argument:(nullable id)anArgument;
- (void)fire:(NSTimer *)timer;
@end

static pthread_mutex_t fn_delayed_registry_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableSet *fn_delayed_registry = nil;

static void fn_delayed_registry_add(FNDelayedPerform *request)
{
	pthread_mutex_lock(&fn_delayed_registry_lock);
	if (fn_delayed_registry == nil) {
		fn_delayed_registry = [[NSMutableSet alloc] init];
	}
	[fn_delayed_registry addObject:request];
	pthread_mutex_unlock(&fn_delayed_registry_lock);
}

static void fn_delayed_registry_remove(FNDelayedPerform *request)
{
	pthread_mutex_lock(&fn_delayed_registry_lock);
	[fn_delayed_registry removeObject:request];
	pthread_mutex_unlock(&fn_delayed_registry_lock);
}

/* A SNAPSHOT, because cancelling mutates the registry while it is being walked. The array retains each request, so
 * a cancel that removes the registry's reference cannot free one out from under this loop. */
static NSArray *fn_delayed_registry_snapshot(void)
{
	NSMutableArray *snapshot;

	pthread_mutex_lock(&fn_delayed_registry_lock);
	snapshot = [[NSMutableArray alloc] init];
	if (fn_delayed_registry != nil) {
		NSEnumerator *enumerator = [fn_delayed_registry objectEnumerator];
		id request;

		while ((request = [enumerator nextObject]) != nil) {
			[snapshot addObject:request];
		}
	}
	pthread_mutex_unlock(&fn_delayed_registry_lock);
	return [snapshot autorelease];
}

@implementation FNDelayedPerform

- (instancetype)initWithTarget:(id)target selector:(SEL)aSelector argument:(nullable id)anArgument
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_target = [target retain];
	_selector = aSelector;
	_argument = [anArgument retain];
	return self;
}

- (void)dealloc
{
	[_target release];
	[_argument release];
	[_timer release];
	[super dealloc];
}

/* THE REQUEST IS ADDED TO THE REGISTRY BEFORE THE TIMER IS ARMED, so a cancel from another thread can see it from
 * the moment it can fire. `_timer` is kept so the cancel can invalidate it; the run loop owns its own reference. */
- (void)scheduleInModes:(nullable NSArray *)modes delay:(NSTimeInterval)delay
{
	NSRunLoop *loop = [NSRunLoop currentRunLoop];
	NSTimer *timer;
	NSUInteger i;

	if (_timer != nil) {
		return;		/* already scheduled: a second schedule would arm a second timer for one request */
	}
	fn_delayed_registry_add(self);
	timer = [NSTimer timerWithTimeInterval:delay target:self selector:@selector(fire:) userInfo:nil repeats:NO];
	_timer = [timer retain];
	if (modes == nil || [modes count] == 0) {
		[loop addTimer:timer forMode:NSDefaultRunLoopMode];
		return;
	}
	for (i = 0; i < [modes count]; i++) {
		[loop addTimer:timer forMode:[modes objectAtIndex:i]];
	}
}

- (void)fire:(NSTimer *)timer
{
	(void)timer;
	/* RETAINED ACROSS THE SEND: removing the registry's reference below can be the last one, and the message has
	 * not been sent yet. The loop's timer also releases its target when the timer dies. */
	[self retain];
	fn_delayed_registry_remove(self);
	[_timer release];
	_timer = nil;
	[_target performSelector:_selector withObject:_argument];
	[self release];
}

- (void)cancel
{
	if (_timer != nil) {
		[_timer invalidate];
		[_timer release];
		_timer = nil;
	}
	fn_delayed_registry_remove(self);
}

- (BOOL)matchesTarget:(id)target selector:(SEL)aSelector argument:(nullable id)anArgument
{
	if (_target != target) {
		return NO;
	}
	if (aSelector != NULL && _selector != aSelector) {
		return NO;
	}
	if (aSelector != NULL && _argument != anArgument) {
		return NO;
	}
	return YES;
}

@end

@implementation NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector
	     withObject:(nullable id)anArgument
	     afterDelay:(NSTimeInterval)delay
		inModes:(NSArray *)modes
{
	FNDelayedPerform *request;

	if (aSelector == NULL) {
		return;
	}
	request = [[FNDelayedPerform alloc] initWithTarget:self selector:aSelector argument:anArgument];
	[request scheduleInModes:modes delay:delay];
	[request release];		/* the registry holds it until it fires or is cancelled */
}

- (void)performSelector:(SEL)aSelector
	     withObject:(nullable id)anArgument
	     afterDelay:(NSTimeInterval)delay
{
	[self performSelector:aSelector withObject:anArgument afterDelay:delay inModes:nil];
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget
				       selector:(SEL)aSelector
					 object:(nullable id)anArgument
{
	NSArray *snapshot = fn_delayed_registry_snapshot();
	NSUInteger i;

	for (i = 0; i < [snapshot count]; i++) {
		FNDelayedPerform *request = [snapshot objectAtIndex:i];

		if ([request matchesTarget:aTarget selector:aSelector argument:anArgument]) {
			[request cancel];
		}
	}
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget
{
	[self cancelPreviousPerformRequestsWithTarget:aTarget selector:NULL object:nil];
}

@end
