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
 * TWO GRAMMARS, ONE PARSER AND ONE FLAG. `+predicateWithFormat:` reads the predicate grammar above;
 * `+expressionWithFormat:` reads Apple's EXPRESSION grammar, which is that grammar plus arithmetic (`+ - * / **`,
 * over Apple's own `add:to:`/`raise:toPower:` function names) and grouping parentheses, and MINUS the comparison
 * operators — a comparison is a predicate, so the expression door refuses one BY NAME instead of returning its
 * left side and dropping the rest. The flag is the whole difference: everything a predicate can already say
 * about an operand, an expression says identically, which is why the two doors cannot drift apart.
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
#include <stdarg.h>	/* va_list: the argument list the two format doors hand over unread */

typedef struct {
	unichar *s;
	NSUInteger n;
	NSUInteger i;
	NSArray *args;
	NSUInteger arg;
	BOOL expression;		/* YES: the expression grammar; NO: the predicate grammar (see the note above) */
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

/* ONE BINARY FUNCTION EXPRESSION. Every arithmetic operator becomes one of these, which is why the parser can
 * promise that `a + b` and `+[NSExpression expressionForFunction:@"add:to:" arguments:…]` are the same tree. */
static NSExpression *FNBinary(NSString *function, NSExpression *left, NSExpression *right)
{
	NSMutableArray *args = [[NSMutableArray alloc] init];
	NSExpression *e;
	[args addObject:left];
	[args addObject:right];
	e = [NSExpression expressionForFunction:function arguments:args];
	[args release];
	return e;
}

static NSPredicate *FNParseOr(FNP *p);
static NSPredicate *FNParseAnd(FNP *p);
static NSPredicate *FNParseUnary(FNP *p);
static NSPredicate *FNParseComparison(FNP *p);
static NSExpression *FNParseExpression(FNP *p);
static NSExpression *FNParsePrimary(FNP *p);
static NSExpression *FNParseSuffix(FNP *p);
static NSExpression *FNParseArithmetic(FNP *p);
static NSExpression *FNParseTerm(FNP *p);
static NSExpression *FNParsePower(FNP *p);

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
		 * about arithmetic: `(a) == b` is not Cocoa, and this tree refuses it in the caller's own terms. In the
		 * EXPRESSION grammar a parenthesis groups an arithmetic operand, which is the one thing
		 * `+expressionWithFormat:` needs that the predicate grammar here must keep refusing. */
		if (p->expression) {
			NSExpression *inner;
			p->i++;
			inner = FNParseArithmetic(p);
			if (!FNEat(p, ')')) { FNFail(p, @"expected `)` closing a group"); }
			return inner;
		}
		FNFail(p, @"a parenthesised expression is not supported in operand position; use a key path");
		return nil;
	default:
		break;
	}

	/* A SIGN IN OPERAND POSITION (expression mode only): `-(a + b)`, `2 * -x`. A sign the NUMBER READER can use is
	 * left to it, so `-1` stays one constant instead of becoming a subtraction from zero. */
	if (p->expression && (p->s[p->i] == '-' || p->s[p->i] == '+') && !FNIsDigit(FNPeekCharAt(p, 1))) {
		BOOL negative = (p->s[p->i] == '-');
		NSExpression *operand;
		p->i++;
		operand = FNParseSuffix(p);
		if (!negative) { return operand; }
		return FNBinary(@"from:subtract:",
		                [NSExpression expressionForConstantValue:[NSNumber numberWithInteger:0]], operand);
	}

	if (FNIsDigit(p->s[p->i]) ||
	    ((p->s[p->i] == '-' || p->s[p->i] == '+') && FNIsDigit(FNPeekCharAt(p, 1)))) {
		return [NSExpression expressionForConstantValue:FNReadNumber(p)];
	}

	if (FNIsIdentStart(p->s[p->i])) {
		NSString *name = FNReadIdentifier(p);
		BOOL selectorColons = NO;

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
		/* TERNARY(condition, true, false) IS A FORM, NOT A FUNCTION: its first argument is a PREDICATE and the other
		 * two are expressions, so it cannot go through the function-argument loop below, which parses every argument as
		 * an expression. That is also why it is read here in BOTH modes — a conditional expression renders as TERNARY,
		 * so the predicate door has to be able to read the text its own renderer writes. */
		if ([name caseInsensitiveCompare:@"TERNARY"] == NSOrderedSame && FNPeek(p, '(')) {
			NSPredicate *condition;
			NSExpression *whenTrue, *whenFalse;
			p->i++;
			condition = FNParseOr(p);
			if (!FNEat(p, ',')) { FNFail(p, @"TERNARY takes a condition, a true expression and a false expression"); }
			whenTrue = FNParseExpression(p);
			if (!FNEat(p, ',')) { FNFail(p, @"TERNARY takes a condition, a true expression and a false expression"); }
			whenFalse = FNParseExpression(p);
			if (!FNEat(p, ')')) { FNFail(p, @"expected `)` closing TERNARY"); }
			return [NSExpression expressionForConditional:condition
			                              trueExpression:whenTrue
			                             falseExpression:whenFalse];
		}
		if (FNPeek(p, ':')) {
			/* A SELECTOR'S TRAILING COLONS ARE PART OF THE SYMBOL. `-fn_expressionFormat` writes a function whose
			 * name has colons as `modulus:by:(a, b)` — the only spelling that reads back — so the symbol is read as
			 * Apple's grammar states it (`uppercase:(name)` and `modulus:by:(a, b)` alike). The colons are COMMITTED
			 * only when the symbol ends at `(`, so `a : b` stays the syntax error it was rather than becoming a key
			 * path nobody wrote. */
			NSUInteger save = p->i;
			NSMutableString *symbol = [[NSMutableString alloc] init];
			[symbol appendString:name];
			while (FNPeek(p, ':')) {
				p->i++;
				[symbol appendString:@":"];
				if (FNIsIdentStart(FNPeekChar(p))) {
					[symbol appendString:FNReadIdentifier(p)];
				}
			}
			if (FNPeek(p, '(')) {
				name = [symbol autorelease];
				selectorColons = YES;
			} else {
				[symbol release];
				p->i = save;
			}
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
			/* ⚠ **`FUNCTION(receiver, "selector")` IS A SELECTOR FORM, NOT A FUNCTION CALLED `FUNCTION`.** The
			 * parser used to read it as a function named `FUNCTION:` and evaluation refused it by that name, which
			 * is how this gap was found (§0.15). Apple's grammar puts the receiver first and the selector as a
			 * STRING second, with any arguments after it. */
			if (([name caseInsensitiveCompare:@"FUNCTION"] == NSOrderedSame ||
			     [name caseInsensitiveCompare:@"FUNCTION:"] == NSOrderedSame) && [args count] >= 2) {
				id receiver = [args objectAtIndex:0];
				/* THE SELECTOR ARRIVES AS A CONSTANT EXPRESSION, not as a string: every argument is parsed as an
				 * expression, and a quoted string parses to `expressionForConstantValue:`. */
				id selector = [[args objectAtIndex:1] constantValue];
				NSMutableArray *rest = [[NSMutableArray alloc] init];
				NSUInteger k;

				if (![selector isKindOfClass:[NSString class]]) {
					[rest release];
					[args release];
					FNFail(p, @"FUNCTION's second argument must be a selector NAME in quotes");
				}
				for (k = 2; k < [args count]; k++) {
					[rest addObject:[args objectAtIndex:k]];
				}
				e = [NSExpression expressionForFunction:receiver selectorName:selector arguments:rest];
				[rest release];
				[args release];
				return e;
			}
			e = [NSExpression expressionForFunction:(selectorColons ? name : [name stringByAppendingString:@":"])
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

/* ONE NAME, TWO GRAMMARS. Every predicate production that takes an operand calls this, so the predicate grammar
 * must not move: in predicate mode it is a primary and its dotted tail, exactly as it was before expressions had
 * a door of their own. In expression mode it is Apple's arithmetic grammar, and that is the whole difference. */
static NSExpression *FNParseExpression(FNP *p)
{
	if (p->expression) { return FNParseArithmetic(p); }
	return FNParseSuffix(p);
}

static NSExpression *FNParseSuffix(FNP *p)
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

/* THE ARITHMETIC OPERATORS ARE APPLE'S FUNCTION NAMES, not this tree's invention: a parsed `a + b` answers
 * `-function` == `add:to:`, which is what a keyed archive of it holds and what code building such an expression
 * names. `**` is `raise:toPower:`. `modulus:by:` has an evaluation but no operator, so it has none here — the
 * grammar refuses what a caller cannot write back, and `%` is not in Apple's operator set. */
static NSExpression *FNParsePower(FNP *p)
{
	NSExpression *left = FNParseSuffix(p);
	while (FNPeek(p, '*') && FNPeekCharAt(p, 1) == '*') {
		p->i += 2;
		left = FNBinary(@"raise:toPower:", left, FNParseSuffix(p));
	}
	return left;
}

static NSExpression *FNParseTerm(FNP *p)
{
	NSExpression *left = FNParsePower(p);
	for (;;) {
		/* `**` IS TESTED BEFORE `*`: reading `a ** b` as a multiplication would leave the second `*` in operand
		 * position, and the diagnostic would name arithmetic the caller did write correctly. */
		if (FNPeek(p, '*') && FNPeekCharAt(p, 1) != '*') {
			p->i++;
			left = FNBinary(@"multiply:by:", left, FNParsePower(p));
		} else if (FNPeek(p, '/')) {
			p->i++;
			left = FNBinary(@"divide:by:", left, FNParsePower(p));
		} else {
			return left;
		}
	}
}

static NSExpression *FNParseArithmetic(FNP *p)
{
	NSExpression *left = FNParseTerm(p);
	for (;;) {
		if (FNPeek(p, '+')) {
			p->i++;
			left = FNBinary(@"add:to:", left, FNParseTerm(p));
		} else if (FNPeek(p, '-')) {
			p->i++;
			left = FNBinary(@"from:subtract:", left, FNParseTerm(p));
		} else {
			return left;
		}
	}
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

/* ONE SET-UP FOR BOTH DOORS: the format is copied into a unichar buffer once, because every scan below walks it
 * by index and `-characterAtIndex:` in a loop is the one thing a parser may not do. `expression` is the flag that
 * chooses grammar; nothing else about the text changes. */
static BOOL FNPBegin(FNP *p, NSString *format, NSArray *arguments, BOOL expression)
{
	NSUInteger k;

	p->n = [format length];
	p->i = 0;
	p->args = arguments;
	p->arg = 0;
	p->expression = expression;
	p->s = (unichar *)malloc(sizeof(unichar) * (p->n + 1));
	if (p->s == NULL) { return NO; }
	for (k = 0; k < p->n; k++) { p->s[k] = [format characterAtIndex:k]; }
	FNSkip(p);
	return YES;
}

NSPredicate *FNParsePredicateFormat(NSString *format, NSArray *arguments)
{
	FNP p;
	NSPredicate *result;

	if (format == nil) { return nil; }
	if (!FNPBegin(&p, format, arguments, NO)) { return nil; }

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

NSExpression *FNParseExpressionFormat(NSString *format, NSArray *arguments)
{
	FNP p;
	NSExpression *result;

	if (format == nil) { return nil; }
	if (!FNPBegin(&p, format, arguments, YES)) { return nil; }

	result = FNParseArithmetic(&p);
	FNSkip(&p);
	if (p.i < p.n) {
		/* A COMPARISON IS A PREDICATE, AND THE REFUSAL NAMES THE DOOR THAT READS ONE. Returning the left side and
		 * dropping ` < 2` — which is what a scanner that does not check for trailing text does — would make
		 * `+expressionWithFormat:@"a < 2"` mean `a`, silently. */
		unichar c = p.s[p.i];
		if (c == '<' || c == '>' || c == '=' || c == '!') {
			FNFail(&p, @"a comparison is a predicate, not an expression; +predicateWithFormat: is the door that reads one");
		}
		FNFail(&p, @"unexpected text after the expression");
	}
	free(p.s);
	return result;
}

/* THE ARGUMENTS ARE COLLECTED, NOT POSITIONALLY INTERPRETED HERE: `%K` and `%@` are interchangeable in position, so
 * the parser has to see the format and the values together to know which door a given value came through. The list
 * is walked once, here, into the array the parser reads. Two callers share it — the predicate door and the
 * expression door — because which conversions a format has is a property of the FORMAT, not of the caller. */
NSArray *FNArgumentsFromFormat(NSString *format, va_list arguments)
{
	NSMutableArray *values;
	unichar *buf = NULL;
	NSUInteger i, n;

	if (format == nil) { return nil; }
	values = [[NSMutableArray alloc] init];
	n = [format length];
	buf = (unichar *)malloc(sizeof(unichar) * (n + 1));
	if (buf == NULL) {
		[values release];
		return nil;
	}
	for (i = 0; i < n; i++) { buf[i] = [format characterAtIndex:i]; }

	i = 0;
	while (i < n) {
		if (buf[i] == '%' && i + 1 < n) {
			unichar c = buf[i + 1];
			if (c == '@' || c == 'K') {
				id obj = va_arg(arguments, id);
				[values addObject:(obj != nil) ? obj : (id)[NSNull null]];
			} else if (c == 'd' || c == 'i') {
				[values addObject:[NSNumber numberWithInteger:(NSInteger)va_arg(arguments, int)]];
			} else if (c == 'f' || c == 'g' || c == 'e') {
				[values addObject:[NSNumber numberWithDouble:va_arg(arguments, double)]];
			}
			i += 2;
			continue;
		}
		i++;
	}
	free(buf);
	return [values autorelease];
}

/* ---- rendering: the other half of the round trip -------------------------------------------------- */

/* THE SIX ARITHMETIC SYMBOLS HAVE AN OPERATOR SPELLING AND THE PARSER READS IT BACK. Rendering them as
 * `add:to:(a, b)` would be a string this grammar cannot parse (an identifier stops at `:`), so a predicate or
 * expression that came from arithmetic must be written as arithmetic — otherwise `-predicateFormat` would produce
 * text that means nothing to the door that produced it. `modulus:by:` has no operator; it renders as the
 * selector-shaped call the parser now reads. */
static NSString *FNOperatorForFunction(NSString *function)
{
	if ([function isEqualToString:@"add:to:"]) { return @"+"; }
	if ([function isEqualToString:@"from:subtract:"]) { return @"-"; }
	if ([function isEqualToString:@"multiply:by:"]) { return @"*"; }
	if ([function isEqualToString:@"divide:by:"]) { return @"/"; }
	if ([function isEqualToString:@"raise:toPower:"]) { return @"**"; }
	return nil;
}

/* AN OPERAND OF A BINARY OPERATOR IS PARENTHESISED WHEN IT IS ONE TOO, so the text re-parses to the same tree:
 * `a + b * 2` is written `a + (b * 2)`, and `(a + b) * 2` keeps the parentheses that changed the answer. */
static NSString *FNOperandFormat(NSExpression *e)
{
	NSString *text = [e fn_expressionFormat];

	if ([e expressionType] == NSFunctionExpressionType && [e operand] == nil &&
	    [e arguments] != nil && [[e arguments] count] == 2 && FNOperatorForFunction([e function]) != nil) {
		return [NSString stringWithFormat:@"(%@)", text];
	}
	return text;
}

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
		NSString *op = ([self operand] == nil && n == 2) ? FNOperatorForFunction([self function]) : nil;

		if (op != nil) {
			[out appendFormat:@"%@ %@ %@",
			 FNOperandFormat([items objectAtIndex:0]), op, FNOperandFormat([items objectAtIndex:1])];
			return [out autorelease];
		}

		if ([self operand] != nil) {
			/* FUNCTION(receiver, "selector" [, args…]) — the form the parser reads back. */
			[out appendFormat:@"FUNCTION(%@, \"%@\"", [[self operand] fn_expressionFormat], [self function]];
			for (i = 0; i < n; i++) {
				[out appendFormat:@", %@", [[items objectAtIndex:i] fn_expressionFormat]];
			}
			[out appendString:@")"];
			return [out autorelease];
		}
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
	case NSConditionalExpressionType:
		/* `TERNARY(condition, true, false)` IS THE FORM APPLE'S FORMAT USES and the form the parser reads back, with
		 * the condition written as a PREDICATE — which is what it is, and why it is rendered by `-predicateFormat`. */
		return [NSString stringWithFormat:@"TERNARY(%@, %@, %@)",
		        [[self predicate] predicateFormat],
		        [[self trueExpression] fn_expressionFormat],
		        [[self falseExpression] fn_expressionFormat]];
	default:
		return @"SELF";
	}
}

@end
