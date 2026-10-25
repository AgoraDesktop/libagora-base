/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSProgress.h — reported work, as a tree (10.9).
 *
 * **THE CONTRACT IS OBSERVATION, NOT BOOKKEEPING.** A progress object exists so a UI can watch it: `fractionCompleted`
 * and `indeterminate` change under KVO, `-cancel` travels DOWN the tree and the cancellation handler runs UP it, and
 * `-becomeCurrentWithPendingUnitCount:` puts the object on a per-thread stack so that work started without being handed
 * the object can still find it with `+currentProgress`. A class that only stored two integers would satisfy a header
 * diff and fail every caller, which is why the plan puts this class early and why the probe measures the announcements.
 *
 * **WHAT IS NOT HERE, AND WHY.** `-publish`, `-unpublish`, `+addSubscriberForFileURL:withPublishingHandler:` and
 * `+removeSubscriber:` are declared for iOS in this SDK (they have no macOS introduction version); they are not part
 * of the macOS surface this reference measures, so they are not declared here — an omission with a reason, not a
 * refusal. Everything else in Apple's 10.11 macOS list is present.
 *
 * The designated initializer is Apple's `-initWithParent:userInfo:`, which is also the only way to make a child.
 */

#ifndef FOUNDATION_NSPROGRESS_H
#define FOUNDATION_NSPROGRESS_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSMutableArray;

NS_CLASS_AVAILABLE_MAC(10_9)
@interface NSProgress : NSObject
{
	int64_t _totalUnitCount;
	int64_t _completedUnitCount;
	int64_t _pendingUnitCount;		/* this object's share of its PARENT, in the parent's units */
	BOOL _cancellable;
	BOOL _pausable;
	BOOL _cancelled;
	BOOL _paused;
	NSString *_kind;
	NSString *_localizedDescription;
	NSString *_localizedAdditionalDescription;
	NSMutableDictionary *_userInfo;
	NSProgress *_parent;			/* NOT retained: the tree's root outlives its children */
	NSMutableArray *_children;		/* retained */
}

/* THE DESIGNATED INITIALIZER, and the only one: a progress object with no parent is a root, which is what the
 * convenience constructors make. */
- (instancetype)initWithParent:(nullable NSProgress *)parentProgressOrNil
                      userInfo:(nullable NSDictionary *)userInfoOrNil NS_DESIGNATED_INITIALIZER;

+ (NSProgress *)currentProgress;
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount;
+ (NSProgress *)discreteProgressWithTotalUnitCount:(int64_t)unitCount NS_AVAILABLE_MAC(10_11);
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount
                                    parent:(nullable NSProgress *)parent
                         pendingUnitCount:(int64_t)unitCount NS_AVAILABLE_MAC(10_11);

/* THE PER-THREAD STACK. -becomeCurrent... registers the receiver for the CURRENT thread; -resignCurrent pops it. A
 * child created while the receiver is current becomes its child with the pending count it was created with. */
- (void)becomeCurrentWithPendingUnitCount:(int64_t)unitCount;
- (void)resignCurrent;
- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)unitCount NS_AVAILABLE_MAC(10_11);

@property int64_t totalUnitCount;
@property int64_t completedUnitCount;
@property (copy) NSString *kind;
@property (copy) NSString *localizedDescription;
@property (copy) NSString *localizedAdditionalDescription;

@property (getter=isCancellable) BOOL cancellable;
@property (getter=isPausable) BOOL pausable;
@property (readonly, getter=isCancelled) BOOL cancelled;
@property (readonly, getter=isPaused) BOOL paused;

- (void)cancel;
- (void)pause;
- (void)resume NS_AVAILABLE_MAC(10_11);

@property (readonly) double fractionCompleted;
@property (readonly, getter=isIndeterminate) BOOL indeterminate;
@property (readonly, copy) NSDictionary<NSString *, id> *userInfo;
- (void)setUserInfoObject:(nullable id)objectOrNil forKey:(NSString *)key;

@end

/* **THE PROTOCOL IS ONE PROPERTY.** A class that reports progress adopts it so a caller can ask for the object without
 * knowing the class; `NSURLSessionTask`, `NSFileCoordinator` and the extension request all conform in 10.11. */
@protocol NSProgressReporting <NSObject>
@property (readonly) NSProgress *progress;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSPROGRESS_H */
