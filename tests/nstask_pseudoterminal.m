/*
 * nstask_pseudoterminal — a child with a pty for a controlling terminal, and the four things that makes true.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHAT THIS HOLDS UP, AND WHY EACH ONE IS SEPARATE. "Runs a shell on a pty" is not one property but five, and a
 * pty that is merely a pair of descriptors satisfies none of them:
 *
 *   1. THE CHILD HAS A TERMINAL. `isatty(3)` is true on fd 0 and `tty(1)` names a `/dev/pts/…` — the difference
 *      between a terminal and a pipe.
 *   2. IT HAS ITS OWN SESSION, AND THAT TERMINAL IS THE CONTROLLING ONE. The shell's session id is its own pid (it
 *      is the session leader `setsid` made) and its `tty_nr` is not zero. Without this the next three cannot work.
 *   3. THE LINE DISCIPLINE IS LIVE. Two things prove it, and one is not enough: writing to the MASTER is ECHOED back
 *      (the terminal, not the shell), and `^C` on the master KILLS the child with SIGINT — which only happens if
 *      the kernel is signalling the terminal's FOREGROUND PROCESS GROUP, i.e. the session claim took.
 *   4. THE SIZE IS THE CALLER'S, BEFORE AND AFTER. A size set before the launch is what the child's first
 *      `TIOCGWINSZ` answers (that is what a shell reads for `COLUMNS`/`LINES`), and a size set afterwards reaches
 *      the child as `SIGWINCH` — trapped here, so the check is the signal rather than a `stty` reading.
 *   5. THE MASTER IS A RUN-LOOP SOURCE. The child's output is read through `-readabilityHandler:` and a run-loop
 *      wait, which is the path a terminal actually uses — a pty is a character device, so the loop's file guard does
 *      not swallow it, and getting this wrong would be a terminal that only reads when a key is pressed.
 *
 * A FIFTH OF THE POINT IS THE SHAPE: no forkpty, no libutil. `posix_openpt`/`grantpt`/`unlockpt`/`ptsname` are libc,
 * and the child's half is `setsid` + `TIOCSCTTY` — the same pair `window-server/src/session-vt.c` uses for the
 * compositor's own session.
 *
 * THE CHILD IS ALWAYS `/bin/sh`, and each case is a SCRIPT rather than a program, so the test asserts what a shell
 * reports rather than what this file happens to believe.
 */
#import <Foundation/Foundation.h>

#include <signal.h>
#include <stdio.h>
#include <string.h>

static int g_checks;
static int g_failed;

static void check(int ok, const char *what, const char *detail)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s%s%s\n", what, (detail != NULL) ? " — " : "", (detail != NULL) ? detail : "");
	} else {
		printf("  [ok]   %s\n", what);
	}
}

/* THE MASTER READ THROUGH A READABILITY HANDLER AND THE RUN LOOP, which is the terminal's own path. Every wait below
 * is "until the marker appears or the deadline passes": a test that waited a fixed time would be a test that fails on
 * a loaded machine, and one that waited forever would be a test that hangs one. */
@interface PTYReader : NSObject
{
@public
	NSMutableData *data;
}
@end

@implementation PTYReader
- (void)readable:(NSFileHandle *)handle
{
	/* **NOT `-availableData`**: Apple spells that "read to the end of the file", and a pty has no end of file while
	 * the child is alive — the first read would block the loop forever. One read of what is there is what a terminal
	 * wants, and it is the read the source's readiness just promised. */
	NSData *chunk = [handle readDataOfLength:4096];

	if (chunk != nil && [chunk length] > 0) {
		[data appendData:chunk];
		return;
	}
	/* **END OF FILE IS THE HANDLER'S OWN TO ACT ON.** A pty master whose child has gone is readable FOR EVER (the
	 * read fails with EIO), so a level-triggered source that is left installed is a loop that spins — which is what
	 * this test did before this line existed. A terminal uninstalls here too. */
	[handle setReadabilityHandler:nil];
}
@end

/* RUN THE LOOP UNTIL `marker` HAS BEEN SEEN (or the task ended, so a child that died is not waited out). */
static BOOL wait_for(PTYReader *reader, NSString *marker, NSTask *task, double seconds)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];

	while ([deadline timeIntervalSinceNow] > 0.0) {
		NSString *seen = [[[NSString alloc] initWithData:reader->data encoding:NSUTF8StringEncoding] autorelease];

		if (seen != nil && [seen rangeOfString:marker].location != NSNotFound) {
			return YES;
		}
		if (task != nil && ![task isRunning]) {
			/* ONE MORE PASS, so what the child wrote before it died is read rather than missed. */
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
			return NO;
		}
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	}
	return NO;
}

static NSString *text(PTYReader *reader)
{
	return [[[NSString alloc] initWithData:reader->data encoding:NSUTF8StringEncoding] autorelease];
}

static void write_to(NSTask *task, const char *bytes)
{
	[[task pseudoterminalHandle] writeData:[NSData dataWithBytes:bytes length:strlen(bytes)]];
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1, 2, 3 and 4's first half: ONE shell, and a short report about itself.
		 * ============================================================================================ */
		NSTask *task = [[NSTask alloc] init];
		PTYReader *reader = [[PTYReader alloc] init];
		NSError *error = nil;

		setvbuf(stdout, NULL, _IONBF, 0);

		[task setExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]];
		/* **THE SHELL ANSWERS THE SESSION QUESTION ITSELF**, because parsing two numbers out of one line is a test
		 * that can be wrong for a reason that is not the pty's: `[ "$sid" = "$$" ]` is the assertion, and this file
		 * reads its answer. `tty_nr` is field 7 of the process's own `/proc` stat — zero when a process has no
		 * controlling terminal, which is exactly the failure mode `setsid` without `TIOCSCTTY` leaves behind. */
		[task setArguments:[NSArray arrayWithObjects:@"-c",
			@"echo ready; echo tty=$(tty); "
			 "if [ -t 0 ]; then echo isatty=yes; else echo isatty=no; fi; "
			 "if [ \"$(ps -o sid= -p $$ | tr -d ' ')\" = \"$$\" ]; then "
			   "echo session=own; else echo session=other; fi; "
			 "echo ttynr=$(awk '{print $7}' /proc/$$/stat); "
			 "echo size=$(stty size); cat", nil]];	/* cat keeps a child alive for the echo case */
		[task setUsesPseudoTerminal:YES];
		check([task setPseudoterminalRows:33 columns:101], "a size can be set before the launch", NULL);
		check([task pseudoterminalRows] == 33 && [task pseudoterminalColumns] == 101,
		      "and it is what the task reports", NULL);
		check(![task setPseudoterminalRows:0 columns:101], "a zero dimension is refused", NULL);

		check([task launchAndReturnError:&error], "the task launched with a pty",
		      error != nil ? [[error localizedDescription] UTF8String] : NULL);
		reader->data = [[NSMutableData alloc] init];
		[[task pseudoterminalHandle] setReadabilityHandler:^(NSFileHandle *h) { [reader readable:h]; }];
		check([task pseudoterminalHandle] != nil, "the master end is a handle the task owns", NULL);

		check(wait_for(reader, @"size=", task, 5.0), "the child's report arrived through the run loop", NULL);

		{
			NSString *out = text(reader);

			check([out rangeOfString:@"tty=/dev/pts/"].location != NSNotFound,
			      "fd 0 is a terminal, and tty(1) names a pty", [out UTF8String]);
			check([out rangeOfString:@"isatty=yes"].location != NSNotFound,
			      "isatty(3) is true on the child's stdin", NULL);
			check([out rangeOfString:[NSString stringWithFormat:@"size=33 101"]].location != NSNotFound,
			      "the size set BEFORE the launch is what the child's first TIOCGWINSZ answers",
			      [out UTF8String]);
			{
				NSUInteger ttyField = [out rangeOfString:@"ttynr="].location;

				check([out rangeOfString:@"session=own"].location != NSNotFound,
				      "the child is its own SESSION leader, so the pty is its CONTROLLING terminal",
				      [out UTF8String]);
				check(ttyField != NSNotFound &&
				      [[out substringFromIndex:ttyField] rangeOfString:@"ttynr=0\n"].location == NSNotFound,
				      "and its controlling terminal is recorded (tty_nr is not zero)", NULL);
			}
		}

		/* ============================================================================================
		 * 3: THE LINE DISCIPLINE — echo, then the signal a terminal sends for ^C.
		 * ============================================================================================ */
		write_to(task, "echo from-the-master\n");
		check(wait_for(reader, @"from-the-master", task, 3.0),
		      "what is written to the master is ECHOED and run by the shell", NULL);
		[task terminate];
		[task waitUntilExit];

		/* ============================================================================================
		 * 4's second half: A SIZE CHANGE REACHES THE CHILD AS SIGWINCH.
		 * ============================================================================================ */
		{
			NSTask *winch = [[NSTask alloc] init];
			PTYReader *winchReader = [[PTYReader alloc] init];
			NSError *winchError = nil;

			[winch setExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]];
			[winch setArguments:[NSArray arrayWithObjects:@"-c",
				@"trap 'echo got-winch $(stty size)' WINCH; echo armed; while :; do sleep 0.05; done", nil]];
			[winch setUsesPseudoTerminal:YES];
			check([winch launchAndReturnError:&winchError], "the WINCH child launched",
			      winchError != nil ? [[winchError localizedDescription] UTF8String] : NULL);
			winchReader->data = [[NSMutableData alloc] init];
			[[winch pseudoterminalHandle] setReadabilityHandler:^(NSFileHandle *h) { [winchReader readable:h]; }];
			check(wait_for(winchReader, @"armed", winch, 5.0), "the WINCH child armed its trap", NULL);
			check([winch setPseudoterminalRows:40 columns:120], "the size is changed AFTER the launch", NULL);
			check(wait_for(winchReader, @"got-winch 40 120", winch, 5.0),
			      "and it arrives as SIGWINCH carrying the new size", [text(winchReader) UTF8String]);
			[winch terminate];
			[winch waitUntilExit];
			[[winch pseudoterminalHandle] setReadabilityHandler:nil];
			[winchReader release];
			[winch release];
		}

		/* ============================================================================================
		 * 3 again, as a SIGNAL rather than an echo: ^C is the line discipline's, not the shell's.
		 * ============================================================================================ */
		{
			NSTask *victim = [[NSTask alloc] init];
			PTYReader *victimReader = [[PTYReader alloc] init];
			NSError *victimError = nil;

			[victim setExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]];
			[victim setArguments:[NSArray arrayWithObjects:@"-c", @"echo waiting; sleep 30; echo survived", nil]];
			[victim setUsesPseudoTerminal:YES];
			check([victim launchAndReturnError:&victimError], "the ^C child launched",
			      victimError != nil ? [[victimError localizedDescription] UTF8String] : NULL);
			victimReader->data = [[NSMutableData alloc] init];
			[[victim pseudoterminalHandle] setReadabilityHandler:^(NSFileHandle *h) { [victimReader readable:h]; }];
			check(wait_for(victimReader, @"waiting", victim, 5.0), "the child is running", NULL);
			write_to(victim, "\x03");	/* ^C, on the master: a byte the TERMINAL turns into a signal */
			[victim waitUntilExit];
			check([victim terminationReason] == NSTaskTerminationReasonUncaughtSignal,
			      "^C on the master killed the child WITH A SIGNAL, not by the shell exiting", NULL);
			check([victim terminationStatus] == SIGINT,
			      "and the signal is SIGINT, which means the kernel found a FOREGROUND GROUP to send it to",
			      NULL);
			check([text(victimReader) rangeOfString:@"survived"].location == NSNotFound,
			      "the child did not run to completion", NULL);
			[[victim pseudoterminalHandle] setReadabilityHandler:nil];
			[victimReader release];
			[victim release];
		}

		/* ============================================================================================
		 * AND THE ORDINARY PATH IS UNCHANGED: a task with no pty is still three pipes.
		 * ============================================================================================ */
		{
			NSTask *plain = [[NSTask alloc] init];
			NSPipe *pipe = [NSPipe pipe];
			NSData *out;

			[plain setExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"]];
			[plain setArguments:[NSArray arrayWithObjects:@"-c", @"[ -t 0 ] && echo tty || echo notty", nil]];
			[plain setStandardOutput:pipe];
			check([plain launchAndReturnError:NULL], "a task with no pty still launches", NULL);
			/* THE PARENT MUST LET GO OF THE WRITE END, or "read to end of file" never sees one: the pipe's
			 * writing handle is open in this process for as long as the NSPipe lives. */
			[[pipe fileHandleForWriting] closeFile];
			out = [[pipe fileHandleForReading] readDataToEndOfFile];
			[plain waitUntilExit];
			check([[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] != nil &&
			      [[[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] autorelease]
				isEqualToString:@"notty\n"],
			      "and its stdin is a pipe, not a terminal", NULL);
		}

		printf("  ... all four cases are done\n");
		[[task pseudoterminalHandle] setReadabilityHandler:nil];
		[reader release];
		[task release];

		printf("%s (%d check%s)\n", g_failed ? "FAILURES" : "all checks passed", g_checks,
		       (g_checks == 1) ? "" : "s");
	}
	return g_failed ? 1 : 0;
}
