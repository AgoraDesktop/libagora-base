/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSComparisonMethods.m — the two comparison categories on NSObject.
 *
 * THE ORDERING DOORS ALL ROUTE THROUGH `-compare:`, WHICH IS APPLE'S CONTRACT rather than a choice made here: a
 * class that wants to be comparable implements `-compare:`, and these doors give the six spellings of the answer.
 * A class with no `-compare:` raises through the same message send it would have raised anyway, which is why there
 * is no second, quieter fallback — a silent "not equal, so less than" would turn a programming error into an
 * ordering.
 *
 * `-isLike:` IS A WILDCARD MATCH, NOT A REGEX: `*` matches any run (including empty) and `?` matches one character.
 * That is Apple's scripting pattern language, and it is implemented with the usual two-pointer backtracking scan so
 * that a pattern like `*a*b*c*` cannot go exponential.
 */

#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <wctype.h>

static NSComparisonResult fn_compare(id receiver, id object)
{
	typedef NSComparisonResult (*fn_compare_method)(id, SEL, id);
	SEL sel = @selector(compare:);

	if (receiver == object) {
		return NSOrderedSame;
	}
	if (receiver == nil) {
		return NSOrderedAscending;
	}
	if (object == nil) {
		return NSOrderedDescending;
	}
	if (![receiver respondsToSelector:sel]) {
		/* The message send below would raise; doing it explicitly names the reason rather than the selector. */
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ does not implement -compare:, so it cannot be ordered against %@",
				   [receiver class], [object class]];
	}
	return ((fn_compare_method)[receiver methodForSelector:sel])(receiver, sel, object);
}

/* THE PATTERN SCAN. `star` remembers the last `*` and the position it matched from; on a mismatch the scan
 * backtracks to that star and consumes one more receiver character. Linear in practice, and bounded by the two
 * indexes for a pattern of stars. */
static unichar fn_fold_case(unichar character)
{
	return (unichar)towlower((wint_t)character);
}

static BOOL fn_wildcard_match(const unichar *string, NSUInteger length,
			      const unichar *pattern, NSUInteger patternLength, BOOL caseSensitive)
{
	NSUInteger s = 0, p = 0, star = NSNotFound, mark = 0;

	while (s < length) {
		unichar patternCharacter = (p < patternLength) ? pattern[p] : 0;
		unichar stringCharacter = string[s];
		BOOL literalMatch;

		if (caseSensitive) {
			literalMatch = (patternCharacter == stringCharacter);
		} else {
			literalMatch = (fn_fold_case(patternCharacter) == fn_fold_case(stringCharacter));
		}
		if (p < patternLength && (patternCharacter == '?' || literalMatch)) {
			s++;
			p++;
			continue;
		}
		if (p < patternLength && pattern[p] == '*') {
			star = p++;
			mark = s;
			continue;
		}
		if (star != NSNotFound) {
			p = star + 1;
			s = ++mark;
			continue;
		}
		return NO;
	}
	while (p < patternLength && pattern[p] == '*') {
		p++;
	}
	return p == patternLength;
}

static BOOL fn_is_like(id receiver, NSString *pattern, BOOL caseSensitive)
{
	NSString *text = [receiver isKindOfClass:[NSString class]] ? (NSString *)receiver : [receiver description];
	unichar *stringBuffer;
	unichar *patternBuffer;
	NSUInteger length, patternLength;
	BOOL matches;

	if (pattern == nil) {
		return NO;
	}
	length = [text length];
	patternLength = [pattern length];
	stringBuffer = malloc(sizeof(unichar) * (length + 1));
	patternBuffer = malloc(sizeof(unichar) * (patternLength + 1));
	if (stringBuffer == NULL || patternBuffer == NULL) {
		free(stringBuffer);
		free(patternBuffer);
		return NO;
	}
	[text getCharacters:stringBuffer range:NSMakeRange(0, length)];
	[pattern getCharacters:patternBuffer range:NSMakeRange(0, patternLength)];
	matches = fn_wildcard_match(stringBuffer, length, patternBuffer, patternLength, caseSensitive);
	free(stringBuffer);
	free(patternBuffer);
	return matches;
}

@implementation NSObject (NSComparisonMethods)

- (BOOL)isEqualTo:(id)object
{
	return [self isEqual:object];
}

- (BOOL)isNotEqualTo:(id)object
{
	return ![self isEqual:object];
}

- (BOOL)isLessThan:(id)object
{
	return fn_compare(self, object) == NSOrderedAscending;
}

- (BOOL)isLessThanOrEqualTo:(id)object
{
	return fn_compare(self, object) != NSOrderedDescending;
}

- (BOOL)isGreaterThan:(id)object
{
	return fn_compare(self, object) == NSOrderedDescending;
}

- (BOOL)isGreaterThanOrEqualTo:(id)object
{
	return fn_compare(self, object) != NSOrderedAscending;
}

- (BOOL)isLike:(NSString *)object
{
	return fn_is_like(self, object, YES);
}

- (BOOL)isCaseInsensitiveLike:(NSString *)object
{
	return fn_is_like(self, object, NO);
}

- (BOOL)doesContain:(id)object
{
	if ([self isKindOfClass:[NSString class]]) {
		return [(NSString *)self rangeOfString:[object description]].location != NSNotFound;
	}
	if ([self isKindOfClass:[NSArray class]]) {
		return [(NSArray *)self containsObject:object];
	}
	if ([self isKindOfClass:[NSSet class]]) {
		return [(NSSet *)self containsObject:object];
	}
	if ([self isKindOfClass:[NSDictionary class]]) {
		return [(NSDictionary *)self objectForKey:object] != nil;
	}
	return NO;
}

@end

@implementation NSObject (NSScriptingComparisonMethods)

- (BOOL)scriptingIsEqualTo:(id)object
{
	return [self isEqualTo:object];
}

- (BOOL)scriptingIsNotEqualTo:(id)object
{
	return [self isNotEqualTo:object];
}

- (BOOL)scriptingIsLessThan:(id)object
{
	return [self isLessThan:object];
}

- (BOOL)scriptingIsLessThanOrEqualTo:(id)object
{
	return [self isLessThanOrEqualTo:object];
}

- (BOOL)scriptingIsGreaterThan:(id)object
{
	return [self isGreaterThan:object];
}

- (BOOL)scriptingIsGreaterThanOrEqualTo:(id)object
{
	return [self isGreaterThanOrEqualTo:object];
}

- (BOOL)scriptingBeginsWith:(NSString *)object
{
	NSString *text = [self isKindOfClass:[NSString class]] ? (NSString *)self : [self description];

	return [text hasPrefix:object];
}

- (BOOL)scriptingEndsWith:(NSString *)object
{
	NSString *text = [self isKindOfClass:[NSString class]] ? (NSString *)self : [self description];

	return [text hasSuffix:object];
}

- (BOOL)scriptingContains:(NSString *)object
{
	return [self doesContain:object];
}

@end
