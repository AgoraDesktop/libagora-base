/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <Foundation/NSAppleScript.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSString.h>
#import <Foundation/NSData.h>
#import <Foundation/NSError.h>
#import <Foundation/NSThread.h>

static void fn_script_error(NSError **error, NSString *what)
{
	if (error != NULL) {
		*error = [NSError errorWithDomain:@"NSAppleScriptErrorDomain"
					     code:1
					 userInfo:@{ NSLocalizedDescriptionKey :
						     [NSString stringWithFormat:
							      @"NSAppleScript: %@ needs an OSA component and an "
							      @"AppleEvents transport, neither of which this system has",
							      what] }];
	}
}

@implementation NSAppleScript

/* THE INSTALL, AS A METHOD (batch 8). Both doors below are DESIGNATED in Apple's graph, and a designated initializer
 * may not chain to another initializer on `self` — so the state they share is written here instead of the URL door
 * routing through the source door. */
- (void)fnAdoptSource:(NSString *)source
{
	[_source release];
	_source = [source copy];
	_compiled = source != nil;
}

- (instancetype)initWithSource:(NSString *)source
{
	self = [super init];
	if (self != nil) {
		[self fnAdoptSource:source];
	}
	return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
	NSData *data;
	NSString *source;

	if (url == nil || ![url isFileURL]) {
		fn_script_error(error, @"-initWithContentsOfURL:error:");
		[self release];
		return nil;
	}
	data = [NSData dataWithContentsOfFile:[url path]];
	source = data != nil ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
	if (source == nil) {
		fn_script_error(error, @"-initWithContentsOfURL:error:");
		[self release];
		return nil;
	}
	self = [super init];
	if (self == nil) {
		return nil;
	}
	[self fnAdoptSource:source];
	return self;
}

- (void)dealloc
{
	[_source release];
	[super dealloc];
}

- (NSString *)source { return _source; }
- (BOOL)isCompiled { return _compiled; }
- (BOOL)compiled { return _compiled; }

- (id)copyWithZone:(NSZone *)zone
{
	return [[[self class] allocWithZone:zone] initWithSource:_source];
}

- (BOOL)compileAndReturnError:(NSError **)error
{
	if (_source == nil) {
		fn_script_error(error, @"-compileAndReturnError:");
		return NO;
	}
	_compiled = YES;
	return YES;
}

- (NSAppleEventDescriptor *)executeAndReturnError:(NSError **)error
{
	fn_script_error(error, @"-executeAndReturnError:");
	return nil;
}

- (NSAppleEventDescriptor *)executeAppleEvent:(NSAppleEventDescriptor *)event error:(NSError **)error
{
	(void)event;
	fn_script_error(error, @"-executeAppleEvent:error:");
	return nil;
}

@end
