/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSRunLoop — the loop that waits, and the place timers, sources, performers and notification posts are kept.
 * F13.18 (§62.62 added the performers and the visitors the queue needed).
 *
 * WHAT IT RUNS: TIMERS (§12.3's W6), SOURCES (§43), PERFORMERS (§62.62) and the suspended notifications a
 * thread's NSNotificationQueue holds (§62.61). A loop with ports, observers and a CoreFoundation bridge is a
 * different design at each of those words, and what is not here is named at the foot of this comment rather
 * than left to be discovered.
 *
 * THE MODES ARE NAMES, NOT MACHINES: an entry is added for a mode, and a loop running that mode carries it.
 * `NSDefaultRunLoopMode` and `NSRunLoopCommonModes` are the two Cocoa names, and an entry added for the COMMON
 * modes is carried by every mode — which is the whole of what "common" means here, and it is now ONE function
 * (§62.62, FNRunLoopModes.h) rather than a rule each kind of entry spelled for itself.
 *
 * HOW IT WAITS: IT DOES NOT. The waiting is CoreFoundation's, which is the design this header now documents — a
 * timer is a `CFRunLoopTimer`, an fd source is a `CFRunLoopSource` fed by a `dispatch_source`, a performer is a
 * signalled source, and the loop's wait is `CFRunLoopRunInMode`. That is one mechanism for all four, and it is the
 * same one that services the main dispatch queue, so `dispatch_async(dispatch_get_main_queue(), ^{…})` runs on the
 * next pass of an application's loop. `-getCFRunLoop` answers the loop it always refused to fake:
 * `tests/runloop_cf.m` holds that identity, a timer's delivery, a signalled source, an fd source and the dispatch
 * main queue to their contracts, and `libagora-app` proves a timer fires inside `-[NSApplication run]`.
 *
 * WHAT IS STILL NOT HERE, named rather than left to be discovered: run-loop OBSERVERS as a public API
 * (`-addObserver:forKeyPath:…` and the activity notifications) — the loop installs its own observer internally, for
 * the notification queue's phases — `-performSelector:target:argument:order:modes:` on the NSObject side, and
 * `NSRunLoopCommonModes` as a mode SET rather than the single name it is treated as.
 */

#ifndef FOUNDATION_NSRUNLOOP_H
#define FOUNDATION_NSRUNLOOP_H

#import <CoreFoundation/CFRunLoop.h>	/* CFRunLoopRef, the answer -getCFRunLoop refuses to fake */
#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>	/* NSTimeInterval, which the delayed-perform category names */

@class NSDate;
@class NSTimer;
@class NSString;
@class NSThread;

NS_ASSUME_NONNULL_BEGIN

/* COCOA'S TWO NAMES, and their values are the names — a caller compares against the constant. */
extern NSString *const NSDefaultRunLoopMode;
extern NSString *const NSRunLoopCommonModes;

/* Apple's modern spelling for a mode, DECLARED because this class's own source door takes one (the older
 * methods below say `NSString *` and mean the same type). */
typedef NSString * NSRunLoopMode;

/* FORWARD-DECLARED: the ivars and the performer doors only need the names, and the implementation imports
 * NSArray.h. A port is forward-declared for the same reason AND because the dependency runs the other way:
 * NSPort.h imports THIS header, so importing it back would be a cycle. */
@class NSArray;
@class NSMutableArray;
@class NSPort;
@class NSTimer;
@class NSRunLoop;

NS_SWIFT_NAME(RunLoop)
NS_CLASS_AVAILABLE_MAC(10_5)
@interface NSRunLoop : NSObject
{
	/* **THE LOOP IS CORE FOUNDATION'S, AND THAT IS THE WHOLE DESIGN.** This class used to keep its own
	 * arrays of timers, fd sources and performers and wait in `select(2)`; it is now a façade over
	 * `CFRunLoop`, so a timer's date, an fd source's readiness, the loop's own wait and the main dispatch
	 * queue are one mechanism rather than four. `_cfLoop` is `CFRunLoopGetCurrent()` at init, retained.
	 *
	 * `_timers` is ONLY A LIFETIME HOLDER: CF's run loop retains a timer for as long as it is scheduled, but an
	 * `NSTimer` is an Objective-C object whose dealloc releases the `CFRunLoopTimer` it owns, so this array is
	 * what keeps a scheduled timer's NSTimer alive across a caller that let go of it. Invalidated timers are
	 * pruned at the top of every pass. */
	CFRunLoopRef _cfLoop;		/* RETAINED */
	NSMutableArray *_timers;	/* NSTimer, scheduled anywhere; pruned when invalid */
	NSString *_currentMode;		/* RETAINED: the mode the last pass ran in */
	BOOL _running;
	NSMutableArray *_sources;	/* FNRunLoopSource, created on first use */
	NSMutableArray *_performers;	/* FNPerformer, created on first use (§62.62) */
	/* AND THE TWO THINGS THIS CLASS NOW CONTRIBUTES TO THE LOOP RATHER THAN IMPLEMENTING: the source performers
	 * are delivered through, and the observer that gives NSNotificationQueue its two phases. Both live in
	 * `kCFRunLoopCommonModes`, so they are live in every mode the loop runs. */
	CFRunLoopSourceRef _performerSource;	/* RETAINED */
	CFRunLoopObserverRef _phaseObserver;	/* RETAINED */
	unsigned long _workCount;	/* bumped by every timer, source and performer this loop delivers */
}

+ (NSRunLoop *)currentRunLoop;
+ (NSRunLoop *)mainRunLoop NS_AVAILABLE_MAC(10_5);

/*
 * INTERNAL, AND IT IS WHAT MAKES `-performSelector:onThread:…` POSSIBLE. A run loop is per-thread and its ownership
 * is a pthread-specific, which one thread cannot read for another; so a loop also records itself in its OWNER
 * THREAD's `-threadDictionary`, which every thread can read. The answer is nil when that thread has never asked for a
 * run loop — which is the condition Apple raises for, because there is no loop to queue a request on.
 */
+ (nullable NSRunLoop *)fn_runLoopForThread:(NSThread *)thread;

- (NSString *)currentMode;

- (void)addTimer:(NSTimer *)timer forMode:(NSString *)mode;

/*
 * APPLE'S PORT DOOR, AND IT IS CURRENT API RATHER THAN A DEPRECATED ONE: the class overview names port
 * objects as run-loop input sources beside mouse and keyboard events, and neither of these two methods
 * carries a deprecation. THEY WERE UNIMPLEMENTABLE UNTIL §43 — a door that takes a port has nothing to
 * take while no port class exists — and now they are the forward they were always meant to be: the port
 * is told to schedule ITSELF, and a concrete port is what decides how.
 *
 * The descriptor door above (`-addSourceForFileDescriptor:…`, W6a) is still what a caller without a
 * port wants, and it is OURS; these two are Apple's shape over the same loop.
 */
- (void)addPort:(NSPort *)aPort forMode:(NSRunLoopMode)mode;
- (void)removePort:(NSPort *)aPort forMode:(NSRunLoopMode)mode;

/* ONE PASS: fire what is due, then answer whether the loop should keep going. The limit is NULLABLE
 * because a caller may want the pass without a deadline, which is exactly what -run does. */
- (BOOL)runMode:(NSString *)mode beforeDate:(nullable NSDate *)limit;

/* **A PASS THAT MAY WAIT, AND RETURNS AS SOON AS SOMETHING WAS DELIVERED — which is the shape an application's frame
 * loop wants and no Apple door provides.** `-runMode:beforeDate:` is one pass with NO wait (documented as such, and
 * what a frame that has already decided how long to sleep uses); `-runUntilDate:` runs until a deadline even when
 * work arrives. This is CoreFoundation's `CFRunLoopRunInMode` with `returnAfterSourceHandled`, plus this class's own
 * work counter: a TIMER callout does not make CF return early on its own, and a frame that waited out its whole
 * slice after a timer fired would paint a frame late. YES when work was delivered, NO when the wait expired.
 *
 * INTERNAL: it exists so `NSApplication` can make the compositor's descriptor one source among its timers instead of
 * polling it with a deadline. */
- (BOOL)fnRunMode:(NSString *)mode forSeconds:(double)seconds returnAfterWork:(BOOL)stopAfterWork;
- (void)runUntilDate:(nullable NSDate *)limit;
- (void)run;

/*
 * THE SOURCE DOOR, AND IT IS OURS. A run loop wakes for two kinds of thing: a TIMER, which names a date,
 * and a SOURCE, which names a FILE DESCRIPTOR and says "tell me when it is ready". This class shipped
 * with timers only (§12.3's W6 named the gap), and the door is here rather than private because Apple's
 * own source door is NSPort-shaped — `-addPort:forMode:` — while `NSPort`'s message half went with
 * `NSPortMessage` and `NSPortDelegate`, both APPLE-DEPRECATED and struck by §11.5. A port scheduled here
 * is therefore a descriptor with an object wrapped round it, and the seam is the smaller honest thing.
 *
 * THE CONTRACT, FOUR PARTS:
 *   * `selector` must take NO ARGUMENTS. A source exists to say "ready now"; a caller that wants the
 *     descriptor already has it.
 *   * `target` is held WEAKLY. A run loop lives as long as its thread, so a retained target would be a
 *     leak with no owner to fix it, and a target that has gone away is DROPPED, not called (the rule
 *     NSNotificationCenter already follows).
 *   * `readable` picks which readiness is watched: YES for "there is something to read", NO for "there is
 *     room to write".
 *   * A source OUTLIVES the pass that notices it: the consumer removes it, which is what makes a
 *     one-shot read one.
 */
- (void)addSourceForFileDescriptor:(int)fd
			      mode:(NSRunLoopMode)mode
			  readable:(BOOL)readable
			    target:(id)target
			  selector:(SEL)selector;

/* Every source this target registered, in every mode. */
- (void)removeSourceForTarget:(id)target;

/*
 * THE PERFORMERS (§62.62), Apple's five doors, and their contract is Apple's to state — read off the pages
 * rather than recalled, because two of the clauses are the kind a guess gets wrong:
 *
 *   * "This method sets up a timer to perform the aSelector message ... AT THE START OF THE NEXT RUN LOOP
 *     ITERATION", so a performer is a REQUEST the loop honours, not a call;
 *   * "messages with a LOWER order value are sent BEFORE messages with a higher order value" (so 0 runs first);
 *   * the receiver RETAINS the target and the argument until the message is sent — an ownership rule with teeth,
 *     and the reason this class holds both rather than borrowing them;
 *   * the message is sent only while the loop is running in one of the given `modes`, and otherwise waits.
 *
 * `-cancelPerformSelector:target:argument:` requires SELECTOR AND ARGUMENT to match as well as the target;
 * `-cancelPerformSelectorsWithTarget:` cancels by TARGET ALONE and "removes the perform requests for the object
 * from ALL modes".
 *
 * THE BLOCK FORMS are macOS 10.12+ and are the same request with a block instead of a selector. Apple's own page
 * for `-performBlock:` does NOT state which modes it uses; the resolution recorded on Apple's developer forum
 * ("performBlock: is equivalent to performInModes:block: with an array containing the default run loop mode") is
 * what this implements, and it is cited here because the alternative readings would differ observably.
 */
- (void)performSelector:(SEL)aSelector
		 target:(id)target
	       argument:(nullable id)arg
		  order:(NSUInteger)order
		  modes:(NSArray *)modes;
- (void)cancelPerformSelector:(SEL)aSelector target:(id)target argument:(nullable id)arg;
- (void)cancelPerformSelectorsWithTarget:(id)target;
- (void)performBlock:(void (^)(void))block;
- (void)performInModes:(NSArray *)modes block:(void (^)(void))block;


/* §63.203: THREE DOORS. `-acceptInputForMode:beforeDate:` is this loop's one turn spelled Apple's way;
 * `-limitDateForMode:` reports the next timer due in that mode (a stated reading: the earliest fire date
 * among the timers that mode would fire, or nil); `-configureAsServer` IS A NO-OP BY APPLE'S OWN
 * DOCUMENTATION — "This method does nothing" — so implementing it as one is faithful rather than lazy.
 * `-getCFRunLoop` IS DECLARED AND REFUSES: it returns the CFRunLoopRef behind the loop, and this loop is NOT
 * CF-backed (see the note above). Returning Core Foundation's own current loop would be a different loop with the
 * same name — a caller would add a source to one and wait on the other — so the door raises with that ground. */
- (BOOL)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;
- (nullable NSDate *)limitDateForMode:(NSRunLoopMode)mode;
- (void)configureAsServer NS_DEPRECATED_MAC(10_0, 10_5);
- (CFRunLoopRef)getCFRunLoop;
@end

/*
 * THE DELAYED PERFORM FAMILY (10.2), and it is declared HERE because a delayed perform IS a timer on a run loop:
 * Apple's NSRunLoop.h carries `NSObject (NSDelayedPerforming)` for exactly that reason. The four doors are the
 * `afterDelay:` pair and the two cancels; the threaded half lives in NSThread.h, which is also Apple's placement.
 *
 * THE CONTRACT, THREE PARTS, each of which the implementation had to honour rather than approximate:
 *   * the receiver is RETAINED with its argument until the message is sent (or cancelled);
 *   * the message is sent on the run loop in the given modes, and NOT at all if the loop never runs them;
 *   * cancelling matches the target alone for the one-argument form, and target, selector AND argument for the
 *     three-argument form — so cancelling one of two requests with the same selector needs the argument too.
 */
@interface NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector
	     withObject:(nullable id)anArgument
	     afterDelay:(NSTimeInterval)delay
		inModes:(NSArray *)modes;
- (void)performSelector:(SEL)aSelector
	     withObject:(nullable id)anArgument
	     afterDelay:(NSTimeInterval)delay;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget
				       selector:(SEL)aSelector
					 object:(nullable id)anArgument;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSRUNLOOP_H */
