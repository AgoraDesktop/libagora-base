/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * W5: the script-task family refuses by name — no OSA component and no Automator engine exist here.
 */
#import <Foundation/NSUserScriptTask.h>
#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <stdio.h>

NSString *const NSUserScriptTaskErrorDomain = @"NSUserScriptTaskErrorDomain";

static NSError *fn_script_error(void)
{
	return [NSError errorWithDomain:NSUserScriptTaskErrorDomain
				   code:1
			       userInfo:[NSDictionary dictionaryWithObject:
					 @"this system has no OSA component or Automator engine, so a user "
					 @"script cannot run"
								     forKey:NSLocalizedDescriptionKey]];
}

@implementation NSUserScriptTask

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSUserScriptTask initWithURL:error:] cannot run a user script; this "
			"system has no OSA component or Automator engine\n");
	if (error != NULL) {
		*error = fn_script_error();
	}
	[self release];
	return nil;
}

- (void)dealloc
{
	[_scriptURL release];
	[super dealloc];
}

- (NSURL *)scriptURL { return _scriptURL; }

- (void)executeWithCompletionHandler:(void (^)(NSError *))handler
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSUserScriptTask executeWithCompletionHandler:] cannot run a user script; "
			"this system has no OSA component\n");
	if (handler != nil) {
		handler(fn_script_error());
	}
}

@end

@implementation NSUserAppleScriptTask

- (void)executeWithAppleEvent:(NSAppleEventDescriptor *)event
	    completionHandler:(void (^)(NSAppleEventDescriptor *, NSError *))handler
{
	(void)event;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSUserAppleScriptTask executeWithAppleEvent:completionHandler:] cannot run "
			"an AppleScript; this system has no OSA component\n");
	if (handler != nil) {
		handler(nil, fn_script_error());
	}
}

@end

@implementation NSUserAutomatorTask

- (void)dealloc
{
	[_variables release];
	[super dealloc];
}

- (NSDictionary *)variables { return _variables; }

- (void)setVariables:(NSDictionary *)variables
{
	NSDictionary *copied = [variables copy];

	[_variables release];
	_variables = copied;
}

- (void)executeWithInput:(id)input completionHandler:(void (^)(id, NSError *))handler
{
	(void)input;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSUserAutomatorTask executeWithInput:completionHandler:] cannot run an "
			"Automator workflow; this system has no Automator engine\n");
	if (handler != nil) {
		handler(nil, fn_script_error());
	}
}

@end
