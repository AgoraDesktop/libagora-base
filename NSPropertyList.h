/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPropertyList.h — the property-list FORMATS and the option types a read or write takes (W7), in Apple's own file.
 *
 * NSPropertyListSerialization.h is the class; these are the values it is asked with, and Apple gives them a header so a
 * caller that only names a format imports it. The raw values are Apple's, so a numeric comparison in existing code
 * still holds.
 */
#ifndef FOUNDATION_NSPROPERTYLIST_H
#define FOUNDATION_NSPROPERTYLIST_H

#import <Foundation/NSObjCRuntime.h>

NS_ASSUME_NONNULL_BEGIN

/* Apple's raw values, so a numeric comparison in existing code still holds. */
typedef enum {
	NSPropertyListOpenStepFormat = 1,
	NSPropertyListXMLFormat_v1_0 = 100,
	NSPropertyListBinaryFormat_v1_0 = 200
} NSPropertyListFormat;

typedef enum {
	NSPropertyListImmutable = 0,
	NSPropertyListMutableContainers = 1,
	NSPropertyListMutableContainersAndLeaves = 2
} NSPropertyListMutabilityOptions;

typedef NSUInteger NSPropertyListReadOptions;
typedef NSUInteger NSPropertyListWriteOptions;

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSPROPERTYLIST_H */
