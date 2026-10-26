/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_scripting_archive.m — THE SCRIPTING FAMILY'S ELEVEN NSCoding CONFORMANCES, MEASURED BY AN ARCHIVE.
 *
 * W6's last batch. A `whose` clause, a command and a command description are values a document keeps, so each one
 * writes its own state and reads it back: this probe builds a small graph of every kind, archives it, unarchives it,
 * and compares the state — including the standard suite's key specifier, which travels with the command.
 *
 * NSDistantObject is the one conformance that is DECLARED AND REFUSED: a proxy cannot be rebuilt from bytes because a
 * connection cannot be (the name server is per-process), so archiving one raises by name.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSScriptCommand.h>
#import <Foundation/NSScriptStandardSuiteCommands.h>
#import <Foundation/NSScriptCommandDescription.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSKeyedArchiver.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ---- the specifier tree: every concrete kind with state, one archive, the same values back ---- */
	{
		NSNameSpecifier *name = [[[NSNameSpecifier alloc]
			initWithContainerClassDescription:nil
				       containerSpecifier:nil
						    key:@"items"
						   name:@"alpha"] autorelease];
		/* THE CHILD'S CONTAINER IS NOT `name`: a specifier graph with both links pointing at each other is a cycle the
		 * evaluator would walk forever, and Cocoa's shape is one direction for containment and the child link for the
		 * walk down. */
		NSNameSpecifier *child = [[[NSNameSpecifier alloc]
			initWithContainerClassDescription:nil
				       containerSpecifier:nil
						    key:@"children"
						   name:@"beta"] autorelease];
		NSUniqueIDSpecifier *unique = [[[NSUniqueIDSpecifier alloc]
			initWithContainerClassDescription:nil
				       containerSpecifier:nil
						    key:@"items"
					       uniqueID:@"id-42"] autorelease];
		NSRangeSpecifier *range = [[[NSRangeSpecifier alloc]
			initWithContainerClassDescription:nil
				       containerSpecifier:nil
						    key:@"items"
					 startSpecifier:name
					   endSpecifier:child] autorelease];
		NSRelativeSpecifier *relative = [[[NSRelativeSpecifier alloc]
			initWithContainerClassDescription:nil
				       containerSpecifier:nil
						    key:@"items"
				       relativePosition:NSRelativeBefore
					  baseSpecifier:name] autorelease];
		NSSpecifierTest *test = [[[NSSpecifierTest alloc]
			initWithObjectSpecifier:name
			     comparisonOperator:NSEqualToComparison
				     testObject:@"alpha"] autorelease];
		NSWhoseSpecifier *whose = [[[NSWhoseSpecifier alloc]
			initWithContainerClassDescription:nil
				       containerSpecifier:nil
						    key:@"items"
						   test:test] autorelease];
		NSLogicalTest *logical = [[[NSLogicalTest alloc]
			initAndTestWithTests:[NSArray arrayWithObjects:test, test, nil]] autorelease];
		NSData *archive;
		id restored;

		[name setChildSpecifier:child];
		[name setContainerIsObjectBeingTested:YES];
		[name setEvaluationErrorNumber:7];
		[whose setStartSubelementIdentifier:NSIndexSubelement];
		[whose setStartSubelementIndex:2];
		[whose setEndSubelementIdentifier:NSEverySubelement];
		[whose setEndSubelementIndex:-1];

		check([name conformsToProtocol:@protocol(NSCoding)] &&
		      [NSWhoseSpecifier conformsToProtocol:@protocol(NSCoding)] &&
		      [NSSpecifierTest conformsToProtocol:@protocol(NSCoding)],
		      "the specifier family declares NSCoding");

		/* EVERY SPECIFIER IN ONE GRAPH, so nesting is exercised and not just a leaf. */
		archive = [NSKeyedArchiver archivedDataWithRootObject:
			[NSArray arrayWithObjects:name, unique, range, relative, whose, logical, nil]];
		restored = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
		check([restored isKindOfClass:[NSArray class]] && [restored count] == 6,
		      "the archive of the specifier graph comes back as the same shape");

		{
			NSNameSpecifier *back = [restored objectAtIndex:0];

			check([back isKindOfClass:[NSNameSpecifier class]] && [[back key] isEqualToString:@"items"] &&
			      [[back name] isEqualToString:@"alpha"] &&
			      [back containerIsObjectBeingTested] && [back evaluationErrorNumber] == 7,
			      "a name specifier keeps its key, its name and the base fields");
			check([[back childSpecifier] isKindOfClass:[NSNameSpecifier class]] &&
			      [[[(NSNameSpecifier *)[back childSpecifier] name] description] isEqualToString:@"beta"],
			      "and its child specifier, which is a whole specifier of its own");
		}
		check([[[restored objectAtIndex:1] uniqueID] isEqual:@"id-42"],
		      "a unique-ID specifier keeps its identifier");
		check([[[restored objectAtIndex:2] startSpecifier] isKindOfClass:[NSNameSpecifier class]] &&
		      [[[[restored objectAtIndex:2] startSpecifier] name] isEqualToString:@"alpha"] &&
		      [[[[restored objectAtIndex:2] endSpecifier] name] isEqualToString:@"beta"],
		      "a range specifier keeps both ends");
		check([[[restored objectAtIndex:3] baseSpecifier] isKindOfClass:[NSNameSpecifier class]] &&
		      [[restored objectAtIndex:3] relativePosition] == NSRelativeBefore,
		      "a relative specifier keeps its position and its base");
		check([[[restored objectAtIndex:4] test] isKindOfClass:[NSSpecifierTest class]] &&
		      [[[[restored objectAtIndex:4] test] description] length] > 0 &&
		      [[restored objectAtIndex:4] startSubelementIdentifier] == NSIndexSubelement &&
		      [[restored objectAtIndex:4] startSubelementIndex] == 2 &&
		      [[restored objectAtIndex:4] endSubelementIdentifier] == NSEverySubelement &&
		      [[restored objectAtIndex:4] endSubelementIndex] == -1,
		      "a whose specifier keeps its test and its two subelement ranges");
		check([[restored objectAtIndex:5] isKindOfClass:[NSLogicalTest class]],
		      "a logical test survives the archive as itself");

		/* AND ITS SUBTESTS SURVIVE TOO, measured on a test that can be evaluated without the specifier graph: NOT of the
		 * base test (which answers NO) is YES, and it is YES only if the subtest came back. */
		{
			NSLogicalTest *notTest = [[[NSLogicalTest alloc]
				initNotTestWithTest:[[[NSScriptWhoseTest alloc] init] autorelease]] autorelease];
			NSData *notArchive = [NSKeyedArchiver archivedDataWithRootObject:notTest];
			id notBack = [NSKeyedUnarchiver unarchiveObjectWithData:notArchive];

			check([notBack isKindOfClass:[NSLogicalTest class]] && [notBack isTrue],
			      "a logical test's subtests survive the archive: NOT of the base's NO is YES");
		}
	}

	/* ---- the command, its description, and the standard suite's key specifier ---- */
	{
		NSScriptCommandDescription *description = [[[NSScriptCommandDescription alloc]
			initWithSuiteName:@"Agora Suite"
			      commandName:@"Do Thing"
			       dictionary:[NSDictionary dictionaryWithObjectsAndKeys:
				@"AgoraDoThingCommand", @"CommandClass", nil]] autorelease];
		NSScriptCommand *command = [[[NSScriptCommand alloc] initWithCommandDescription:description] autorelease];
		NSNameSpecifier *receiver = [[[NSNameSpecifier alloc]
			initWithContainerClassDescription:nil containerSpecifier:nil key:@"items" name:@"alpha"] autorelease];
		NSSetCommand *setCommand = [[[NSSetCommand alloc] initWithCommandDescription:description] autorelease];
		NSNameSpecifier *key = [[[NSNameSpecifier alloc]
			initWithContainerClassDescription:nil containerSpecifier:nil key:@"properties" name:@"colour"] autorelease];
		NSData *archive;
		id restored;

		[command setDirectParameter:@"value"];
		[command setArguments:[NSDictionary dictionaryWithObject:@"arg" forKey:@"argument"]];
		[command setReceiversSpecifier:receiver];
		[command setScriptErrorNumber:9];
		[command setScriptErrorString:@"a script error"];
		[setCommand setKeySpecifier:key];

		archive = [NSKeyedArchiver archivedDataWithRootObject:description];
		restored = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
		check([restored isKindOfClass:[NSScriptCommandDescription class]] &&
		      [[restored suiteName] isEqualToString:@"Agora Suite"] &&
		      [[restored commandName] isEqualToString:@"Do Thing"] &&
		      [[restored commandClassName] isEqualToString:@"AgoraDoThingCommand"],
		      "a command description archives its three strings");

		archive = [NSKeyedArchiver archivedDataWithRootObject:command];
		restored = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
		check([restored isKindOfClass:[NSScriptCommand class]] &&
		      [[[restored commandDescription] commandName] isEqualToString:@"Do Thing"] &&
		      [[restored directParameter] isEqual:@"value"] &&
		      [[[restored arguments] objectForKey:@"argument"] isEqual:@"arg"] &&
		      [[restored receiversSpecifier] isKindOfClass:[NSNameSpecifier class]] &&
		      [restored scriptErrorNumber] == 9 &&
		      [[restored scriptErrorString] isEqualToString:@"a script error"],
		      "a command archives its description, parameter, arguments, receiver and script error");

		archive = [NSKeyedArchiver archivedDataWithRootObject:setCommand];
		restored = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
		check([restored isKindOfClass:[NSSetCommand class]] &&
		      [[[restored keySpecifier] key] isEqualToString:@"properties"] &&
		      [[[restored keySpecifier] name] isEqualToString:@"colour"],
		      "a standard command carries its key specifier through the archive");
	}

	/* ---- NSDistantObject: the conformance is declared and BOTH coder doors refuse by name ---- */
	{
		NSDistantObject *proxy = [NSDistantObject proxyWithTarget:nil connection:nil];
		BOOL raised = NO;

		check([proxy conformsToProtocol:@protocol(NSCoding)],
		      "a proxy declares NSCoding, as Apple's class does");
		@try {
			[NSKeyedArchiver archivedDataWithRootObject:proxy];
		}
		@catch (NSException *exception) {
			raised = [[exception name] isEqualToString:NSInvalidArgumentException];
		}
		check(raised, "archiving a proxy refuses by name rather than writing a connection it cannot rebuild");
	}

	printf("foundation_10_11_scripting_archive: %d of %d cases passed, %d failed\n",
	       g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
