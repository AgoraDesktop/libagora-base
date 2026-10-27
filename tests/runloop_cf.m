/*
 * runloop_cf — the run loop is Core Foundation's, and everything a loop is for arrives through it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHAT THIS HOLDS UP. `NSRunLoop` used to be its own implementation with its own `select(2)` wait, its own timer
 * array and its own source array, and `-getCFRunLoop` raised because Core Foundation's loop was a different loop.
 * It is now a façade over `CFRunLoop`, and this case is the contract of that change — each check names the door and
 * the property, so a failure says which half moved:
 *
 *   * THE LOOP IS THE ONE COREFOUNDATION NAMES. `-getCFRunLoop` answers `CFRunLoopGetCurrent()`, which is what makes
 *     a caller's own `CFRunLoopTimer`/`CFRunLoopSource`/`dispatch_async` land in the loop an application runs.
 *   * A TIMER FIRES, ON TIME, AND ONLY ONCE — one-shot, and repeating with a date that advances.
 *   * `-limitDateForMode:` answers the next fire date, and nil when the loop has none.
 *   * AN FD SOURCE FIRES when its descriptor is ready, on the loop's thread — the NSFileHandle reading contract.
 *   * A DELAYED PERFORM fires, which is a timer nobody calls a timer.
 *   * A PERFORMER SENT FROM ANOTHER THREAD ARRIVES, which is the wake path rather than a poll.
 *   * THE MODE RULE IS UNCHANGED: common-mode entries fire in the default mode, and an entry added for another mode
 *     waits for that mode.
 *   * AND THE ONE THIS WHOLE CHANGE IS FOR: `dispatch_async(dispatch_get_main_queue(), ^{…})` runs, because the
 *     pass that delivers a timer is the pass that services the main dispatch queue's port.
 */

#import <Foundation/Foundation.h>
#include <CoreFoundation/CFRunLoop.h>
#include <dispatch/dispatch.h>

#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

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

@interface Probe : NSObject
{
@public
	int timers;
	int repeats;
	int sources;
	int delayed;
	int performed;
}
- (void)onTimer:(NSTimer *)timer;
- (void)onRepeat:(NSTimer *)timer;
- (void)onSource;
- (void)onDelayed;
- (void)onPerformed;
@end

@implementation Probe

- (void)onTimer:(NSTimer *)timer
{
	(void)timer;
	timers++;
}

- (void)onRepeat:(NSTimer *)timer
{
	(void)timer;
	repeats++;
}

- (void)onSource
{
	sources++;
}

- (void)onDelayed
{
	delayed++;
}

- (void)onPerformed
{
	performed++;
}

@end

/* A SPINNER WITH A BOUND, because every wait in this file is "until it happens, or fail in a second": a test that
 * waits a fixed time is a test that fails on a loaded machine, and one that waits forever is a test that hangs it. */
/* **HOW MANY DESCRIPTORS THIS PROCESS HOLDS.** A source is two objects (a CF source and a dispatch source), and the
 * failure this counts is the one a test can see from outside: a source that is removed must give its watching back,
 * or a program that opens and closes sources leaks a descriptor per cycle. The dispatch source's own fd is
 * libdispatch's business; what is counted here is the caller's. */
static int count_open_fds(void)
{
	DIR *dir = opendir("/proc/self/fd");
	struct dirent *entry;
	int count = 0;

	if (dir == NULL) {
		return -1;
	}
	while ((entry = readdir(dir)) != NULL) {
		if (entry->d_name[0] != '.') {
			count++;
		}
	}
	closedir(dir);
	return count;
}

static void pump(NSRunLoop *loop, double seconds)
{
	[loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void pump_until(NSRunLoop *loop, int *flag, double limit)
{
	double deadline = [[NSDate date] timeIntervalSinceReferenceDate] + limit;

	while (*flag == 0 && [[NSDate date] timeIntervalSinceReferenceDate] < deadline) {
		pump(loop, 0.02);
	}
}

/* **PUMPED IN A NAMED MODE, AND THAT IS DIFFERENT FROM PUMPING THE DEFAULT ONE.** A mode is what the caller asks the
 * loop to run, so a check about a mode has to run THAT mode — `-runUntilDate:` would run the default one and never
 * reach the timer the check is about. */
static void pump_mode_until(NSRunLoop *loop, NSString *mode, int *flag, double limit)
{
	double deadline = [[NSDate date] timeIntervalSinceReferenceDate] + limit;

	while (*flag == 0 && [[NSDate date] timeIntervalSinceReferenceDate] < deadline) {
		[loop runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	}
}

/* A PERFORMER FROM ANOTHER THREAD: this is `-performSelectorOnMainThread:`'s real use, and the path that used to
 * deadlock because the main loop never looked at its queue. */
@interface Sender : NSObject
{
@public
	Probe *probe;
}
@end

@implementation Sender
- (void)run:(id)ignored
{
	(void)ignored;
	usleep(20 * 1000);
	[probe performSelectorOnMainThread:@selector(onPerformed) withObject:nil waitUntilDone:NO];
}
@end

int main(void)
{
	NSRunLoop *loop = [NSRunLoop currentRunLoop];
	Probe *probe = [[Probe alloc] init];
	NSTimer *timer;
	NSTimer *repeat;
	__block int mainQueueRan = 0;
	int pipeFds[2];
	double started;

	printf("the run loop is Core Foundation's\n");

	/* 1. IDENTITY ------------------------------------------------------------------------------------- */
	check([loop getCFRunLoop] == CFRunLoopGetCurrent(),
	      "-getCFRunLoop answers Core Foundation's loop for this thread");

	/* 2. A ONE-SHOT TIMER FIRES, AND NOT BEFORE IT IS DUE --------------------------------------------- */
	timer = [NSTimer scheduledTimerWithTimeInterval:0.05
						 target:probe
					       selector:@selector(onTimer:)
					       userInfo:nil
						repeats:NO];
	pump(loop, 0.01);
	check(probe->timers == 0, "a timer 50 ms out has not fired after 10 ms");
	check([[loop limitDateForMode:NSDefaultRunLoopMode] timeIntervalSinceNow] > 0.0,
	      "-limitDateForMode answers the pending timer's date");
	pump_until(loop, &probe->timers, 1.0);
	check(probe->timers == 1, "the timer fired exactly once");
	check(![timer isValid], "a one-shot timer is invalid once it has fired");
	check([loop limitDateForMode:NSDefaultRunLoopMode] == nil,
	      "-limitDateForMode answers nil with no timer pending");

	/* 3. A REPEATING TIMER REPEATS, AND ITS DATE ADVANCES --------------------------------------------- */
	repeat = [NSTimer scheduledTimerWithTimeInterval:0.02
						  target:probe
						selector:@selector(onRepeat:)
						userInfo:nil
						 repeats:YES];
	{
		NSDate *first = [[repeat fireDate] copy];

		pump_until(loop, &probe->repeats, 1.0);
		check(probe->repeats >= 1, "a repeating timer fires");
		check([[repeat fireDate] timeIntervalSinceDate:first] > 0.0,
		      "and its fire date has moved past the one it started with");
		[first release];
	}
	[repeat invalidate];
	{
		int seen = probe->repeats;

		pump(loop, 0.06);
		check(probe->repeats == seen, "an invalidated timer stops firing");
	}

	/* 4. AN FD SOURCE FIRES WHEN ITS DESCRIPTOR IS READY, ON THIS THREAD ----------------------------- */
	if (pipe(pipeFds) == 0) {
		[loop addSourceForFileDescriptor:pipeFds[0]
					    mode:NSDefaultRunLoopMode
					readable:YES
					  target:probe
					selector:@selector(onSource)];
		check(write(pipeFds[1], "x", 1) == 1, "a byte was written to the pipe");
		pump_until(loop, &probe->sources, 1.0);
		check(probe->sources >= 1, "the source's selector ran for the readable descriptor");
		{
			char byte;

			(void)read(pipeFds[0], &byte, 1);
		}
		[loop removeSourceForTarget:probe];
		check(write(pipeFds[1], "y", 1) == 1, "another byte was written after the source was removed");
		{
			int seen = probe->sources;

			pump(loop, 0.05);
			check(probe->sources == seen, "a removed source does not fire");
		}
		close(pipeFds[0]);
		close(pipeFds[1]);
	} else {
		check(0, "a pipe could be made");
	}

	/* 4b. AND A SOURCE GIVES ITS DESCRIPTOR BACK ------------------------------------------------------ */
	{
		int before = count_open_fds();
		int round;

		for (round = 0; round < 20; round++) {
			int pair[2];

			if (pipe(pair) != 0) {
				break;
			}
			[loop addSourceForFileDescriptor:pair[0]
						    mode:NSDefaultRunLoopMode
						readable:YES
						  target:probe
						selector:@selector(onSource)];
			(void)!write(pair[1], "z", 1);
			pump(loop, 0.005);
			{
				char byte;

				(void)read(pair[0], &byte, 1);
			}
			[loop removeSourceForTarget:probe];
			close(pair[0]);
			close(pair[1]);
		}
		check(count_open_fds() == before, "twenty add/remove cycles left no descriptor behind");
	}

	/* 5. A DELAYED PERFORM FIRES --------------------------------------------------------------------- */
	[probe performSelector:@selector(onDelayed) withObject:nil afterDelay:0.03];
	pump_until(loop, &probe->delayed, 1.0);
	check(probe->delayed == 1, "-performSelector:withObject:afterDelay: ran once");

	/* 6. A PERFORMER FROM ANOTHER THREAD ARRIVES ----------------------------------------------------- */
	{
		Sender *sender = [[Sender alloc] init];

		sender->probe = probe;
		[NSThread detachNewThreadSelector:@selector(run:) toTarget:sender withObject:nil];
		pump_until(loop, &probe->performed, 2.0);
		check(probe->performed == 1,
		      "-performSelectorOnMainThread from a worker thread ran on this loop");
		[sender release];
	}

	/* 7. THE MODE RULE ------------------------------------------------------------------------------- */
	{
		Probe *modeProbe = [[Probe alloc] init];
		NSTimer *common = [NSTimer timerWithTimeInterval:0.0
							  target:modeProbe
							selector:@selector(onTimer:)
							userInfo:nil
							 repeats:NO];
		NSTimer *other = [NSTimer timerWithTimeInterval:0.0
							 target:modeProbe
						       selector:@selector(onRepeat:)
						       userInfo:nil
							repeats:NO];

		[loop addTimer:common forMode:NSRunLoopCommonModes];
		[loop addTimer:other forMode:@"AgTestRunLoopMode"];
		/* **PUMPED, BECAUSE A ZERO-SECOND PASS IS A POLL AND A POLL CAN MISS.** `-runMode:beforeDate:` runs
		 * `CFRunLoopRunInMode(mode, 0.0, true)`, and in this tree's CFRunLoop a zero duration sets `termTSR = 0`,
		 * which makes the pass a poll: the wait set is serviced with a zero timeout (`poll` in `__CFRunLoopRun`),
		 * the run ends `TimedOut` when nothing is ready, and TIMERS ARE DONE ONLY FROM THE TIMER-PORT BRANCH. So a
		 * timer added microseconds earlier — a 0.0-interval one especially — can still be pending when that poll
		 * returns, and the pass ends without firing it. That is what reddened the x86-64 clang-19 leg of the
		 * "pointer types" workflow on this one check while the other two legs passed, and why a single pass is not
		 * something this file can assert on.
		 *
		 * THE SUBJECT HERE IS THE MODE RULE, and pumping does not weaken it: the common entry must fire in the
		 * default mode, the named entry must NOT fire there, and it must fire when the loop runs its own mode — no
		 * number of extra passes in a mode can make another mode's timer fire in it. "One pass" has its own
		 * assertion below, where a pass is given a five-second deadline and must return at once. */
		pump_mode_until(loop, NSDefaultRunLoopMode, &modeProbe->timers, 0.5);
		check(modeProbe->timers == 1, "a common-mode timer fires in the default mode");
		check(modeProbe->repeats == 0, "a timer added for another mode does not");
		pump_mode_until(loop, @"AgTestRunLoopMode", &modeProbe->repeats, 0.5);
		check(modeProbe->repeats == 1, "and it fires when the loop runs its own mode");
		[modeProbe release];
	}

	/* 8. A ZERO-SECOND PASS IS A PASS, AND DOES NOT WAIT ----------------------------------------------- */
	started = [[NSDate date] timeIntervalSinceReferenceDate];
	[loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]];
	check([[NSDate date] timeIntervalSinceReferenceDate] - started < 0.2,
	      "-runMode:beforeDate: is one pass and does not wait out its deadline");

	/* 9. THE MAIN DISPATCH QUEUE, WHICH IS WHAT THE CHANGE IS FOR ------------------------------------- */
	dispatch_async(dispatch_get_main_queue(), ^{
		mainQueueRan = 1;
	});
	pump_until(loop, &mainQueueRan, 2.0);
	check(mainQueueRan == 1, "dispatch_async(dispatch_get_main_queue(), ^{...}) ran on the loop");

	/* 10. A CF TIMER ADDED BY THE CALLER LANDS IN THE SAME LOOP --------------------------------------- */
	{
		__block int cfFired = 0;
		CFRunLoopTimerRef cfTimer = CFRunLoopTimerCreateWithHandler(NULL,
									   CFAbsoluteTimeGetCurrent() + 0.01,
									   0, 0, 0, ^(CFRunLoopTimerRef t) {
			(void)t;
			cfFired = 1;
		});

		CFRunLoopAddTimer([loop getCFRunLoop], cfTimer, kCFRunLoopDefaultMode);
		pump_until(loop, &cfFired, 2.0);
		check(cfFired == 1, "a CFRunLoopTimer the caller made fired in this loop");
		CFRelease(cfTimer);
	}

	/* 11. THE THREE VIEWS OF ONE LOOP ARE ONE LOOP ---------------------------------------------------- */
	check([NSRunLoop currentRunLoop] == loop, "+currentRunLoop is stable");
	check([NSRunLoop mainRunLoop] == loop, "+mainRunLoop is this loop on the main thread");
	check([NSRunLoop fn_runLoopForThread:[NSThread mainThread]] == loop,
	      "+fn_runLoopForThread:mainThread answers it too");

	[probe release];
	printf("%s\n", g_fail ? "FAILURES" : "all checks passed");
	return g_fail ? 1 : 0;
}
