/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_progress.m — THE OBSERVATION CONTRACT, NOT THE TWO INTEGERS.
 *
 * NSProgress exists so a caller can watch it, so the probe asks the questions a caller asks: does
 * `fractionCompleted` change when the inputs do, does KVO hear about it, does `+currentProgress` find the object a
 * thread became current with, does a child's fraction move its PARENT by the child's share (and not by its integers),
 * and does `-cancel` reach the leaves.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

/* THE OBSERVER ONLY COUNTS. It is registered for the two derived keys, which is what the manual will/did pair is for. */
@interface FNObserver : NSObject
{
@public
	int fractionChanges;
	int completedChanges;
	int indeterminateChanges;
}
@end

@implementation FNObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
	(void)object; (void)change; (void)context;
	if ([keyPath isEqualToString:@"fractionCompleted"]) fractionChanges++;
	if ([keyPath isEqualToString:@"completedUnitCount"]) completedChanges++;
	if ([keyPath isEqualToString:@"indeterminate"]) indeterminateChanges++;
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:10];
	NSProgress *parent = [NSProgress progressWithTotalUnitCount:10];
	NSProgress *child = [NSProgress progressWithTotalUnitCount:10];
	NSProgress *leaf;
	FNObserver *observer;
	NSProgress *current;
	NSProgress *nested;

	/* INDETERMINATE IS A NEGATIVE TOTAL, AND THE FRACTION IS DERIVED. */
	check([progress isIndeterminate] == NO, "a positive total is determinate");
	check([progress fractionCompleted] == 0.0, "nothing completed yet");
	[progress setCompletedUnitCount:5];
	check([progress fractionCompleted] == 0.5, "half done");
	check([progress isIndeterminate] == NO, "still determinate");

	/* THE ANNOUNCEMENTS: ONE COMPLETED WRITE TELLS OBSERVERS ABOUT THE COUNT AND THE FRACTION. */
	observer = [[FNObserver alloc] init];
	[progress addObserver:observer forKeyPath:@"fractionCompleted" options:0 context:NULL];
	[progress addObserver:observer forKeyPath:@"completedUnitCount" options:0 context:NULL];
	[progress addObserver:observer forKeyPath:@"indeterminate" options:0 context:NULL];
	[progress setCompletedUnitCount:8];
	check(observer->completedChanges == 1, "the completed count is announced once");
	check(observer->fractionChanges == 1, "and so is the fraction, once");
	[progress setTotalUnitCount:-1];
	check(observer->indeterminateChanges == 1, "becoming indeterminate is announced");
	check([progress isIndeterminate], "and the object says so");
	[progress removeObserver:observer forKeyPath:@"fractionCompleted"];
	[progress removeObserver:observer forKeyPath:@"completedUnitCount"];
	[progress removeObserver:observer forKeyPath:@"indeterminate"];
	[observer release];

	/* THE PER-THREAD STACK: BECOME, FIND, RESIGN. */
	check([NSProgress currentProgress] == nil, "nothing is current on a fresh thread");
	[parent becomeCurrentWithPendingUnitCount:10];
	check([NSProgress currentProgress] == parent, "+currentProgress finds what became current");
	nested = [NSProgress progressWithTotalUnitCount:4];
	[parent resignCurrent];
	check([NSProgress currentProgress] == nil, "and resigning leaves nothing current");
	check(nested != nil, "a nested object can be made while one is current");

	/* THE CHILD'S SHARE: 50% OF A 5-UNIT SHARE MOVES THE PARENT BY 2, NOT BY 5. */
	[parent setCompletedUnitCount:0];
	[parent addChild:child withPendingUnitCount:5];
	[child setCompletedUnitCount:5];
	check([parent completedUnitCount] == 2, "half of a five-unit share is two units");
	[child setCompletedUnitCount:10];
	check([parent completedUnitCount] == 5, "and a finished child fills exactly its share");

	/* CANCELLATION GOES DOWN. */
	leaf = [NSProgress progressWithTotalUnitCount:1];
	[parent addChild:leaf withPendingUnitCount:5];
	[parent cancel];
	check([parent isCancelled], "the cancelled object is cancelled");
	check([leaf isCancelled], "and so is its child");
	check([child isCancelled], "and its other child");

	/* USER INFO IS A MUTABLE DICTIONARY UNDER A READONLY PROPERTY. */
	[progress setUserInfoObject:@"value" forKey:@"key"];
	check([[[progress userInfo] objectForKey:@"key"] isEqualToString:@"value"], "user info carries an object");
	[progress setUserInfoObject:nil forKey:@"key"];
	check([[progress userInfo] objectForKey:@"key"] == nil, "and removing it removes it");

	printf("foundation_10_11_progress: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
