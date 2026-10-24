/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSCondition.h — the condition lock (10.5).
 *
 * THE BODY WAS HERE ALL ALONG UNDER ANOTHER NAME. §63.170 cut this 10.5 class against the tree's then-10.2 baseline
 * and re-homed its implementation as `FNCondition`, which NSOperation and NSTask wait on. The census measures the
 * 10.6 surface, so the public class is restored ON TOP of that body rather than written a second time: `NSCondition`
 * is the implementation, and `FNCondition` is now an empty subclass kept for the files that name it.
 *
 * THE CONTRACT IS NSLocking PLUS THE WAIT: `-lock`/`-unlock` bracket the predicate, `-wait` releases the lock and
 * sleeps until `-signal`/`-broadcast` (or the deadline), and returns with the lock held again. `-name` is
 * diagnostic only.
 */
#ifndef FOUNDATION_NSCONDITION_H
#define FOUNDATION_NSCONDITION_H

#import <Foundation/NSObject.h>
#import <Foundation/NSLock.h>

@class NSDate;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(NSCondition)
@interface NSCondition : NSObject <NSLocking>
{
@private
	void *_mutex;
	void *_condition;
	NSString *_name;
}

- (void)wait;
- (BOOL)waitUntilDate:(NSDate *)limit;
- (void)signal;
- (void)broadcast;

@property (nullable, copy) NSString *name;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSCONDITION_H */
