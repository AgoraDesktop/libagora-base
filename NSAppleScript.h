/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAppleScript.h — AppleScript source as an object, and the execution doors that refuse by name.
 *
 * The SOURCE is real: it is stored, compiled (a non-nil source is "compiled" in the sense that this library accepts
 * it) and answered. EXECUTION needs an OSA component and an AppleEvents transport, neither of which exists here, so
 * `-executeAndReturnError:` and `-executeAppleEvent:error:` answer nil with an error naming the missing subsystem.
 * That is the plan's F10 disposition, stated at the door rather than discovered at the first call.
 */
#ifndef FOUNDATION_NSAPPLESCRIPT_H
#define FOUNDATION_NSAPPLESCRIPT_H

#import <Foundation/NSObject.h>
#import <Foundation/NSAppleEventDescriptor.h>

@class NSURL;
@class NSDictionary;
@class NSError;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_2)
@interface NSAppleScript : NSObject <NSCopying>
{
@private
	NSString *_source;
	BOOL _compiled;
}

- (instancetype)initWithSource:(NSString *)source NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER;

@property (nullable, readonly, copy) NSString *source;
@property (readonly, getter=isCompiled) BOOL compiled;

- (BOOL)compileAndReturnError:(NSError **)error;
- (nullable NSAppleEventDescriptor *)executeAndReturnError:(NSError **)error;
- (nullable NSAppleEventDescriptor *)executeAppleEvent:(NSAppleEventDescriptor *)event error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSAPPLESCRIPT_H */
