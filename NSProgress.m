/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSProgress.m — the tree, the announcements, and the two directions cancellation travels.
 *
 * **A CHILD'S PROGRESS IS ITS PARENT'S, IN THE PARENT'S UNITS.** `-addChild:withPendingUnitCount:` gives the child a
 * share of the parent's remaining work; when the child's `completedUnitCount` moves, the parent's moves by the same
 * FRACTION of that share. That is why the parent does not simply add the child's integers: a child that counts bytes
 * inside a parent that counts files would otherwise finish the parent on its first write.
 *
 * **CANCELLATION GOES DOWN, THE HANDLER GOES UP.** `-cancel` marks the receiver and every descendant, so one call from
 * the UI reaches the leaves; `-cancellationHandler` runs once, at the object the caller cancelled, because that is the
 * object whose work the handler knows how to abandon. Both directions are measured by the probe.
 *
 * **THE ANNOUNCEMENTS ARE MANUAL AND THAT IS DELIBERATE.** `fractionCompleted` and `indeterminate` are derived — they
 * have no setter for KVO's automatic wrapper to bracket — so the setters that change the inputs announce them: a
 * `completedUnitCount` write tells observers about itself AND about the fraction; a `totalUnitCount` write tells them
 * about the fraction and about whether the object stopped being indeterminate.
 */

#import <Foundation/NSProgress.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSException.h>

/* THE CURRENT-PROGRESS STACK IS PER THREAD, because two threads are two pieces of work. The key is the thread object
 * itself, so the stack dies with it and a thread that never becomes current pays nothing. */
static NSString *const FNProgressStackKey = @"FNProgressStack";

static NSMutableArray *fn_progress_stack(BOOL create)
{
	NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
	NSMutableArray *stack = [threadDictionary objectForKey:FNProgressStackKey];

	if (stack == nil && create) {
		stack = [NSMutableArray array];
		[threadDictionary setObject:stack forKey:FNProgressStackKey];
	}
	return stack;
}

@implementation NSProgress

- (instancetype)init
{
	return [self initWithParent:nil userInfo:nil];
}

- (instancetype)initWithParent:(nullable NSProgress *)parentProgressOrNil userInfo:(nullable NSDictionary *)userInfoOrNil
{
	self = [super init];
	if (self != nil) {
		_totalUnitCount = -1;		/* -1 is Apple's "unknown", which is what makes an object indeterminate */
		_completedUnitCount = 0;
		_cancellable = YES;
		_kind = [@"" copy];
		_localizedDescription = [@"" copy];
		_localizedAdditionalDescription = [@"" copy];
		_userInfo = [[NSMutableDictionary alloc] initWithDictionary:(userInfoOrNil ?: @{})];
		_parent = parentProgressOrNil;	/* unretained by contract */
		if (parentProgressOrNil != nil) {
			NSMutableArray *siblings = parentProgressOrNil->_children;

			if (siblings == nil) {
				siblings = [[NSMutableArray alloc] init];
				parentProgressOrNil->_children = siblings;
				[siblings release];
			}
			[siblings addObject:self];	/* the parent retains the child */
		}
	}
	return self;
}

- (void)dealloc
{
	[_children release];
	[_userInfo release];
	[_kind release];
	[_localizedDescription release];
	[_localizedAdditionalDescription release];
	[super dealloc];
}

+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount
{
	NSProgress *progress = [[[self alloc] initWithParent:nil userInfo:nil] autorelease];

	[progress setTotalUnitCount:unitCount];
	return progress;
}

+ (NSProgress *)discreteProgressWithTotalUnitCount:(int64_t)unitCount
{
	/* A discrete progress reports only its own work; the spelling exists so a caller can say so. The tree above it is
	 * unaffected either way, because nothing is current at creation time. */
	return [self progressWithTotalUnitCount:unitCount];
}

+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount
                                    parent:(nullable NSProgress *)parent
                         pendingUnitCount:(int64_t)pending
{
	NSProgress *progress = [[[self alloc] initWithParent:parent userInfo:nil] autorelease];

	progress->_pendingUnitCount = pending;
	[progress setTotalUnitCount:unitCount];
	return progress;
}

+ (NSProgress *)currentProgress
{
	NSMutableArray *stack = fn_progress_stack(NO);

	return [stack lastObject];
}

- (void)becomeCurrentWithPendingUnitCount:(int64_t)unitCount
{
	_pendingUnitCount = unitCount;
	[fn_progress_stack(YES) addObject:self];
}

- (void)resignCurrent
{
	NSMutableArray *stack = fn_progress_stack(NO);

	if ([stack lastObject] == self) {
		[stack removeLastObject];
	}
}

- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)unitCount
{
	NSProgress *oldParent;

	if (child == nil || child == self) {
		return;
	}
	oldParent = child->_parent;
	if (oldParent != nil) {
		[oldParent->_children removeObjectIdenticalTo:child];
	}
	child->_parent = self;
	child->_pendingUnitCount = unitCount;
	if (_children == nil) {
		_children = [[NSMutableArray alloc] init];
	}
	[_children addObject:child];
}

/* THE FRACTION IS DERIVED, AND -1 TOTAL MEANS INDETERMINATE. */
- (double)fractionCompleted
{
	if (_totalUnitCount <= 0) {
		return 0.0;
	}
	return (double)_completedUnitCount / (double)_totalUnitCount;
}

- (BOOL)isIndeterminate
{
	return _totalUnitCount <= 0;
}

- (int64_t)totalUnitCount { return _totalUnitCount; }

- (void)setTotalUnitCount:(int64_t)unitCount
{
	BOOL wasIndeterminate = [self isIndeterminate];

	/* THE STORED KEY IS AUTOMATICALLY WRAPPED: KVO moves an observed object to a subclass whose setter brackets this
	 * one, so a manual pair here would announce it TWICE — the bug `NSUserDefaults` documents from the other side. The
	 * two DERIVED keys have no setter of their own, so they are the ones the manual pair exists for. */
	[self willChangeValueForKey:@"fractionCompleted"];
	if (wasIndeterminate != (unitCount <= 0)) {
		[self willChangeValueForKey:@"indeterminate"];
	}
	_totalUnitCount = unitCount;
	if (wasIndeterminate != (unitCount <= 0)) {
		[self didChangeValueForKey:@"indeterminate"];
	}
	[self didChangeValueForKey:@"fractionCompleted"];
	[self fn_reportToParent];
}

- (int64_t)completedUnitCount { return _completedUnitCount; }

- (void)setCompletedUnitCount:(int64_t)unitCount
{
	int64_t delta = unitCount - _completedUnitCount;

	[self willChangeValueForKey:@"fractionCompleted"];
	_completedUnitCount = unitCount;
	[self didChangeValueForKey:@"fractionCompleted"];
	if (delta != 0) {
		[self fn_reportToParent];
	}
}

/* THE CHILD'S SHARE, EXPRESSED IN THE PARENT'S UNITS. The parent's own count is driven by its children's fractions, so
 * a child that reaches 100% moves the parent by exactly the pending count it was given — never more. */
- (void)fn_reportToParent
{
	double fraction;

	if (_parent == nil || _pendingUnitCount == 0) {
		return;
	}
	fraction = [self fractionCompleted];
	[_parent fn_setChildShare:self fraction:fraction];
}

- (void)fn_setChildShare:(NSProgress *)child fraction:(double)fraction
{
	double contributed = 0.0;
	int64_t newCount;
	NSUInteger i;

	for (i = 0; i < [_children count]; i++) {
		NSProgress *each = [_children objectAtIndex:i];
		double share = [each fractionCompleted] * (double)each->_pendingUnitCount;

		if (each == child) {
			share = fraction * (double)each->_pendingUnitCount;
		}
		contributed += share;
	}
	newCount = _completedUnitCount + (int64_t)(contributed - (double)_completedUnitCount);
	if (newCount != _completedUnitCount) {
		[self setCompletedUnitCount:newCount];
	}
}

- (NSString *)kind { return _kind; }
- (void)setKind:(NSString *)kind
{
	NSString *old = _kind;

	_kind = [kind copy];
	[old release];
}

- (NSString *)localizedDescription { return _localizedDescription; }
- (void)setLocalizedDescription:(NSString *)text
{
	NSString *old = _localizedDescription;

	_localizedDescription = [text copy];
	[old release];
}

- (NSString *)localizedAdditionalDescription { return _localizedAdditionalDescription; }
- (void)setLocalizedAdditionalDescription:(NSString *)text
{
	NSString *old = _localizedAdditionalDescription;

	_localizedAdditionalDescription = [text copy];
	[old release];
}

- (BOOL)isCancellable { return _cancellable; }
- (void)setCancellable:(BOOL)flag { _cancellable = flag; }
- (BOOL)isPausable { return _pausable; }
- (void)setPausable:(BOOL)flag { _pausable = flag; }
- (BOOL)isCancelled { return _cancelled; }
- (BOOL)isPaused { return _paused; }

/* DOWN THE TREE, ONCE EACH: a cancelled child re-cancelling its parent's other children would be a loop. */
- (void)cancel
{
	NSUInteger i;

	if (_cancelled) {
		return;
	}
	_cancelled = YES;	/* `cancelled` is readonly: there is no setter for the automatic wrapper to bracket */
	for (i = 0; i < [_children count]; i++) {
		[[_children objectAtIndex:i] cancel];
	}
}

- (void)pause
{
	if (!_pausable || _paused) {
		return;
	}
	_paused = YES;
}

- (void)resume
{
	if (!_paused) {
		return;
	}
	_paused = NO;
}

- (NSDictionary *)userInfo { return _userInfo; }

- (void)setUserInfoObject:(nullable id)object forKey:(NSString *)key
{
	if (object == nil) {
		[_userInfo removeObjectForKey:key];
	} else {
		[_userInfo setObject:object forKey:key];
	}
}

@end
