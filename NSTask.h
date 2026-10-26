/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSTask — A SUBPROCESS. docs/design/foundation-plan.md W6d and §45.
 *
 * IT IS THE ONE CLASS IN THIS LIBRARY THAT OWNS A PROCESS, so three things about it are unlike anything
 * else here:
 *
 *   * IT RE-EXECS, so what it needs from the system is `fork(2)` and `execve(2)` — which this kernel has,
 *     and which every other class in this unit only reads through a descriptor.
 *   * IT NEEDS A SECOND THREAD, and that is not an implementation detail: Apple's contract for
 *     `-terminationHandler` and `NSTaskDidTerminateNotification` is that both happen WHEN THE TASK ENDS,
 *     with nobody calling `-waitUntilExit`. So a launched task starts a REAPER thread that `waitpid(2)`s,
 *     records the status, posts the notification and runs the handler. `-waitUntilExit` then waits on a
 *     condition for that thread's answer rather than reaping a second time — one reaper, one status, and
 *     a status that survives being read twice.
 *   * ONE INSTANCE RUNS ONCE. Apple: *"You can only run the subprocess once per instance."* A second
 *     `-launchAndReturnError:` answers NO with an error rather than forking twice.
 *
 * THE DEPRECATED HALF IS STRUCK, AND IT IS THE HALF EVERYOONE REMEMBERS. §11.5 removes four names, and the
 * live spelling of each is beside it here: `+launchedTaskWithLaunchPath:arguments:` (→ the
 * `…WithExecutableURL:` form), `-launch` (→ `-launchAndReturnError:`), `-launchPath`/`-setLaunchPath:`
 * (→ `-executableURL`), and `-currentDirectoryPath`/`-setCurrentDirectoryPath:` (→ `-currentDirectoryURL`).
 * The probe's inventory names each one with that reason.
 *
 * TWO CONTRACTS ARE APPLE'S OWN SENTENCES AND ARE PINNED RATHER THAN PARAPHRASED: passing `nil` arguments
 * to the static launcher **raises NSInvalidArgumentException**, and the child's standard input, output and
 * error are set as an `NSPipe` (the other end becomes the caller's) or an `NSFileHandle`.
 *
 * AND TWO THINGS ARE OURS, STATED HERE BECAUSE APPLE PUBLISHES NEITHER:
 *
 *   * `-terminationStatus` ANSWERS `WEXITSTATUS` WHEN THE TASK EXITED and the SIGNAL NUMBER WHEN IT DID
 *     NOT. Apple's page says only "the exit status the executable returns", and `-terminationReason` is
 *     the API that tells the two apart, so the value for the signal case has to be chosen by somebody.
 *   * `-interrupt` and `-terminate` SIGNAL THE CHILD'S PROCESS GROUP, which is how Apple's "and all of its
 *     subtasks" is honoured: the child is put in a new group (`setpgid(0, 0)`) before it execs, and the
 *     signal goes to `-pid`. A child that spawns children of its own therefore dies with them.
 *
 * NOT DECLARED, NAMED: `launchRequirement` and `launchRequirementData` are code-signing requirement
 * objects, and this system has no code-signing requirement subsystem to express one with — a refusal
 * rather than a stub.
 */

#ifndef FOUNDATION_NSTASK_H
#define FOUNDATION_NSTASK_H

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>	/* NSQualityOfService */
#include <sys/types.h>

@class NSArray;
@class FNCondition;	/* the reaper's handshake with -waitUntilExit — first-party since §63.170 */
@class NSDictionary;
@class NSError;
@class NSFileHandle;
@class NSString;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

/* Posted when the task has stopped execution, with the task as the object. Posted by the REAPER, so it
 * arrives whether or not anybody called `-waitUntilExit`. */
extern NSString *const NSTaskDidTerminateNotification;

/* THE CASE NAMES ARE APPLE'S AND THE VALUES ARE OURS, which is this tree's rule for an enum nobody
 * publishes numbers for (§11.6.1 D2). They are the conventional pair: an exit, or a signal. */
typedef enum {
	NSTaskTerminationReasonExit = 1,
	NSTaskTerminationReasonUncaughtSignal = 2
} NSTaskTerminationReason;

NS_SWIFT_NAME(Process)
@interface NSTask : NSObject
{
	NSURL *_executableURL;
	NSArray *_arguments;
	NSDictionary *_environment;
	NSURL *_currentDirectoryURL;
	id _standardInput;		/* an NSPipe or an NSFileHandle, per Apple */
	id _standardOutput;
	id _standardError;
	NSQualityOfService _qualityOfService;
	void (^_terminationHandler)(NSTask *);	/* COPIED */
	/* THE PROCESS STATE, AND THE HANDSHAKE THE REAPER AND -waitUntilExit MAKE OVER IT. */
	pid_t _pid;
	BOOL _launched;
	BOOL _exited;
	int _status;			/* the RAW wait(2) status */
	FNCondition *_condition;
	BOOL _reaperStarted;
	/* **THE PSEUDO-TERMINAL, WHICH APPLE'S CLASS CANNOT EXPRESS AND A TERMINAL CANNOT DO WITHOUT.** `_ptyMaster`
	 * is the end this process reads and writes, `-1` until a launch that asked for one; `_ptyHandle` wraps it for
	 * the caller and is retained here, because the descriptor is the task's to close. The size is stored so that a
	 * caller may set it BEFORE the launch — the child's first `TIOCGWINSZ` has to be right, since that is what a
	 * shell reads for `COLUMNS`/`LINES`. */
	BOOL _usesPseudoTerminal;
	int _ptyMaster;
	NSFileHandle *_ptyHandle;
	unsigned short _ptyRows;
	unsigned short _ptyColumns;
}

/* --- creating and initializing ------------------------------------------- */

/* The environment of the current process, and nothing launched: Apple's `-init`. */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/* "Creates and runs a task with a specified executable and arguments." RAISES NSInvalidArgumentException
 * when `arguments` is nil — Apple's own sentence — and answers nil with an error when the launch fails. */
+ (nullable instancetype)launchedTaskWithExecutableURL:(NSURL *)url
					     arguments:(NSArray *)arguments
						 error:(NSError **)errorPtr
				      terminationHandler:(nullable void (^)(NSTask *task))terminationHandler;

/* --- running and stopping ------------------------------------------------ */

/* Runs the process once. A second call on the same instance answers NO with an error. */
- (BOOL)launchAndReturnError:(NSError **)errorPtr;

/* Each signals the child's PROCESS GROUP (see the header's note). suspend/resume answer whether the
 * signal was delivered, which is Apple's BOOL. */
- (void)interrupt;
- (BOOL)suspend;
- (BOOL)resume;
- (void)terminate;

/* Blocks until the task is finished. A no-op on a task that was never launched. */
- (void)waitUntilExit;

/* --- querying the process state ------------------------------------------ */

- (BOOL)isRunning;
- (int)processIdentifier;

/* `WEXITSTATUS` when the task exited; the SIGNAL NUMBER when it did not — see the header's note. */
- (int)terminationStatus;
- (NSTaskTerminationReason)terminationReason NS_AVAILABLE_MAC(10_6);

/* --- configuring, BEFORE the launch -------------------------------------- */

- (nullable NSURL *)executableURL;
- (void)setExecutableURL:(NSURL *)url;

/* The arguments, WITHOUT the executable's own name: `argv[0]` is built from the executable. */
- (nullable NSArray *)arguments;
- (void)setArguments:(NSArray *)arguments;

/* nil means "inherit this process's environment", which is Apple's default. */
- (nullable NSDictionary *)environment;
- (void)setEnvironment:(NSDictionary *)environment;

- (nullable NSURL *)currentDirectoryURL;
- (void)setCurrentDirectoryURL:(NSURL *)url;

- (nullable id)standardInput;
- (void)setStandardInput:(nullable id)object;
- (nullable id)standardOutput;
- (void)setStandardOutput:(nullable id)object;
- (nullable id)standardError;
- (void)setStandardError:(nullable id)object;

/* --- the pseudo-terminal (OURS: Apple's NSTask cannot make one) ------------------------------------ */

/* **A TERMINAL IS NOT THREE PIPES, AND THIS CLASS COULD ONLY MAKE THREE PIPES.** With this set,
 * `-launchAndReturnError:` creates a pty pair, puts the child in a NEW SESSION with the slave as its CONTROLLING
 * TERMINAL (`setsid(2)`, then `TIOCSCTTY`), and gives it the slave on stdin, stdout and stderr. That is what makes
 * the line discipline work rather than a pipe's byte stream: `^C` and `^Z` become signals to the child's foreground
 * process group, `tcsetpgrp` has a group to name, `isatty(3)` is true, and `TIOCSWINSZ` delivers `SIGWINCH`.
 *
 * THE THREE STDIO SLOTS ARE IGNORED IN THIS MODE, which is stated rather than discovered: one terminal is one
 * device, and three halves sharing one line discipline cannot be told apart. The child's group is the session's
 * (so `-interrupt` and `-terminate`, which signal the group, still reach the subtree).
 *
 * A PTY'S OWNER IS THE TASK. `-pseudoterminalHandle` is the master, retained by the task and closed when the task
 * is deallocated — so a reader that wants EOF keeps the task alive, the same rule Apple's class has for a pipe. The
 * handle is nil before the launch, and for a task that does not use one. */
@property BOOL usesPseudoTerminal;

/* The master end, or nil. Retained by the task; the caller may set `-readabilityHandler:` on it, which is how a
 * terminal reads what the child wrote (the run loop wakes on it, because a pty is a character device and not a
 * regular file). */
- (nullable NSFileHandle *)pseudoterminalHandle;

/* **THE WINDOW SIZE, A TERMINAL'S ONLY OTHER CHANNEL TO ITS CHILD.** Before the launch the size is stored and
 * applied to the pty, so the child's FIRST `TIOCGWINSZ` is right; after the launch it is written to the terminal,
 * which is what makes the kernel send `SIGWINCH` to the child's foreground group. Answers NO for a zero dimension:
 * a pty with no size is one whose programs believe they have no columns, which is worse than a default. The
 * default is 24 rows by 80 columns. */
- (BOOL)setPseudoterminalRows:(unsigned short)rows columns:(unsigned short)columns;
- (unsigned short)pseudoterminalRows;
- (unsigned short)pseudoterminalColumns;

/* CARRIED AND REPORTED, NOT APPLIED: there is no scheduler class to hand a quality of service to, so the
 * value is stored and answered and the launch does not consult it. Stated because a caller could
 * otherwise believe it had asked for something. */
- (NSQualityOfService)qualityOfService NS_AVAILABLE_MAC(10_10);
- (void)setQualityOfService:(NSQualityOfService)qualityOfService NS_AVAILABLE_MAC(10_10);

/* COPIED, and called by the REAPER when the task ends. */
- (nullable void (^)(NSTask *task))terminationHandler;
- (void)setTerminationHandler:(nullable void (^)(NSTask *task))handler;

/* §63.210: THE PRE-10.6 SPELLINGS — one mechanism: each legacy door is its modern counterpart with the path
 * spelled as a path rather than a URL. `launchRequirementData` is NOT here: it names the code-signing
 * requirement a task should be verified against, and this system has no signing substrate to consult. */
- (void)launch;
+ (nullable instancetype)launchedTaskWithLaunchPath:(NSString *)path
					 arguments:(nullable NSArray *)arguments;
@property (nullable, copy) NSString *launchPath;
@property (nullable, copy) NSString *currentDirectoryPath;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSTASK_H */
