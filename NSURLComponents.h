/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSURLComponents.h — Apple's name for the parser this library already had (10.9).
 *
 * **THE CLASS IS A DECLARATION, NOT A SECOND IMPLEMENTATION.** `FNURLComponents` is the RFC 3986 splitter `NSURL.m`
 * has used since the URL work landed: it parses, it renders, it percent-decodes on the way out and keeps the raw
 * octets it was given, and it resolves one components object against another. Everything measured against 10.11 is
 * therefore already answerable; what was missing was Apple's NAME and the three things only the public class needs.
 *
 * This is the plan's §4.3 decision, made before the class existed: "the internal type keeps its name; the public
 * header is a second declaration, not a rename, so NSURL.m's existing callers do not move." A subclass is the least
 * invasive spelling of that — the inherited doors are the inherited contract, and `-class` still answers
 * `NSURLComponents` to a caller who asks.
 *
 * **WHAT IS HERE AND WHAT IS NOT.** Added: `-init` (all components undefined), `-URLRelativeToURL:` (10.9),
 * `-queryItems` (10.10), and the six `percentEncoded…` setters (10.9) — the internal type only ever needed the
 * getters, because it always received raw text. The eight `rangeOf…` properties Apple added in 10.11 are here too:
 * they render once and scan once, in the order the grammar puts the components.
 */

#ifndef FOUNDATION_NSURLCOMPONENTS_H
#define FOUNDATION_NSURLCOMPONENTS_H

#import <Foundation/FNURLComponents.h>
#import <Foundation/NSURLQueryItem.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_9)
@interface NSURLComponents : FNURLComponents

/* ALL COMPONENTS UNDEFINED. Apple's designated initializer, and what `+components...` falls back to. */
- (instancetype)init;

/* THE RELATIVE FORM. `-URL` renders an absolute URL; this one keeps a relative path relative to `baseURL`. */
- (nullable NSURL *)URLRelativeToURL:(nullable NSURL *)baseURL;

/* THE SIX ENCODED SETTERS. `-setUser:` takes DECODED text and encodes it; these take text that is already encoded and
 * store it as given, which is what a caller who has a percent-encoded fragment in hand needs. */
- (void)setPercentEncodedUser:(nullable NSString *)user;
- (void)setPercentEncodedPassword:(nullable NSString *)password;
- (void)setPercentEncodedHost:(nullable NSString *)host;
- (void)setPercentEncodedPath:(nullable NSString *)path;
- (void)setPercentEncodedQuery:(nullable NSString *)query;
- (void)setPercentEncodedFragment:(nullable NSString *)fragment;

/* THE QUERY AS PAIRS (10.10). Reading splits the raw query on `&` and the first `=`, percent-decodes both halves, and
 * gives a name-only item (`?flag`) a nil value. Writing joins the pairs, encoding both halves, and a nil value writes
 * the name alone. */
@property (nullable, copy) NSArray<NSURLQueryItem *> *queryItems NS_AVAILABLE_MAC(10_10);

/* THE COMPONENT RANGES (10.11). Each is a range in the RENDERED string — `-string` — not in the parsed fields, and
 * `{NSNotFound, 0}` when the component is absent. Apple added them so a caller can highlight part of a URL without
 * re-parsing it; this class renders once and scans once, in the order the grammar puts the components. */
@property (readonly) NSRange rangeOfScheme NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfUser NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfPassword NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfHost NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfPort NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfPath NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfQuery NS_AVAILABLE_MAC(10_11);
@property (readonly) NSRange rangeOfFragment NS_AVAILABLE_MAC(10_11);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSURLCOMPONENTS_H */
