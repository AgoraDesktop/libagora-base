/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSExtensionContext.h — the HOST side of an extension conversation (10.10), in Apple's own file.
 *
 * There is no extension process on this system, so the three request doors REFUSE BY NAME and still answer their
 * completion handlers (with NO, or by cancelling what was never started) — a caller that waits for a handler must not
 * wait forever. The facts are unchanged from W4a's combined header; W7 only gives the class the name Apple gives it.
 */
#ifndef FOUNDATION_NSEXTENSIONCONTEXT_H
#define FOUNDATION_NSEXTENSIONCONTEXT_H

#import <Foundation/NSObject.h>

@class NSArray;
@class NSError;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSExtensionContext : NSObject
{
@private
	NSArray *_inputItems;
}

/* THE ITEMS THE HOST HANDED OVER. A bare context has none, and a context created by an extension's host would be
 * filled by a process this system does not launch. */
@property (readonly, copy) NSArray *inputItems;

/* THE THREE REQUESTS, ALL REFUSED BY NAME (the census counts each). The handlers are still called, because that is
 * what a caller observes; the return values are the documented "nothing happened" answers. */
- (void)completeRequestReturningItems:(nullable NSArray *)items
		    completionHandler:(nullable void (^)(BOOL expired))completionHandler;
- (void)cancelRequestWithError:(NSError *)error;
- (void)openURL:(NSURL *)URL completionHandler:(nullable void (^)(BOOL success))completionHandler;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSEXTENSIONCONTEXT_H */
