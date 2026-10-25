/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * The two doors the three public predicate classes need from each other and from the format parser, and
 * nothing else: rendering an expression back to format text, and parsing one. Private on purpose — Apple
 * has the same two doors and does not publish them either.
 */

#ifndef FOUNDATION_FNPREDICATEPRIVATE_H
#define FOUNDATION_FNPREDICATEPRIVATE_H

#import <Foundation/NSExpression.h>
#import <Foundation/NSPredicate.h>

@class NSArray;
@class NSString;

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSExpression (FNPrivate)
- (NSString *)fn_expressionFormat;
@end

/* Parses a format string and returns the predicate it names. `arguments` supplies `%@`, `%K`, `%d`, `%f`
 * and `%i` substitutions in order. Raises NSInvalidArgumentException, naming the offset, on text it cannot
 * honour — never returns a predicate that means something else. */
NSPredicate *FNParsePredicateFormat(NSString *format, NSArray *arguments);

#endif /* FOUNDATION_FNPREDICATEPRIVATE_H */
