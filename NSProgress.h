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
 * **PUBLISHING IS IN-PROCESS, AND THAT IS SAID AT THE DOORS.** `-publish`, `-unpublish`,
 * `+addSubscriberForFileURL:withPublishingHandler:` and `+removeSubscriber:` are 10.9 macOS surface (the manifest
 * records their era), and this system has no cross-process progress service: a published object is announced to the
 * subscribers registered in THIS process, under the file URL in `NSProgressFileURLKey`. That is the same in-process
 * boundary NSFileCoordinator states, and it is observable — the handler is called, it returns an unpublishing block,
 * and `-unpublish` calls it.
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
@class NSError;
@class NSProgress;
@class NSURL;

/* "The key for a URL in the userInfo dictionary" — what a published progress object is published UNDER, and therefore
 * what a subscriber registers for. */
extern NSString *const NSProgressFileURLKey;

/* THE PUBLISHING HANDLER'S SHAPE, which is Apple's: it is called with the progress being published and RETURNS an
 * unpublishing handler (or nil), which `-unpublish` calls. A publisher that has nothing to tear down returns nil. */
typedef void (^NSProgressUnpublishingHandler)(void);
typedef NSProgressUnpublishingHandler _Nullable (^NSProgressPublishingHandler)(NSProgress *progress);

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
	BOOL _published;
	NSMutableArray *_unpublishingHandlers;	/* one per subscriber that answered publish */
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

/* THE PUBLISHING PAIR (10.9): `-publish` announces this object to this process's subscribers for its
 * `NSProgressFileURLKey` URL, and `-unpublish` calls the unpublishing handlers they returned. Publishing without that
 * key refuses by name, because there is no URL to publish under. */
- (void)publish NS_AVAILABLE_MAC(10_9);
- (void)unpublish NS_AVAILABLE_MAC(10_9);

/* "Whether the progress object is old" — NO: that flag distinguishes an object published by a system service's legacy
 * mechanism from one this process created, and there is no such service here. */
- (BOOL)isOld NS_AVAILABLE_MAC(10_9);

- (void)cancel;
- (void)pause;
- (void)resume NS_AVAILABLE_MAC(10_11);

@property (readonly) double fractionCompleted;
@property (readonly, getter=isIndeterminate) BOOL indeterminate;
@property (readonly, copy) NSDictionary<NSString *, id> *userInfo;
- (void)setUserInfoObject:(nullable id)objectOrNil forKey:(NSString *)key;

/* THE SUBSCRIBER REGISTRY (10.9), process-wide: a subscriber holds a file URL and a handler, and the handler is called
 * when a progress object with that URL is published. The class methods are Apple's shape — a token is returned and
 * handed back to `+removeSubscriber:` — and a nil URL or a nil handler registers nothing and returns nil. */
+ (id)addSubscriberForFileURL:(NSURL *)url
	 withPublishingHandler:(NSProgressPublishingHandler)publishingHandler NS_AVAILABLE_MAC(10_9);
+ (void)removeSubscriber:(id)subscriber NS_AVAILABLE_MAC(10_9);

@end

/* **THE PROTOCOL IS ONE PROPERTY.** A class that reports progress adopts it so a caller can ask for the object without
 * knowing the class; `NSURLSessionTask`, `NSFileCoordinator` and the extension request all conform in 10.11. */
@protocol NSProgressReporting <NSObject>
@property (readonly) NSProgress *progress;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSPROGRESS_H */
