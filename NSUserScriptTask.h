/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSUserScriptTask.h — W5: THE SCRIPT-TASK FAMILY, DECLARED AND REFUSED BY NAME.
 *
 * A user script task runs an AppleScript or an Automator workflow through the OSA component and the Automator engine.
 * This system has neither (NSAppleScript.m records the same absence), so every door REFUSES: the two-argument
 * initialiser answers nil with an error, and each execute door calls its completion handler with a named error rather
 * than leaving a caller waiting for a script that will never start.
 */
#ifndef FOUNDATION_NSUSERSCRIPTTASK_H
#define FOUNDATION_NSUSERSCRIPTTASK_H

#import <Foundation/NSObject.h>

@class NSAppleEventDescriptor;
@class NSDictionary;
@class NSError;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSUserScriptTaskErrorDomain NS_AVAILABLE_MAC(10_8);

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSUserScriptTask : NSObject
{
@private
	NSURL *_scriptURL;
}
- (nullable instancetype)initWithURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER;
@property (nullable, readonly, copy) NSURL *scriptURL;
- (void)executeWithCompletionHandler:(nullable void (^)(NSError * _Nullable error))handler;
@end

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSUserAppleScriptTask : NSUserScriptTask
- (void)executeWithAppleEvent:(nullable NSAppleEventDescriptor *)event
	    completionHandler:(nullable void (^)(NSAppleEventDescriptor * _Nullable result,
						 NSError * _Nullable error))handler;
@end

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSUserAutomatorTask : NSUserScriptTask
{
@private
	NSDictionary *_variables;
}
@property (nullable, copy) NSDictionary *variables;
- (void)executeWithInput:(nullable id)input
       completionHandler:(nullable void (^)(id _Nullable result, NSError * _Nullable error))handler;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSUSERSCRIPTTASK_H */
