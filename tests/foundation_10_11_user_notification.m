/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_user_notification.m — THE NOTIFICATION VALUE, ITS ACTION, AND AN IN-PROCESS CENTRE (10.8–10.10).
 *
 * Nothing presents a notification on this system, so what is measured is the state a caller can observe: the value's
 * copied doors and its copy, the action's pair, the centre's scheduled list, its delegate consultation, and the fact
 * that DELIVERY REFUSES rather than claiming success.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSUserNotification.h>
#import <Foundation/NSUserNotificationCenter.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

@interface CenterProbe : NSObject <NSUserNotificationCenterDelegate>
{
@public
	int consulted;
	BOOL answer;
}
@end

@implementation CenterProbe
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
	shouldPresentNotification:(NSUserNotification *)notification
{
	(void)center;
	(void)notification;
	consulted++;
	return answer;
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ---- the value: copied doors, a copy, and Apple's activation values ---- */
	{
		NSUserNotification *notification = [[[NSUserNotification alloc] init] autorelease];
		NSMutableDictionary *userInfo = [[[NSMutableDictionary alloc] init] autorelease];
		NSUserNotification *copy;

		[userInfo setObject:@"v" forKey:@"k"];
		[notification setTitle:@"Title"];
		[notification setIdentifier:@"id-1"];
		[notification setUserInfo:userInfo];
		[notification setHasActionButton:YES];
		[notification setHasReplyButton:YES];
		[userInfo setObject:@"changed" forKey:@"k"];
		check([[[notification userInfo] objectForKey:@"k"] isEqualToString:@"v"],
		      "userInfo is copied on the way in");
		check([[notification title] isEqualToString:@"Title"] &&
		      [[notification identifier] isEqualToString:@"id-1"] &&
		      [notification hasActionButton] && [notification hasReplyButton],
		      "the string and switch doors read back");
		check(![notification isPresented] && ![notification isRemote] &&
		      [notification activationType] == NSUserNotificationActivationTypeNone,
		      "a new notification is not presented, not remote, and not activated");
		copy = [notification copy];
		check(copy != notification && [[copy title] isEqualToString:@"Title"] &&
		      [[copy userInfo] isEqual:[notification userInfo]], "a copy carries the same values");
		[copy release];
		check(NSUserNotificationActivationTypeNone == 0 && NSUserNotificationActivationTypeContentsClicked == 1 &&
		      NSUserNotificationActivationTypeActionButtonClicked == 2 &&
		      NSUserNotificationActivationTypeReplied == 3 &&
		      NSUserNotificationActivationTypeAdditionalActionClicked == 4,
		      "the activation constants carry Apple's numbers");

		{
			NSUserNotificationAction *action = [NSUserNotificationAction actionWithIdentifier:@"a"
												   title:@"Open"];
			NSUserNotificationAction *actionCopy = [action copy];

			check([[action identifier] isEqualToString:@"a"] && [[action title] isEqualToString:@"Open"],
			      "an action carries its identifier and title");
			check(actionCopy != action && [[actionCopy title] isEqualToString:@"Open"], "and copies");
			[actionCopy release];
		}
	}

	/* ---- the centre: state, the delegate, and a refusal ---- */
	{
		NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
		NSUserNotification *one = [[[NSUserNotification alloc] init] autorelease];
		NSUserNotification *two = [[[NSUserNotification alloc] init] autorelease];
		CenterProbe *probe = [[[CenterProbe alloc] init] autorelease];

		check(center == [NSUserNotificationCenter defaultUserNotificationCenter], "the centre is a singleton");
		[center setScheduledNotifications:nil];
		[center scheduleNotification:one];
		check([[center scheduledNotifications] count] == 1 &&
		      [[[center scheduledNotifications] objectAtIndex:0] isEqual:one], "scheduling keeps the notification");
		[center scheduleNotification:two];
		[center removeScheduledNotification:one];
		check([[center scheduledNotifications] count] == 1 &&
		      [[[center scheduledNotifications] objectAtIndex:0] isEqual:two], "removal drops the named one");
		[center setScheduledNotifications:[NSArray arrayWithObject:one]];
		check([[center scheduledNotifications] count] == 1 &&
		      [[[center scheduledNotifications] objectAtIndex:0] isEqual:one], "the scheduled list can be replaced");
		[center setDelegate:probe];
		check([center delegate] == probe, "the delegate reads back");
		probe->answer = NO;
		[center deliverNotification:one];
		check(probe->consulted == 1, "delivery consults the delegate");
		check([[center deliveredNotifications] count] == 0,
		      "and does not record a delivery, because nothing was delivered");
		[center removeDeliveredNotification:one];
		[center removeAllDeliveredNotifications];
		check([[center deliveredNotifications] count] == 0, "the delivered list stays empty");
		[center setDelegate:nil];
		check([center delegate] == nil, "and is cleared with nil");
	}

	printf("foundation_10_11_user_notification: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
