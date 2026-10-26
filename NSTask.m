/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/* **`posix_openpt`/`grantpt`/`unlockpt`/`ptsname` ARE XSI, AND A TRANSLATION UNIT HAS TO ASK FOR THEM BEFORE ITS
 * FIRST INCLUDE.** glibc hides their declarations behind `_XOPEN_SOURCE >= 600` unless `_GNU_SOURCE` is set, and the
 * failure is an "implicit declaration" pointing at functions the C library already has — the pty would then be built
 * from an `int` returned by a function the compiler believed did not exist. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
/*
 * NSTask.m — a subprocess, a reaper thread, and one handshake. The design is in NSTask.h; what is HERE is
 * the three orders that decide whether it works.
 *
 * ONE: THE CHILD GETS A COPY OF THE PARENT'S MEMORY, SO IT MUST TOUCH ALMOST NOTHING. Every allocation —
 * argv, envp, the paths, the descriptor lookups — happens BEFORE `fork(2)`, and the child does only
 * `dup2`, `close`, `chdir`, `setpgid`, `execve` and `_exit`, all of which are async-signal-safe. A child
 * that allocated would be a child of a THREADED process doing it, and that is the classic way a fork/exec
 * hangs on a lock the child inherited.
 *
 * TWO: THE PARENT CLOSES THE CHILD'S END OF EACH PIPE, AND ONLY FOR THE CHILD. A pipe handed to
 * `-setStandardInput:` has a WRITE end the parent still holds; if the child kept a copy of it too, a child
 * reading its standard input would never see END OF FILE, because the pipe would still have a writer. So
 * the far end is closed IN THE CHILD. The caller's own copies are left alone — the other half of that rule
 * is Apple's and is the caller's: a parent that reads to the end of a pipe must close its own copy of the
 * write end, which the probe does.
 *
 * THREE: THE REAPER OWNS THE STATUS. It is the ONLY caller of `waitpid(2)`, it records the raw status
 * under the condition and broadcasts, and `-waitUntilExit` waits for THAT rather than reaping again — so
 * the status is read exactly once, `-terminationStatus` can be asked for ever afterwards, and the
 * termination handler and the notification happen without anybody waiting at all, which is Apple's
 * contract. The reaper HOLDS A REFERENCE to the task, because this library is MRC and nothing else
 * promises the object outlives its child.
 */

#import "FNCondition.h"
#import <Foundation/NSTask.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSPipe.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

/* THE PROCESS'S OWN ENVIRONMENT, declared where it is used as NSProcessInfo.m does it. */
extern char **environ;

/* THE BLOCKS RUNTIME, declared where it is used: <Block.h> is staged nowhere and libobjc2 exports both. */
extern void *_Block_copy(const void *aBlock);
extern void _Block_release(const void *aBlock);

NSString *const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";

/* THE HOUSE ERROR, as NSFileManager and NSFileHandle spell it. */
static NSError *fn_task_error(int err)
{
	return [NSError errorWithDomain:@"NSPOSIXErrorDomain"
				   code:err
			       userInfo:[NSDictionary dictionaryWithObject:
						[NSString stringWithUTF8String:strerror(err)]
								    forKey:NSLocalizedDescriptionKey]];
}

static BOOL fn_task_failed(NSError **errorPtr, int err)
{
	if (errorPtr != NULL) {
		*errorPtr = fn_task_error(err);
	}
	return NO;
}

/* WHAT A STANDARD DESCRIPTOR SETTING MEANS IN DESCRIPTORS. Apple allows an NSPipe or an NSFileHandle, and
 * the DIRECTION is why this is not one call to `-fileDescriptor`: standard OUTPUT is the pipe's WRITE end
 * while standard INPUT is its READ end. */
static int fn_standard_child_fd(id object, BOOL isInput)
{
	if ([object isKindOfClass:[NSPipe class]]) {
		return isInput ? [[(NSPipe *)object fileHandleForReading] fileDescriptor]
			       : [[(NSPipe *)object fileHandleForWriting] fileDescriptor];
	}
	if ([object isKindOfClass:[NSFileHandle class]]) {
		return [(NSFileHandle *)object fileDescriptor];
	}
	return -1;
}

/* THE END THE CHILD MUST CLOSE: see this file's second note. */
static int fn_standard_far_fd(id object, BOOL isInput)
{
	if ([object isKindOfClass:[NSPipe class]]) {
		return isInput ? [[(NSPipe *)object fileHandleForWriting] fileDescriptor]
			       : [[(NSPipe *)object fileHandleForReading] fileDescriptor];
	}
	return -1;
}

/* `argv[0]` IS THE EXECUTABLE, and the arguments follow it — Apple's `-arguments` does NOT include the
 * program's own name, which is a difference every caller has to be told once. */
static char **fn_task_argv(NSString *path, NSArray *arguments)
{
	NSUInteger count = [arguments count], i;
	char **argv = (char **)malloc((count + 2) * sizeof(char *));

	if (argv == NULL) {
		return NULL;
	}
	argv[0] = strdup([path UTF8String]);
	for (i = 0; i < count; i++) {
		argv[i + 1] = strdup([[arguments objectAtIndex:i] UTF8String]);
	}
	argv[count + 1] = NULL;
	return argv;
}

static char **fn_task_envp(NSDictionary *environment, BOOL *owned)
{
	NSArray *keys;
	NSUInteger count, i;
	char **envp;

	*owned = NO;
	if (environment == nil) {
		return environ;		/* INHERIT, which is Apple's default */
	}
	keys = [environment allKeys];
	count = [keys count];
	envp = (char **)malloc((count + 1) * sizeof(char *));
	if (envp == NULL) {
		return NULL;
	}
	for (i = 0; i < count; i++) {
		NSString *key = [keys objectAtIndex:i];
		NSString *pair = [NSString stringWithFormat:@"%@=%@", key,
							     [environment objectForKey:key]];

		envp[i] = strdup([pair UTF8String]);
	}
	envp[count] = NULL;
	*owned = YES;
	return envp;
}

static void fn_task_free_vector(char **vector, BOOL owned)
{
	NSUInteger i;

	if (vector == NULL || !owned) {
		return;
	}
	for (i = 0; vector[i] != NULL; i++) {
		free(vector[i]);
	}
	free(vector);
}

/* A SIGNAL TO THE CHILD'S PROCESS GROUP, which is how "and all of its subtasks" is honoured — with a
 * fallback, because a kernel without process groups should still get the child itself. */
/* **THE PSEUDO-TERMINAL, OPENED WITHOUT libutil.** `posix_openpt`, `grantpt`, `unlockpt` and `ptsname` are libc, so
 * this adds no dependency; `openpty(3)` is the same three calls behind one name. The master is opened `O_CLOEXEC` so
 * the CHILD cannot inherit it — a child holding the master is a pty that never reports its own end of file. The
 * slave is opened by the parent and handed over, because a path lookup is not something the child should do after
 * `fork(2)`.
 *
 * TWO THINGS ARE SET BEFORE ANYBODY CAN ASK: the WINDOW SIZE, because `posix_openpt` leaves it 0x0 and every program
 * that reads `COLUMNS` believes what it is told, and `IUTF8`, so the line discipline erases a CHARACTER on kill/erase
 * rather than a byte — the difference between backspace working and backspace leaving half a codepoint behind. */
static int fn_pty_open(char *slave_name, size_t name_size, unsigned short rows, unsigned short columns)
{
	struct winsize size;
	struct termios settings;
	const char *name;
	int master;

	master = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (master < 0) {
		return -1;
	}
	if (grantpt(master) != 0 || unlockpt(master) != 0) {
		(void)close(master);
		return -1;
	}
	name = ptsname(master);
	if (name == NULL || strlen(name) + 1 > name_size) {
		(void)close(master);
		return -1;
	}
	memcpy(slave_name, name, strlen(name) + 1);
	memset(&size, 0, sizeof(size));
	size.ws_row = (unsigned short)(rows > 0 ? rows : 24);
	size.ws_col = (unsigned short)(columns > 0 ? columns : 80);
	(void)ioctl(master, TIOCSWINSZ, &size);
	if (tcgetattr(master, &settings) == 0) {
		settings.c_iflag |= IUTF8;
		(void)tcsetattr(master, TCSANOW, &settings);
	}
	return master;
}

static int fn_task_signal(pid_t pid, int sig)
{
	if (kill(-pid, sig) != 0) {
		return kill(pid, sig);
	}
	return 0;
}

@implementation NSTask

/* ---- the reaper --------------------------------------------------------- */

/* IT IS A C FUNCTION INSIDE THE IMPLEMENTATION, which is what lets it touch the task's ivars: the status
 * handshake is one object's private business, and a getter pair for it would be a public door for nobody. */
static void *fn_task_reaper(void *context)
{
	NSTask *task = (NSTask *)context;
	int status = 0;
	pid_t reaped;

	for (;;) {
		reaped = waitpid(task->_pid, &status, 0);
		if (reaped >= 0 || errno != EINTR) {
			break;
		}
	}
	[task->_condition lock];
	task->_status = status;
	task->_exited = YES;
	[task->_condition broadcast];
	[task->_condition unlock];

	[[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification
							    object:task];
	if (task->_terminationHandler != NULL) {
		task->_terminationHandler(task);
	}
	[task release];		/* the reference -launchAndReturnError: took for exactly this */
	return NULL;
}

/* ---- creating and initializing ------------------------------------------ */

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_qualityOfService = NSQualityOfServiceDefault;
		_condition = [[FNCondition alloc] init];
		_ptyMaster = -1;
		_ptyRows = 24;
		_ptyColumns = 80;
	}
	return self;
}

+ (instancetype)launchedTaskWithExecutableURL:(NSURL *)url
				    arguments:(NSArray *)arguments
					error:(NSError **)errorPtr
			 terminationHandler:(void (^)(NSTask *task))terminationHandler
{
	NSTask *task;

	/* APPLE'S OWN SENTENCE: "If arguments is nil, the system raises an NSInvalidArgumentException." */
	if (arguments == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"NSTask: -arguments must not be nil"];
	}
	task = [[[self alloc] init] autorelease];
	[task setExecutableURL:url];
	[task setArguments:arguments];
	[task setTerminationHandler:terminationHandler];
	if (![task launchAndReturnError:errorPtr]) {
		return nil;
	}
	return task;
}

/* ---- configuring -------------------------------------------------------- */

- (NSURL *)executableURL
{
	return _executableURL;
}

- (void)setExecutableURL:(NSURL *)url
{
	[url retain];
	[_executableURL release];
	_executableURL = url;
}

- (NSArray *)arguments
{
	return _arguments;
}

- (void)setArguments:(NSArray *)arguments
{
	[arguments retain];
	[_arguments release];
	_arguments = arguments;
}

- (NSDictionary *)environment
{
	return _environment;
}

- (void)setEnvironment:(NSDictionary *)environment
{
	[environment retain];
	[_environment release];
	_environment = environment;
}

- (NSURL *)currentDirectoryURL
{
	return _currentDirectoryURL;
}

- (void)setCurrentDirectoryURL:(NSURL *)url
{
	[url retain];
	[_currentDirectoryURL release];
	_currentDirectoryURL = url;
}

- (id)standardInput
{
	return _standardInput;
}

- (void)setStandardInput:(id)object
{
	[object retain];
	[_standardInput release];
	_standardInput = object;
}

- (id)standardOutput
{
	return _standardOutput;
}

- (void)setStandardOutput:(id)object
{
	[object retain];
	[_standardOutput release];
	_standardOutput = object;
}

- (id)standardError
{
	return _standardError;
}

- (void)setStandardError:(id)object
{
	[object retain];
	[_standardError release];
	_standardError = object;
}

- (NSQualityOfService)qualityOfService
{
	return _qualityOfService;
}

- (void)setQualityOfService:(NSQualityOfService)qualityOfService
{
	_qualityOfService = qualityOfService;
}

- (void (^)(NSTask *))terminationHandler
{
	return _terminationHandler;
}

- (void)setTerminationHandler:(void (^)(NSTask *))handler
{
	void (^copied)(NSTask *) = (handler != NULL) ? (void (^)(NSTask *))_Block_copy(handler) : NULL;

	if (_terminationHandler != NULL) {
		_Block_release(_terminationHandler);
	}
	_terminationHandler = copied;
}

/* ---- running ------------------------------------------------------------ */

- (BOOL)launchAndReturnError:(NSError **)errorPtr
{
	NSString *path;
	char **argv;
	char **envp;
	BOOL envpOwned;
	int inFd, outFd, errFd, inFar, outFar, errFar;
	int ptyMaster = -1, ptySlave = -1;
	char ptySlaveName[128];
	pthread_t reaper;
	pid_t pid;

	/* ONE INSTANCE RUNS ONCE — Apple: "You can only run the subprocess once per instance." */
	if (_launched) {
		return fn_task_failed(errorPtr, EALREADY);
	}
	if (_arguments == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"NSTask: -arguments must not be nil"];
	}
	if (_executableURL == nil) {
		return fn_task_failed(errorPtr, ENOENT);
	}
	path = [_executableURL path];
	if (path == nil || [path length] == 0) {
		return fn_task_failed(errorPtr, ENOENT);
	}
	if (access([path UTF8String], X_OK) != 0) {
		return fn_task_failed(errorPtr, errno);
	}

	/* EVERYTHING THAT ALLOCATES, BEFORE THE FORK. */
	argv = fn_task_argv(path, _arguments);
	envp = fn_task_envp(_environment, &envpOwned);
	if (argv == NULL || envp == NULL) {
		fn_task_free_vector(argv, YES);
		fn_task_free_vector(envp, envpOwned);
		return fn_task_failed(errorPtr, ENOMEM);
	}
	if (_usesPseudoTerminal) {
		/* **A TERMINAL IS ALL THREE DESCRIPTORS OR NONE.** The three stdio slots are not consulted in this mode
		 * (the header says so): the slave is stdin, stdout and stderr, and the caller's end is the master. Both
		 * halves are opened here, BEFORE the fork, so the child does no path lookup and no allocation. */
		ptyMaster = fn_pty_open(ptySlaveName, sizeof(ptySlaveName), _ptyRows, _ptyColumns);
		if (ptyMaster < 0) {
			fn_task_free_vector(argv, YES);
			fn_task_free_vector(envp, envpOwned);
			return fn_task_failed(errorPtr, errno);
		}
		ptySlave = open(ptySlaveName, O_RDWR);
		if (ptySlave < 0) {
			int err = errno;

			(void)close(ptyMaster);
			fn_task_free_vector(argv, YES);
			fn_task_free_vector(envp, envpOwned);
			return fn_task_failed(errorPtr, err);
		}
		inFd = outFd = errFd = ptySlave;
		inFar = outFar = errFar = -1;
	} else {
		inFd = fn_standard_child_fd(_standardInput, YES);
		inFar = fn_standard_far_fd(_standardInput, YES);
		outFd = fn_standard_child_fd(_standardOutput, NO);
		outFar = fn_standard_far_fd(_standardOutput, NO);
		errFd = fn_standard_child_fd(_standardError, NO);
		errFar = fn_standard_far_fd(_standardError, NO);
	}

	pid = fork();
	if (pid < 0) {
		int err = errno;

		if (ptyMaster >= 0) {
			(void)close(ptyMaster);
		}
		if (ptySlave >= 0) {
			(void)close(ptySlave);
		}
		fn_task_free_vector(argv, YES);
		fn_task_free_vector(envp, envpOwned);
		return fn_task_failed(errorPtr, err);
	}
	if (pid == 0) {
		/* THE CHILD: ASYNC-SIGNAL-SAFE CALLS ONLY, from here to execve. */
		if (inFd >= 0) {
			(void)dup2(inFd, STDIN_FILENO);
		}
		if (outFd >= 0) {
			(void)dup2(outFd, STDOUT_FILENO);
		}
		if (errFd >= 0) {
			(void)dup2(errFd, STDERR_FILENO);
		}
		if (inFar >= 0 && inFar != inFd) {
			(void)close(inFar);	/* or the child's stdin never ends */
		}
		if (outFar >= 0 && outFar != outFd) {
			(void)close(outFar);
		}
		if (errFar >= 0 && errFar != errFd) {
			(void)close(errFar);
		}
		if (_currentDirectoryURL != nil) {
			const char *directory = [[_currentDirectoryURL path] UTF8String];

			if (directory != NULL) {
				(void)chdir(directory);
			}
		}
		/* **A PSEUDO-TERMINAL NEEDS A SESSION, AND THE ORDER IS LOAD-BEARING.** `setsid(2)` makes this process a
		 * session leader with NO controlling terminal; `TIOCSCTTY` on the slave (now fd 0) then names this pty as
		 * that terminal — which is what lets the line discipline signal the foreground group and what makes
		 * `isatty(3)` true. `setpgid` is NOT called in this mode: a session leader is already its own process
		 * group, and the call would fail with `EPERM`. The master is closed in the child, because one holder of it
		 * is the parent and a second is a terminal that never reports EOF. */
		if (ptyMaster >= 0) {
			(void)close(ptyMaster);
			(void)setsid();
			(void)ioctl(STDIN_FILENO, TIOCSCTTY, 0);
		} else {
			(void)setpgid(0, 0);	/* its own group, so one signal reaches the subtree */
		}
		execve([path UTF8String], argv, envp);
		_exit(127);			/* the shell's own "cannot execute" */
	}

	fn_task_free_vector(argv, YES);
	fn_task_free_vector(envp, envpOwned);

	if (ptySlave >= 0) {
		/* THE PARENT MUST NOT HOLD THE SLAVE: a second holder of the child's own end is a master that never
		 * reports EOF after the child exits. */
		(void)close(ptySlave);
	}
	if (ptyMaster >= 0) {
		_ptyMaster = ptyMaster;
		/* THE TASK OWNS THE DESCRIPTOR (the handle does not close it), so the fd's lifetime is the task's and a
		 * caller's handle cannot outlive the number it names by releasing the handle first. */
		_ptyHandle = [[NSFileHandle alloc] initWithFileDescriptor:ptyMaster closeOnDealloc:NO];
	}

	_pid = pid;
	_launched = YES;

	/* THE REAPER TAKES A REFERENCE, and gets it BEFORE the thread exists so the thread cannot outrun it. */
	[self retain];
	if (pthread_create(&reaper, NULL, fn_task_reaper, (void *)self) == 0) {
		_reaperStarted = YES;
		(void)pthread_detach(reaper);
	} else {
		/* NO REAPER: -waitUntilExit reaps instead, which is the whole fallback path. */
		[self release];
		_reaperStarted = NO;
	}
	return YES;
}

- (void)interrupt
{
	if (_launched && !_exited) {
		(void)fn_task_signal(_pid, SIGINT);
	}
}

- (void)terminate
{
	if (_launched && !_exited) {
		(void)fn_task_signal(_pid, SIGTERM);
	}
}

- (BOOL)suspend
{
	if (!_launched || _exited) {
		return NO;
	}
	return fn_task_signal(_pid, SIGSTOP) == 0;
}

- (BOOL)resume
{
	if (!_launched || _exited) {
		return NO;
	}
	return fn_task_signal(_pid, SIGCONT) == 0;
}

- (void)waitUntilExit
{
	if (!_launched) {
		return;
	}
	if (!_reaperStarted) {
		int status = 0;

		while (waitpid(_pid, &status, 0) < 0 && errno == EINTR) {
			;
		}
		[_condition lock];
		_status = status;
		_exited = YES;
		[_condition broadcast];
		[_condition unlock];
		return;
	}
	[_condition lock];
	while (!_exited) {
		[_condition wait];
	}
	[_condition unlock];
}

/* ---- querying ----------------------------------------------------------- */

- (BOOL)isRunning
{
	return _launched && !_exited;
}

- (int)processIdentifier
{
	return (int)_pid;
}

- (int)terminationStatus
{
	if (!_exited) {
		return 0;
	}
	if (WIFEXITED(_status)) {
		return WEXITSTATUS(_status);
	}
	if (WIFSIGNALED(_status)) {
		return WTERMSIG(_status);	/* OURS: see the header */
	}
	return 0;
}

- (NSTaskTerminationReason)terminationReason
{
	if (_exited && WIFSIGNALED(_status)) {
		return NSTaskTerminationReasonUncaughtSignal;
	}
	return NSTaskTerminationReasonExit;
}

/* ---- the pseudo-terminal's doors ---------------------------------------- */

- (BOOL)usesPseudoTerminal
{
	return _usesPseudoTerminal;
}

- (void)setUsesPseudoTerminal:(BOOL)flag
{
	/* A LAUNCHED TASK'S DESCRIPTORS ARE ITS CHILD'S: flipping the mode after the fork would describe a process that
	 * does not exist. Setting it on a launched task is a no-op rather than an exception, because the alternative is
	 * an exception in a callback. */
	if (_launched) {
		return;
	}
	_usesPseudoTerminal = flag;
}

- (NSFileHandle *)pseudoterminalHandle
{
	return _ptyHandle;
}

- (BOOL)setPseudoterminalRows:(unsigned short)rows columns:(unsigned short)columns
{
	struct winsize size;

	if (rows == 0 || columns == 0) {
		return NO;	/* a terminal with no size is worse than one with the default */
	}
	_ptyRows = rows;
	_ptyColumns = columns;
	if (_ptyMaster < 0) {
		return YES;	/* stored: the launch applies it before the child can ask */
	}
	memset(&size, 0, sizeof(size));
	size.ws_row = rows;
	size.ws_col = columns;
	/* THE KERNEL DOES THE REST: a size change on a pty sends SIGWINCH to the foreground process group. */
	return (ioctl(_ptyMaster, TIOCSWINSZ, &size) == 0) ? YES : NO;
}

- (unsigned short)pseudoterminalRows
{
	return _ptyRows;
}

- (unsigned short)pseudoterminalColumns
{
	return _ptyColumns;
}

- (void)dealloc
{
	/* REACHED ONLY WHEN THE REAPER HAS RELEASED ITS REFERENCE, so a running task's object is never torn
	 * down under its own child. */
	[_executableURL release];
	[_arguments release];
	[_environment release];
	[_currentDirectoryURL release];
	[_standardInput release];
	[_standardOutput release];
	[_standardError release];
	[_condition release];
	[_ptyHandle release];
	if (_ptyMaster >= 0) {
		(void)close(_ptyMaster);
		_ptyMaster = -1;
	}
	if (_terminationHandler != NULL) {
		_Block_release(_terminationHandler);
	}
	[super dealloc];
}


- (void)launch
{
	/* THE PRE-10.6 SPELLING: the modern door is where the work is. A failure surfaces the way the legacy API
	 * surfaced it — the task is simply not running. */
	(void)[self launchAndReturnError:NULL];
}

+ (instancetype)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments
{
	NSTask *task = [[self alloc] init];

	[task setLaunchPath:path];
	[task setArguments:arguments];
	[task launch];
	return [task autorelease];
}

- (NSString *)launchPath
{
	NSURL *url = [self executableURL];

	return url != nil ? [url path] : nil;
}

- (void)setLaunchPath:(NSString *)path
{
	if (path == nil) {
		[self setExecutableURL:(NSURL *)nil];
		return;
	}
	[self setExecutableURL:(NSURL *)[NSURL fileURLWithPath:path]];
}

- (NSString *)currentDirectoryPath
{
	NSURL *url = [self currentDirectoryURL];

	return url != nil ? [url path] : nil;
}

- (void)setCurrentDirectoryPath:(NSString *)path
{
	if (path == nil) {
		[self setCurrentDirectoryURL:(NSURL *)nil];
		return;
	}
	[self setCurrentDirectoryURL:(NSURL *)[NSURL fileURLWithPath:path]];
}
@end
