/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * FNPredicateFormat.m — the format grammar: a tokenizer, a recursive-descent parser and the expression
 * renderer that makes `-predicateFormat` a round trip.
 *
 * WHY A PARSER RATHER THAN A REGEX. A predicate's format is text a caller wrote, and Core Data loads those
 * strings from nib files and model resources. A parser that mis-reads text produces a predicate that answers
 * a different question from the one asked, and does it silently — which is the one failure mode
 * COREDATA-PLAN.md §4.3 forbids. So every path out of this file either builds the predicate the text names
 * or raises `NSInvalidArgumentException` NAMING THE OFFSET where the text stopped making sense.
 *
 * WHAT IS DELIBERATELY NOT SUPPORTED, and refuses rather than approximates: arithmetic inside a comparison
 * (`a + 1 < b`), parenthesised EXPRESSIONS (`(a) == b` — a parenthesis in operand position is a predicate
 * group), `FUNCTION()` over a target expression (`obj.func(arg)`), and `%` conversions other than `%@`, `%K`,
 * `%d`, `%i`, `%f`, `%g`, `%e`.
 *
 * THE OPERATOR IS FOUND BY LONGEST MATCH, which matters for exactly one case: `<>` and `!=` are both
 * "not equal" and a single-character scan would read `<>` as `<` and then choke on `>`.
 */

#import <Foundation/NSPredicate.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/FNPredicatePrivate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSException.h>
#include <stdlib.h>

typedef struct {
	unichar *s;
	NSUInteger n;
	NSUInteger i;
	NSArray *args;
	NSUInteger arg;
} FNP;

static NSString *FNChars(const unichar *buf, NSUInteger len)
{
	return [[[NSString alloc] initWithCharacters:buf length:len] autorelease];
}

static NSString *FNChar(unichar c)
{
	return FNChars(&c, 1);
}

static void FNFail(FNP *p, NSString *why)
{
	[NSException raise:NSInvalidArgumentException
	            format:@"NSPredicate: %@ at offset %lu of the format", why, (unsigned long)p->i];
}

static BOOL FNIsSpace(unichar c) { return (c == ' ' || c == '\t' || c == '\n' || c == '\r'); }
static BOOL FNIsDigit(unichar c) { return (c >= '0' && c <= '9'); }
static BOOL FNIsIdentStart(unichar c)
{
	return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_');
}
static BOOL FNIsIdentPart(unichar c) { return FNIsIdentStart(c) || FNIsDigit(c); }

static void FNSkip(FNP *p)
{
	while (p->i < p->n && FNIsSpace(p->s[p->i])) { p->i++; }
}

static BOOL FNPeek(FNP *p, unichar c)
{
	FNSkip(p);
	return (p->i < p->n && p->s[p->i] == c);
}

static BOOL FNEat(FNP *p, unichar c)
{
	if (FNPeek(p, c)) { p->i++; return YES; }
	return NO;
}

static unichar FNPeekChar(FNP *p)
{
	FNSkip(p);
	return (p->i < p->n) ? p->s[p->i] : 0;
}

static unichar FNPeekCharAt(FNP *p, NSUInteger ahead)
{
	FNSkip(p);
	return (p->i + ahead < p->n) ? p->s[p->i + ahead] : 0;
}

/* A keyword is refused as a keyword when it runs into identifier characters: `ANDY` is a key path, not `AND`. */
static BOOL FNEatKeyword(FNP *p, const char *keyword)
{
	NSUInteger start, k;
	FNSkip(p);
	start = p->i;
	for (k = 0; keyword[k] != '\0'; k++) {
		unichar c = p->s[start + k];
		unichar want = (unichar)(unsigned char)keyword[k];
		if (start + k >= p->n) { return NO; }
		if (c >= 'A' && c <= 'Z') { c = (unichar)(c - 'A' + 'a'); }
		if (want >= 'A' && want <= 'Z') { want = (unichar)(want - 'A' + 'a'); }
		if (c != want) { return NO; }
	}
	if (start + k < p->n && FNIsIdentPart(p->s[start + k])) { return NO; }
	p->i = start + k;
	return YES;
}

static NSString *FNReadIdentifier(FNP *p)
{
	NSUInteger start;
	FNSkip(p);
	start = p->i;
	while (p->i < p->n && FNIsIdentPart(p->s[p->i])) { p->i++; }
	if (p->i == start) { FNFail(p, @"expected a name"); }
	return FNChars(p->s + start, p->i - start);
}

static NSString *FNReadString(FNP *p)
{
	unichar quote;
	NSMutableString *out;

	FNSkip(p);
	quote = p->s[p->i];
	p->i++;
	out = [[NSMutableString alloc] init];
	while (p->i < p->n) {
		unichar c = p->s[p->i++];
		if (c == quote) { return [out autorelease]; }
		if (c == '\\' && p->i < p->n) {
			unichar e = p->s[p->i++];
			switch (e) {
			case 'n': c = '\n'; break;
			case 't': c = '\t'; break;
			case 'r': c = '\r'; break;
			default: c = e; break;
			}
		}
		[out appendString:FNChar(c)];
	}
	[out release];
	FNFail(p, @"unterminated string literal");
	return nil;
}

static NSNumber *FNReadNumber(FNP *p)
{
	unichar buf[64];
	NSUInteger len = 0;
	BOOL floating = NO;
	BOOL negative = NO;

	FNSkip(p);
	if (p->i < p->n && (p->s[p->i] == '-' || p->s[p->i] == '+')) {
		negative = (p->s[p->i] == '-');
		p->i++;
	}
	while (p->i < p->n && len < 63) {
		unichar c = p->s[p->i];
		if (FNIsDigit(c)) { buf[len++] = c; p->i++; }
		else if (c == '.' && !floating) { floating = YES; buf[len++] = c; p->i++; }
		else if ((c == 'e' || c == 'E') && !floating) { floating = YES; buf[len++] = c; p->i++; }
		else { break; }
	}
	if (len == 0) { FNFail(p, @"expected a number"); }
	{
		NSString *text = FNChars(buf, len);
		if (floating) {
			double d = [text doubleValue];
			return [NSNumber numberWithDouble:(negative ? -d : d)];
		} else {
			double d = [text doubleValue];
			return [NSNumber numberWithInteger:(NSInteger)(negative ? -d : d)];
		}
	}
}

static NSArray *FNOne(id object)
{
	NSMutableArray *a = [[NSMutableArray alloc] init];
	[a addObject:object];
	return [a autorelease];
}

static NSPredicate *FNParseOr(FNP *p);
static NSPredicate *FNParseAnd(FNP *p);
static NSPredicate *FNParseUnary(FNP *p);
static NSPredicate *FNParseComparison(FNP *p);
static NSExpression *FNParseExpression(FNP *p);
static NSExpression *FNParsePrimary(FNP *p);

static NSExpression *FNParsePrimary(FNP *p)
{
	FNSkip(p);
	if (p->i >= p->n) { FNFail(p, @"expected an expression"); }

	switch (p->s[p->i]) {
	case '$': {
		NSString *name;
		p->i++;
		name = FNReadIdentifier(p);
		return [NSExpression expressionForVariable:name];
	}
	case '%': {
		unichar conv;
		p->i++;
		if (p->i >= p->n) { FNFail(p, @"dangling `%`"); }
		conv = p->s[p->i++];
		if (p->arg >= [p->args count]) {
			p->i--;
			FNFail(p, @"more format conversions than arguments");
		}
		{
			id value = [p->args objectAtIndex:p->arg++];
			if (conv == '@' || conv == 'K') {
				if (value == (id)[NSNull null]) { return [NSExpression expressionForConstantValue:nil]; }
				if (conv == 'K') { return [NSExpression expressionForKeyPath:value]; }
				return [NSExpression expressionForConstantValue:value];
			}
			return [NSExpression expressionForConstantValue:value];
		}
	}
	case '@': {
		if (FNPeekCharAt(p, 1) == '\'' || FNPeekCharAt(p, 1) == '"') {
			p->i++;
			return [NSExpression expressionForConstantValue:FNReadString(p)];
		}
		p->i++;
		{
			NSString *name = FNReadIdentifier(p);
			NSString *function = nil;
			if ([name isEqualToString:@"count"]) { function = @"count:"; }
			else if ([name isEqualToString:@"sum"]) { function = @"sum:"; }
			else if ([name isEqualToString:@"max"]) { function = @"max:"; }
			else if ([name isEqualToString:@"min"]) { function = @"min:"; }
			else if ([name isEqualToString:@"avg"]) { function = @"average:"; }
			if (function == nil) {
				FNFail(p, [NSString stringWithFormat:@"`@%@` is not an aggregate this parser knows", name]);
			}
			return [NSExpression expressionForFunction:function
			                                arguments:FNOne([NSExpression expressionForKeyPath:@"SELF"])];
		}
	}
	case '\'':
	case '"':
		return [NSExpression expressionForConstantValue:FNReadString(p)];
	case '{': {
		NSMutableArray *elements = [[NSMutableArray alloc] init];
		p->i++;
		for (;;) {
			[elements addObject:FNParseExpression(p)];
			if (FNEat(p, ',')) { continue; }
			break;
		}
		if (!FNEat(p, '}')) { [elements release]; FNFail(p, @"expected `}` closing an aggregate"); }
		{
			NSExpression *e = [NSExpression expressionForAggregate:elements];
			[elements release];
			return e;
		}
	}
	case '(':
		/* A PARENTHESIS IN OPERAND POSITION IS A PREDICATE GROUP, and saying so is better than a diagnostic
		 * about arithmetic: `(a) == b` is not Cocoa, and this tree refuses it in the caller's own terms. */
		FNFail(p, @"a parenthesised expression is not supported in operand position; use a key path");
		return nil;
	default:
		break;
	}

	if (FNIsDigit(p->s[p->i]) ||
	    ((p->s[p->i] == '-' || p->s[p->i] == '+') && FNIsDigit(FNPeekCharAt(p, 1)))) {
		return [NSExpression expressionForConstantValue:FNReadNumber(p)];
	}

	if (FNIsIdentStart(p->s[p->i])) {
		NSString *name = FNReadIdentifier(p);

		if ([name isEqualToString:@"YES"] || [name isEqualToString:@"TRUE"]) {
			return [NSExpression expressionForConstantValue:[NSNumber numberWithBool:YES]];
		}
		if ([name isEqualToString:@"NO"] || [name isEqualToString:@"FALSE"]) {
			return [NSExpression expressionForConstantValue:[NSNumber numberWithBool:NO]];
		}
		if ([name isEqualToString:@"nil"] || [name isEqualToString:@"NULL"]) {
			return [NSExpression expressionForConstantValue:nil];
		}
		if ([name isEqualToString:@"SELF"]) {
			return [NSExpression expressionForKeyPath:@"SELF"];
		}
		if (FNPeek(p, '(')) {
			NSMutableArray *args = [[NSMutableArray alloc] init];
			NSExpression *e;
			p->i++;
			if (!FNPeek(p, ')')) {
				for (;;) {
					[args addObject:FNParseExpression(p)];
					if (FNEat(p, ',')) { continue; }
					break;
				}
			}
			if (!FNEat(p, ')')) { [args release]; FNFail(p, @"expected `)` closing a function"); }
			e = [NSExpression expressionForFunction:[name stringByAppendingString:@":"]
			                             arguments:args];
			[args release];
			return e;
		}
		/* A DOTTED TAIL IS ONE KEY PATH, including `SELF.x` and `@count`'s target. */
		while (FNPeek(p, '.') && FNIsIdentStart(FNPeekCharAt(p, 1))) {
			NSString *next;
			p->i++;
			next = FNReadIdentifier(p);
			name = [NSString stringWithFormat:@"%@.%@", name, next];
		}
		return [NSExpression expressionForKeyPath:name];
	}

	FNFail(p, @"expected an expression");
	return nil;
}

static NSExpression *FNParseExpression(FNP *p)
{
	NSExpression *e = FNParsePrimary(p);
	while (FNPeek(p, '.')) {
		NSString *next;
		if (FNPeekCharAt(p, 1) == '@') { break; }
		if (!FNIsIdentStart(FNPeekCharAt(p, 1))) { break; }
		p->i++;
		next = FNReadIdentifier(p);
		e = [NSExpression expressionForKeyPath:
		     [NSString stringWithFormat:@"%@.%@", [[[e keyPath] copy] autorelease], next]];
	}
	return e;
}

static NSUInteger FNParseOptions(FNP *p)
{
	NSUInteger options = 0;
	if (!FNPeek(p, '[')) { return 0; }
	p->i++;
	while (p->i < p->n && p->s[p->i] != ']') {
		unichar c = p->s[p->i++];
		if (c == 'c') { options |= NSCaseInsensitivePredicateOption; }
		else if (c == 'd') { options |= NSDiacriticInsensitivePredicateOption; }
	}
	if (!FNEat(p, ']')) { FNFail(p, @"expected `]` closing an operator's options"); }
	return options;
}

static NSPredicate *FNParseComparison(FNP *p)
{
	NSComparisonPredicateModifier modifier = NSDirectPredicateModifier;
	BOOL negate = NO;
	NSExpression *lhs;
	NSExpression *rhs = nil;
	NSPredicateOperatorType type = NSEqualToPredicateOperatorType;
	NSUInteger options = 0;
	NSPredicate *result;

	if (FNEatKeyword(p, "ANY") || FNEatKeyword(p, "SOME")) { modifier = NSAnyPredicateModifier; }
	else if (FNEatKeyword(p, "ALL")) { modifier = NSAllPredicateModifier; }
	else if (FNEatKeyword(p, "NONE")) { modifier = NSAnyPredicateModifier; negate = YES; }

	lhs = FNParseExpression(p);

	if (FNEatKeyword(p, "BETWEEN")) {
		NSMutableArray *bounds = [[NSMutableArray alloc] init];
		if (!FNEat(p, '{')) { [bounds release]; FNFail(p, @"expected `{` after BETWEEN"); }
		[bounds addObject:FNParseExpression(p)];
		if (!FNEat(p, ',')) { [bounds release]; FNFail(p, @"BETWEEN takes two bounds"); }
		[bounds addObject:FNParseExpression(p)];
		if (!FNEat(p, '}')) { [bounds release]; FNFail(p, @"expected `}` closing BETWEEN"); }
		rhs = [NSExpression expressionForAggregate:bounds];
		[bounds release];
		type = NSBetweenPredicateOperatorType;
	} else if (FNEatKeyword(p, "IN")) {
		rhs = FNParseExpression(p);
		type = NSInPredicateOperatorType;
	} else if (FNEatKeyword(p, "CONTAINS")) {
		rhs = FNParseExpression(p);
		type = NSContainsPredicateOperatorType;
	} else if (FNEatKeyword(p, "BEGINSWITH")) {
		options = FNParseOptions(p);
		rhs = FNParseExpression(p);
		type = NSBeginsWithPredicateOperatorType;
	} else if (FNEatKeyword(p, "ENDSWITH")) {
		options = FNParseOptions(p);
		rhs = FNParseExpression(p);
		type = NSEndsWithPredicateOperatorType;
	} else if (FNEatKeyword(p, "LIKE")) {
		options = FNParseOptions(p);
		rhs = FNParseExpression(p);
		type = NSLikePredicateOperatorType;
	} else if (FNEatKeyword(p, "MATCHES")) {
		options = FNParseOptions(p);
		rhs = FNParseExpression(p);
		type = NSMatchesPredicateOperatorType;
	} else {
		/* LONGEST MATCH FIRST: `<>` and `!=` are one operator and `<=` is not `<` followed by `=`. */
		unichar a = FNPeekChar(p);
		unichar b = FNPeekCharAt(p, 1);

		if (a == '!' && b == '=') { p->i += 2; type = NSNotEqualToPredicateOperatorType; }
		else if (a == '<' && b == '>') { p->i += 2; type = NSNotEqualToPredicateOperatorType; }
		else if (a == '<' && b == '=') { p->i += 2; type = NSLessThanOrEqualToPredicateOperatorType; }
		else if (a == '>' && b == '=') { p->i += 2; type = NSGreaterThanOrEqualToPredicateOperatorType; }
		else if (a == '=' && b == '=') { p->i += 2; type = NSEqualToPredicateOperatorType; }
		else if (a == '<') { p->i += 1; type = NSLessThanPredicateOperatorType; }
		else if (a == '>') { p->i += 1; type = NSGreaterThanPredicateOperatorType; }
		else if (a == '=') { p->i += 1; type = NSEqualToPredicateOperatorType; }
		else {
			/* A BARE EXPRESSION IS A TRUTH TEST: `isDone` means `isDone == YES`, which is what Cocoa's own
			 * simple predicates do, and is the only reading that keeps `predicateWithFormat:@"flag"` useful. */
			result = [NSComparisonPredicate predicateWithLeftExpression:lhs
			                                           rightExpression:[NSExpression expressionForConstantValue:
			                                                            [NSNumber numberWithBool:YES]]
			                                                  modifier:NSDirectPredicateModifier
			                                                      type:NSEqualToPredicateOperatorType
			                                                   options:0];
			return result;
		}
		options = FNParseOptions(p);
		rhs = FNParseExpression(p);
	}

	result = [NSComparisonPredicate predicateWithLeftExpression:lhs
	                                           rightExpression:rhs
	                                                  modifier:modifier
	                                                      type:type
	                                                   options:options];
	if (negate) {
		result = [NSCompoundPredicate notPredicateWithSubpredicate:result];
	}
	return result;
}

static NSPredicate *FNParseUnary(FNP *p)
{
	FNSkip(p);
	if (FNEatKeyword(p, "NOT") || FNEat(p, '!')) {
		return [NSCompoundPredicate notPredicateWithSubpredicate:FNParseUnary(p)];
	}
	if (FNPeek(p, '(')) {
		NSPredicate *inner;
		p->i++;
		inner = FNParseOr(p);
		if (!FNEat(p, ')')) { FNFail(p, @"expected `)` closing a group"); }
		return inner;
	}
	return FNParseComparison(p);
}

static NSPredicate *FNParseAnd(FNP *p)
{
	NSMutableArray *parts = [[NSMutableArray alloc] init];
	NSPredicate *result;

	[parts addObject:FNParseUnary(p)];
	while (FNEatKeyword(p, "AND")) {
		[parts addObject:FNParseUnary(p)];
	}
	if ([parts count] == 1) {
		result = [[parts objectAtIndex:0] retain];
	} else {
		result = [[NSCompoundPredicate andPredicateWithSubpredicates:parts] retain];
	}
	[parts release];
	return [result autorelease];
}

static NSPredicate *FNParseOr(FNP *p)
{
	NSMutableArray *parts = [[NSMutableArray alloc] init];
	NSPredicate *result;

	[parts addObject:FNParseAnd(p)];
	while (FNEatKeyword(p, "OR")) {
		[parts addObject:FNParseAnd(p)];
	}
	if ([parts count] == 1) {
		result = [[parts objectAtIndex:0] retain];
	} else {
		result = [[NSCompoundPredicate orPredicateWithSubpredicates:parts] retain];
	}
	[parts release];
	return [result autorelease];
}

NSPredicate *FNParsePredicateFormat(NSString *format, NSArray *arguments)
{
	FNP p;
	NSPredicate *result;

	if (format == nil) { return nil; }

	p.n = [format length];
	p.i = 0;
	p.args = arguments;
	p.arg = 0;
	p.s = (unichar *)malloc(sizeof(unichar) * (p.n + 1));
	if (p.s == NULL) { return nil; }
	{
		NSUInteger k;
		for (k = 0; k < p.n; k++) { p.s[k] = [format characterAtIndex:k]; }
	}

	FNSkip(&p);
	if (FNEatKeyword(&p, "TRUEPREDICATE")) { free(p.s); return [NSPredicate predicateWithValue:YES]; }
	if (FNEatKeyword(&p, "FALSEPREDICATE")) { free(p.s); return [NSPredicate predicateWithValue:NO]; }

	result = FNParseOr(&p);
	FNSkip(&p);
	if (p.i < p.n) {
		FNFail(&p, @"unexpected text after the predicate");
	}
	free(p.s);
	return result;
}

/* ---- rendering: the other half of the round trip -------------------------------------------------- */

@implementation NSExpression (FNPrivate)

- (NSString *)fn_expressionFormat
{
	switch ([self expressionType]) {
	case NSConstantValueExpressionType: {
		id v = [self constantValue];
		if (v == nil) { return @"nil"; }
		if ([v isKindOfClass:[NSString class]]) {
			NSMutableString *out = [[NSMutableString alloc] init];
			NSUInteger i, n = [(NSString *)v length];
			[out appendString:@"\""];
			for (i = 0; i < n; i++) {
				unichar c = [(NSString *)v characterAtIndex:i];
				if (c == '"' || c == '\\') { [out appendString:@"\\"]; }
				[out appendString:FNChar(c)];
			}
			[out appendString:@"\""];
			return [out autorelease];
		}
		return [NSString stringWithFormat:@"%@", v];
	}
	case NSEvaluatedObjectExpressionType:
		return @"SELF";
	case NSVariableExpressionType:
		return [NSString stringWithFormat:@"$%@", [self variable]];
	case NSKeyPathExpressionType:
		return [self keyPath];
	case NSAggregateExpressionType: {
		NSArray *items = [self arguments];
		NSMutableString *out = [[NSMutableString alloc] init];
		NSUInteger i, n = [items count];
		[out appendString:@"{"];
		for (i = 0; i < n; i++) {
			if (i > 0) { [out appendString:@", "]; }
			[out appendString:[[items objectAtIndex:i] fn_expressionFormat]];
		}
		[out appendString:@"}"];
		return [out autorelease];
	}
	case NSFunctionExpressionType: {
		NSArray *items = [self arguments];
		NSMutableString *out = [[NSMutableString alloc] init];
		NSUInteger i, n = [items count];
		[out appendString:[self function]];
		[out appendString:@"("];
		for (i = 0; i < n; i++) {
			if (i > 0) { [out appendString:@", "]; }
			[out appendString:[[items objectAtIndex:i] fn_expressionFormat]];
		}
		[out appendString:@")"];
		return [out autorelease];
	}
	case NSUnionSetExpressionType:
		return [NSString stringWithFormat:@"%@ UNION %@",
		        [[self leftExpression] fn_expressionFormat], [[self rightExpression] fn_expressionFormat]];
	case NSIntersectSetExpressionType:
		return [NSString stringWithFormat:@"%@ INTERSECT %@",
		        [[self leftExpression] fn_expressionFormat], [[self rightExpression] fn_expressionFormat]];
	case NSMinusSetExpressionType:
		return [NSString stringWithFormat:@"%@ MINUS %@",
		        [[self leftExpression] fn_expressionFormat], [[self rightExpression] fn_expressionFormat]];
	case NSSubqueryExpressionType:
		return [NSString stringWithFormat:@"SUBQUERY(%@, $%@, %@)",
		        [[self collection] fn_expressionFormat], [self variable], [[self predicate] predicateFormat]];
	default:
		return @"SELF";
	}
}

@end
