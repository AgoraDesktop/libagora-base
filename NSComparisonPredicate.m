/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSComparisonPredicate.m — the leaf of the format grammar and the only class that decides what "less than"
 * means for two objects.
 *
 * ORDERING IS ASKED FOR, NOT ASSUMED. Two objects that both answer `-compare:` are compared with it (strings,
 * dates, numbers); anything else falls back to `-doubleValue`, which is what makes `1 < 2.5` work when the
 * left side arrived as an NSNumber and the right as an unboxed literal. Comparing a string to a number is
 * therefore a numeric comparison rather than a type error — Apple's behaviour, and the reason a predicate over
 * a heterogeneous collection does not raise.
 *
 * THE TWO STRING MATCHERS ARE BUILT, NOT BORROWED: LIKE becomes a regular expression (`*`→`.*`, `?`→`.`),
 * and MATCHES is one already. Both go through NSRegularExpression, which this library has.
 *
 * `[d]` (diacritic-insensitive) IS A DOCUMENTED ADAPTATION: there is no folding pass in this string layer, so
 * the option is accepted and ignored rather than refused — refusing it would reject a predicate whose ASCII
 * behaviour is exactly right. COREDATA-PLAN.md §4.4 is where that kind of deviation is recorded.
 */

#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSDictionary.h>

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSRegularExpression.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>

static BOOL FNIsString(id v) { return (v != nil) && [v isKindOfClass:[NSString class]]; }

static BOOL FNBoolOf(id v)
{
	if (v == nil || v == (id)[NSNull null]) {
		return NO;
	}
	if ([v respondsToSelector:@selector(boolValue)]) {
		return [v boolValue];
	}
	return YES;
}

/* -compare: WHEN BOTH SIDES AGREE THEY HAVE ONE, -doubleValue OTHERWISE. */
static NSComparisonResult FNOrder(id l, id r)
{
	if (l == r) { return NSOrderedSame; }
	if (l == nil) { return NSOrderedAscending; }
	if (r == nil) { return NSOrderedDescending; }
	if (FNIsString(l) && FNIsString(r)) {
		return [(NSString *)l compare:(NSString *)r];
	}
	{
		double a = [l doubleValue];
		double b = [r doubleValue];
		if (a < b) { return NSOrderedAscending; }
		if (a > b) { return NSOrderedDescending; }
		return NSOrderedSame;
	}
}

static NSString *FNLower(id v)
{
	return FNIsString(v) ? [(NSString *)v lowercaseString] : nil;
}

/* LIKE's wildcards are `*` and `?`, and everything else in the operand is a literal — so the pattern is built
 * with its metacharacters escaped rather than pasted in. This is the same rule the SQL translator in
 * COREDATA-PLAN.md §8.2 follows for the same reason: an operand is data, not pattern. */
static NSString *FNPatternFromLike(NSString *like, BOOL literal)
{
	NSMutableString *pattern = [[NSMutableString alloc] init];
	NSUInteger i, n = [like length];

	if (!literal) { [pattern appendString:@"^"]; }
	for (i = 0; i < n; i++) {
		unichar c = [like characterAtIndex:i];
		if (!literal && c == '*') { [pattern appendString:@".*"]; }
		else if (!literal && c == '?') { [pattern appendString:@"."]; }
		else if (c == '\\' || c == '.' || c == '^' || c == '$' || c == '|' ||
		         c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' ||
		         c == '+' || c == '*' || c == '?') {
			[pattern appendString:@"\\"];
			[pattern appendFormat:@"%c", (char)c];
		} else {
			[pattern appendFormat:@"%c", (char)c];
		}
	}
	if (!literal) { [pattern appendString:@"$"]; }
	return [pattern autorelease];
}

static BOOL FNMatchesRegularExpression(NSString *subject, NSString *pattern, BOOL caseInsensitive)
{
	NSRegularExpressionOptions options = caseInsensitive ? NSRegularExpressionCaseInsensitive : 0;
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:NULL];
	NSRange r;

	if (re == nil) { return NO; }
	r = [re rangeOfFirstMatchInString:subject options:0 range:NSMakeRange(0, [subject length])];
	return r.location != NSNotFound;
}

@interface NSComparisonPredicate (FNPrivate)
- (BOOL)fn_compareLeft:(id)l right:(id)r;
@end

@implementation NSComparisonPredicate

+ (NSPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                              rightExpression:(NSExpression *)rhs
                                     modifier:(NSComparisonPredicateModifier)modifier
                                         type:(NSPredicateOperatorType)type
                                      options:(NSUInteger)options
{
	return [[[self alloc] initWithLeftExpression:lhs rightExpression:rhs modifier:modifier
	                                        type:type options:options] autorelease];
}

+ (NSPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                              rightExpression:(NSExpression *)rhs
                              customSelector:(SEL)selector
{
	return [[[self alloc] initWithLeftExpression:lhs rightExpression:rhs customSelector:selector] autorelease];
}

- (id)initWithLeftExpression:(NSExpression *)lhs
             rightExpression:(NSExpression *)rhs
                    modifier:(NSComparisonPredicateModifier)modifier
                        type:(NSPredicateOperatorType)type
                     options:(NSUInteger)options
{
	self = [super init];
	if (self != nil) {
		_lhs = [lhs retain];
		_rhs = [rhs retain];
		_modifier = modifier;
		_operatorType = type;
		_options = options;
	}
	return self;
}

- (id)initWithLeftExpression:(NSExpression *)lhs
             rightExpression:(NSExpression *)rhs
             customSelector:(SEL)selector
{
	self = [self initWithLeftExpression:lhs rightExpression:rhs modifier:NSDirectPredicateModifier
	                               type:NSCustomSelectorPredicateOperatorType options:0];
	if (self != nil) { _customSelector = selector; }
	return self;
}

- (void)dealloc
{
	[_lhs release];
	[_rhs release];
	[super dealloc];
}

- (NSPredicateOperatorType)predicateOperatorType { return _operatorType; }
- (NSComparisonPredicateModifier)comparisonPredicateModifier { return _modifier; }
- (NSExpression *)leftExpression { return _lhs; }
- (NSExpression *)rightExpression { return _rhs; }
- (SEL)customSelector { return _customSelector; }
- (NSUInteger)options { return _options; }

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	NSComparisonPredicate *p = [[NSComparisonPredicate allocWithZone:zone]
	                            initWithLeftExpression:_lhs rightExpression:_rhs
	                                          modifier:_modifier type:_operatorType options:_options];
	p->_customSelector = _customSelector;
	return p;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_lhs forKey:@"NSLeft"];
	[coder encodeObject:_rhs forKey:@"NSRight"];
	[coder encodeInteger:(NSInteger)_operatorType forKey:@"NSOperator"];
	[coder encodeInteger:(NSInteger)_modifier forKey:@"NSModifier"];
	[coder encodeInteger:(NSInteger)_options forKey:@"NSOptions"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	return [self initWithLeftExpression:[coder decodeObjectForKey:@"NSLeft"]
	                    rightExpression:[coder decodeObjectForKey:@"NSRight"]
	                           modifier:(NSComparisonPredicateModifier)[coder decodeIntegerForKey:@"NSModifier"]
	                               type:(NSPredicateOperatorType)[coder decodeIntegerForKey:@"NSOperator"]
	                            options:(NSUInteger)[coder decodeIntegerForKey:@"NSOptions"]];
}

- (BOOL)fn_compareLeft:(id)l right:(id)r
{
	BOOL caseInsensitive = ((_options & NSCaseInsensitivePredicateOption) != 0);

	switch (_operatorType) {
	case NSEqualToPredicateOperatorType:
		if (l == nil || r == nil) { return (l == r); }
		if (caseInsensitive && FNIsString(l) && FNIsString(r)) {
			return [FNLower(l) isEqualToString:FNLower(r)];
		}
		return [l isEqual:r];

	case NSNotEqualToPredicateOperatorType:
		/* ⚠ **THIS USED TO CALL ITSELF WITH THE SAME OPERATOR AND RECURSE FOR EVER.** `return ![self
		 * fn_compareLeft:l right:r]` switches on `_operatorType`, which is still NotEqual, so the first `!=` in
		 * any predicate overflowed the stack — found by a 10^5-row Core Data suite whose `department != nil` was
		 * the first `!=` the whole test corpus had ever evaluated (COREDATA-PLAN.md §0.13). The negation is
		 * computed here instead: equality is decided, then inverted. */
		{
			BOOL equal;

			if (l == nil || r == nil) {
				equal = (l == r);
			} else if (caseInsensitive && FNIsString(l) && FNIsString(r)) {
				equal = [FNLower(l) isEqualToString:FNLower(r)];
			} else {
				equal = [l isEqual:r];
			}
			return !equal;
		}

	case NSLessThanPredicateOperatorType:
		return FNOrder(l, r) == NSOrderedAscending;
	case NSLessThanOrEqualToPredicateOperatorType:
		return FNOrder(l, r) != NSOrderedDescending;
	case NSGreaterThanPredicateOperatorType:
		return FNOrder(l, r) == NSOrderedDescending;
	case NSGreaterThanOrEqualToPredicateOperatorType:
		return FNOrder(l, r) != NSOrderedAscending;

	case NSBeginsWithPredicateOperatorType:
	case NSEndsWithPredicateOperatorType: {
		NSString *a, *b;
		if (!FNIsString(l) || !FNIsString(r)) { return NO; }
		a = caseInsensitive ? FNLower(l) : l;
		b = caseInsensitive ? FNLower(r) : r;
		if (_operatorType == NSBeginsWithPredicateOperatorType) { return [a hasPrefix:b]; }
		return [a hasSuffix:b];
	}

	case NSContainsPredicateOperatorType:
		if (l == nil || r == nil) { return NO; }
		if ([l respondsToSelector:@selector(containsObject:)]) { return [l containsObject:r]; }
		if (FNIsString(l) && FNIsString(r)) {
			return [l rangeOfString:r].location != NSNotFound;
		}
		return NO;

	case NSInPredicateOperatorType:
		if (r == nil || l == nil) { return NO; }
		if ([r respondsToSelector:@selector(containsObject:)]) { return [r containsObject:l]; }
		if (FNIsString(r) && FNIsString(l)) {
			return [r rangeOfString:l].location != NSNotFound;
		}
		return NO;

	case NSBetweenPredicateOperatorType: {
		id lo, hi;
		if (r == nil || ![r respondsToSelector:@selector(count)] || [r count] < 2) { return NO; }
		lo = [r objectAtIndex:0];
		hi = [r objectAtIndex:1];
		return (FNOrder(l, lo) != NSOrderedAscending) && (FNOrder(l, hi) != NSOrderedDescending);
	}

	case NSLikePredicateOperatorType:
	case NSMatchesPredicateOperatorType: {
		NSString *subject, *pattern;
		if (!FNIsString(l) || !FNIsString(r)) { return NO; }
		subject = l;
		pattern = (_operatorType == NSMatchesPredicateOperatorType) ? r : FNPatternFromLike(r, NO);
		return FNMatchesRegularExpression(subject, pattern, caseInsensitive);
	}

	case NSCustomSelectorPredicateOperatorType:
		/* REFUSED BY NAME. `-performSelector:withObject:` is not declared in this Foundation, and a custom
		 * selector that silently answered NO would be a predicate that lies. */
		[NSException raise:NSInvalidArgumentException
		            format:@"NSComparisonPredicate: custom selector operators are not implemented"];
		return NO;
	}
	return NO;
}

- (BOOL)evaluateWithObject:(id)object
{
	return [self evaluateWithObject:object substitutionVariables:nil];
}

- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings
{
	NSMutableDictionary *context = [[NSMutableDictionary alloc] init];
	id left, right;

	if (bindings != nil) {
		NSEnumerator *keys = [bindings keyEnumerator];
		id key;
		while ((key = [keys nextObject]) != nil) {
			[context setObject:[bindings objectForKey:key] forKey:key];
		}
	}

	left = [_lhs expressionValueWithObject:object context:context];
	right = [_rhs expressionValueWithObject:object context:context];

	if (_modifier != NSDirectPredicateModifier) {
		NSArray *elements = nil;
		NSUInteger i, n, matched = 0;
		BOOL answer;

		if ([left isKindOfClass:[NSSet class]]) { elements = [left allObjects]; }
		else if ([left isKindOfClass:[NSArray class]]) { elements = left; }

		if (elements == nil) {
			[context release];
			return NO;
		}
		n = [elements count];
		for (i = 0; i < n; i++) {
			if ([self fn_compareLeft:[elements objectAtIndex:i] right:right]) { matched++; }
		}
		if (_modifier == NSAllPredicateModifier) {
			answer = (matched == n);
		} else {
			answer = (matched > 0);
		}
		[context release];
		return answer;
	}

	{
		BOOL answer = [self fn_compareLeft:left right:right];
		[context release];
		return answer;
	}
}

- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)variables
{
	(void)variables;
	/* The substitutions land in the EXPRESSIONS, and this class's expressions are immutable, so the predicate
	 * is returned as-is and the variables are resolved at evaluation time — the same answer, one pass fewer. */
	return self;
}

- (NSString *)predicateFormat
{
	NSString *op = @"==";
	NSString *modifier = @"";

	switch (_operatorType) {
	case NSLessThanPredicateOperatorType: op = @"<"; break;
	case NSLessThanOrEqualToPredicateOperatorType: op = @"<="; break;
	case NSGreaterThanPredicateOperatorType: op = @">"; break;
	case NSGreaterThanOrEqualToPredicateOperatorType: op = @">="; break;
	case NSEqualToPredicateOperatorType: op = @"=="; break;
	case NSNotEqualToPredicateOperatorType: op = @"!="; break;
	case NSMatchesPredicateOperatorType: op = @"MATCHES"; break;
	case NSLikePredicateOperatorType: op = @"LIKE"; break;
	case NSBeginsWithPredicateOperatorType: op = @"BEGINSWITH"; break;
	case NSEndsWithPredicateOperatorType: op = @"ENDSWITH"; break;
	case NSInPredicateOperatorType: op = @"IN"; break;
	case NSCustomSelectorPredicateOperatorType: op = @"FUNCTION"; break;
	case NSContainsPredicateOperatorType: op = @"CONTAINS"; break;
	case NSBetweenPredicateOperatorType: op = @"BETWEEN"; break;
	}

	if (_modifier == NSAnyPredicateModifier) { modifier = @"ANY "; }
	else if (_modifier == NSAllPredicateModifier) { modifier = @"ALL "; }

	if ((_options & (NSCaseInsensitivePredicateOption | NSDiacriticInsensitivePredicateOption)) != 0) {
		NSString *options = @"";
		if ((_options & NSCaseInsensitivePredicateOption) != 0) { options = [options stringByAppendingString:@"c"]; }
		if ((_options & NSDiacriticInsensitivePredicateOption) != 0) { options = [options stringByAppendingString:@"d"]; }
		return [NSString stringWithFormat:@"%@%@ %@[%@] %@", modifier,
		        [_lhs fn_expressionFormat], op, options, [_rhs fn_expressionFormat]];
	}
	return [NSString stringWithFormat:@"%@%@ %@ %@", modifier,
	        [_lhs fn_expressionFormat], op, [_rhs fn_expressionFormat]];
}

@end
