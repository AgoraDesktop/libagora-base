/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSURLQueryItem.h — one name/value pair of a query string (10.10).
 *
 * **THE PAIR IS DECODED, AND THAT IS THE WHOLE CONTRACT.** Apple's header is explicit: "the name and value strings
 * of a query name-value pair are not percent encoded". A caller building `?q=a%20b` writes `name: @"q"`,
 * `value: @"a b"`; the percent-encoding happens when `NSURLComponents` renders `-query`. Holding encoded text here
 * and decoding it on the way out would make `-value` disagree with the string the caller passed, which is the bug
 * this note exists to keep out.
 *
 * `NSSecureCoding` and `NSCopying` are Apple's conformances, and both are real: an archived query item is decoded
 * with an allow-list, and a copied one is a distinct object with the same two strings.
 */

#ifndef FOUNDATION_NSURLQUERYITEM_H
#define FOUNDATION_NSURLQUERYITEM_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSURLQueryItem : NSObject <NSSecureCoding, NSCopying>
{
	NSString *_name;
	NSString *_value;	/* nullable: `?flag` has a name and no value */
}

/* THE DESIGNATED INITIALIZER. `value` may be nil — `?flag` is a name with no `=` — and it is stored as given. */
- (instancetype)initWithName:(NSString *)name value:(nullable NSString *)value NS_DESIGNATED_INITIALIZER;

+ (instancetype)queryItemWithName:(NSString *)name value:(nullable NSString *)value;

@property (readonly) NSString *name;
@property (nullable, readonly) NSString *value;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSURLQUERYITEM_H */
