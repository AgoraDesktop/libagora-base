/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * expression_format.m — THE EXPRESSION DOOR, ASKED THE QUESTIONS A CALLER ASKS.
 *
 * `+expressionWithFormat:` is one grammar away from `+predicateWithFormat:`: the same substitutions, the same
 * refusals and the same offsets, plus arithmetic and grouping, minus comparisons. So this probe asks both halves at
 * once — what the text BUILDS (`-function`, `-arguments`, `-expressionType`), what the tree EVALUATES, and what the
 * renderer writes back — because a door that builds the right tree and renders text that does not parse is not a
 * round trip, and the predicate family's contract (COREDATA-PLAN.md §4.3) is that saved text means the same thing
 * when it is read again.
 *
 * THE ARITHMETIC OPERATORS ARE APPLE'S FUNCTION NAMES (`add:to:`, `from:subtract:`, `multiply:by:`, `divide:by:`,
 * `raise:toPower:`), which is what a keyed archive of a parsed expression holds and what code that builds one by
 * hand names. Naming them here is the whole point: `1 + 1` and `[NSExpression expressionForFunction:@"add:to:"
 * arguments:…]` must be the same tree, or the two ways to make an expression disagree.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdarg.h>

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

/* THE THREE FORMS OF ONE DOOR. `arguments:` takes a `va_list`, so a probe has to have one of its own; the array
 * form is here because the same text must produce the same tree whichever door it came through. */
static NSExpression *ViaArguments(NSString *format, ...)
{
	va_list ap;
	NSExpression *e;

	va_start(ap, format);
	e = [NSExpression expressionWithFormat:format arguments:ap];
	va_end(ap);
	return e;
}

static double ValueIn(NSExpression *e, NSDictionary *object)
{
	return [[e expressionValueWithObject:object context:nil] doubleValue];
}

static BOOL Raises(NSString *format, NSArray *arguments, NSString *expectSubstring)
{
	@try {
		(void)[NSExpression expressionWithFormat:format argumentArray:arguments];
	} @catch (NSException *e) {
		if (![[e name] isEqualToString:NSInvalidArgumentException]) { return NO; }
		return [[e reason] rangeOfString:expectSubstring].location != NSNotFound;
	}
	return NO;
}

/* THE ROUND TRIP IS THE ASSERTION, and it is made of two halves: the text parses again, and the tree it parses to
 * WRITES THE SAME TEXT. One half alone passes for a renderer that is lossy in the same way the parser is. */
static BOOL RoundTrips(NSString *format, NSDictionary *object)
{
	NSExpression *first = [NSExpression expressionWithFormat:format];
	NSString *text;
	NSExpression *second;

	if (first == nil) { return NO; }
	text = [first fn_expressionFormat];
	second = [NSExpression expressionWithFormat:text];
	if (second == nil) { return NO; }
	if (![[second fn_expressionFormat] isEqualToString:text]) { return NO; }
	return ValueIn(first, object) == ValueIn(second, object);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *object = [NSDictionary dictionaryWithObjectsAndKeys:
	                        [NSNumber numberWithInt:8], @"a",
	                        [NSNumber numberWithInt:2], @"b", nil];
	NSExpression *e;
	NSExpression *text;

	/* NIL IS THE ONE INPUT THAT IS NOT SYNTAX, and the predicate door answers nil for it; so does this one. */
	check([NSExpression expressionWithFormat:nil] == nil, "a nil format is nil, not an exception");

	/* THE FOUR OPERATORS AND THE POWER, each by the function name Apple's archive holds. */
	e = [NSExpression expressionWithFormat:@"a + b"];
	check([[e function] isEqualToString:@"add:to:"], "a parsed `+` is add:to:");
	check(ValueIn(e, object) == 10.0, "and adds");
	e = [NSExpression expressionWithFormat:@"a - b"];
	check([[e function] isEqualToString:@"from:subtract:"], "a parsed `-` is from:subtract:");
	check(ValueIn(e, object) == 6.0, "and subtracts the second from the first");
	e = [NSExpression expressionWithFormat:@"a * b"];
	check([[e function] isEqualToString:@"multiply:by:"], "a parsed `*` is multiply:by:");
	check(ValueIn(e, object) == 16.0, "and multiplies");
	e = [NSExpression expressionWithFormat:@"a / b"];
	check([[e function] isEqualToString:@"divide:by:"], "a parsed `/` is divide:by:");
	check(ValueIn(e, object) == 4.0, "and divides");
	e = [NSExpression expressionWithFormat:@"a ** b"];
	check([[e function] isEqualToString:@"raise:toPower:"], "a parsed `**` is raise:toPower:");
	check(ValueIn(e, object) == 64.0, "and raises to a power");

	/* PRECEDENCE AND GROUPING. `**` binds tighter than `*`/`/`, which bind tighter than `+`/`-`, and the renderer
	 * states the precedence it read back so the text does not depend on the reader guessing. */
	check(ValueIn([NSExpression expressionWithFormat:@"a + b * 2"], object) == 12.0,
	      "multiplication binds tighter than addition");
	check(ValueIn([NSExpression expressionWithFormat:@"(a + b) * 2"], object) == 20.0,
	      "and a group overrides it");
	check(ValueIn([NSExpression expressionWithFormat:@"2 * (3 + 4)"], object) == 14.0,
	      "a group in operand position is an expression, not a predicate group");
	check(ValueIn([NSExpression expressionWithFormat:@"a - b - 1"], object) == 5.0,
	      "same-precedence operators read left to right");
	check(ValueIn([NSExpression expressionWithFormat:@"a + b * 2 ** 2"], object) == 16.0,
	      "** binds tighter than *");
	text = [NSExpression expressionWithFormat:@"a + b * 2"];
	check([[[text fn_expressionFormat] description] isEqualToString:@"a + (b * 2)"],
	      "and the text it writes states the grouping");
	check([[[NSExpression expressionWithFormat:@"(a + b) * 2"] fn_expressionFormat]
	       isEqualToString:@"(a + b) * 2"], "including the parentheses that changed the answer");

	/* A SIGN IN OPERAND POSITION. A sign the number reader can use stays one constant, so `-1` is a constant and
	 * `-(a - b)` is one subtraction from zero rather than a syntax error. */
	check([[[NSExpression expressionWithFormat:@"-1"] constantValue] intValue] == -1,
	      "-1 is one constant, not a subtraction from zero");
	check(ValueIn([NSExpression expressionWithFormat:@"-(a - b)"], object) == -6.0,
	      "a sign before a group negates it");
	check(ValueIn([NSExpression expressionWithFormat:@"a * -b"], object) == -16.0,
	      "and a sign after an operator is the operand's");

	/* THE SUBSTITUTIONS ARE THE FORMAT'S, not the door's: `%@` is a constant, `%K` a key path, and `%d`/`%f`
	 * arrive from the varargs IN ORDER. `%d + 1` is the case the first attempt at this slice mis-diagnosed: the
	 * substitution was never the fault, the missing arithmetic was. */
	e = [NSExpression expressionWithFormat:@"%@", @"a string"];
	check([e expressionType] == NSConstantValueExpressionType, "%@ makes a constant expression");
	check([[e constantValue] isEqualToString:@"a string"], "with the object it was given");
	e = [NSExpression expressionWithFormat:@"%K", @"a"];
	check([e expressionType] == NSKeyPathExpressionType &&
	      [[e keyPath] isEqualToString:@"a"], "%K makes a key path");
	check(ValueIn([NSExpression expressionWithFormat:@"%d + 1", 41], object) == 42.0,
	      "%d substitutes and then the arithmetic runs");
	check(ValueIn([NSExpression expressionWithFormat:@"%d + %d", 3, 4], object) == 7.0,
	      "the variadic form takes more than one argument");
	check(ValueIn(ViaArguments(@"%f * %f", 1.5, 2.0), object) == 3.0,
	      "the va_list form collects doubles the same way");
	{
		NSArray *args = [NSArray arrayWithObjects:[NSNumber numberWithInt:3],
		                                          [NSNumber numberWithInt:4], nil];
		check(ValueIn([NSExpression expressionWithFormat:@"%d + %d" argumentArray:args], object) == 7.0,
		      "and the argumentArray: form agrees with both");
	}

	/* A SELECTOR-SHAPED FUNCTION NAME READS BACK, which is what makes `modulus:by:` — the one arithmetic function
	 * with no operator — survive -fn_expressionFormat. */
	e = [NSExpression expressionWithFormat:@"modulus:by:(a, b)"];
	check([[e function] isEqualToString:@"modulus:by:"], "a trailing colon is part of the function name");
	check(ValueIn(e, object) == 0.0, "and the function evaluates");
	check([[[NSExpression expressionWithFormat:@"uppercase:(%@)", @"x"] function]
	       isEqualToString:@"uppercase:"], "as it is for a single-colon function");

	/* A COMPARISON IS A PREDICATE, AND THE REFUSAL NAMES THE DOOR THAT READS ONE. Returning the left side and
	 * dropping the operator — what a scanner that does not check for trailing text does — would make `a < 2` mean
	 * `a`, silently. */
	check(Raises(@"1 < 2", nil, @"predicateWithFormat"),
	      "a comparison is refused, and the message names +predicateWithFormat:");
	check(Raises(@"a == b", nil, @"predicateWithFormat"), "equality too");
	check(Raises(@"%d + %d", [NSArray arrayWithObject:[NSNumber numberWithInt:1]], @"more format conversions"),
	      "more conversions than arguments is refused, by name");
	check(Raises(@"1 2", nil, @"unexpected text"), "and so is text the grammar cannot honour");

	/* THE PREDICATE GRAMMAR DID NOT MOVE. The parenthesis refusal, and its wording, are still the predicate
	 * door's — the flag adds a grammar, it does not relax one. */
	{
		BOOL raised = NO;
		@try {
			(void)[NSPredicate predicateWithFormat:@"a == (b)"];
		} @catch (NSException *x) {
			raised = [[x reason] rangeOfString:@"parenthesised expression"].location != NSNotFound;
		}
		check(raised, "the predicate grammar still refuses a parenthesised operand, by name");
	}

	/* THE ROUND TRIP, over every shape above that the renderer writes. */
	check(RoundTrips(@"a + b", object), "a + b round-trips");
	check(RoundTrips(@"a + b * 2", object), "a + b * 2 round-trips");
	check(RoundTrips(@"(a + b) * 2", object), "(a + b) * 2 round-trips");
	check(RoundTrips(@"a ** b + 1", object), "a ** b + 1 round-trips");
	check(RoundTrips(@"-(a - b)", object), "-(a - b) round-trips");
	check(RoundTrips(@"modulus:by:(a, b)", object), "modulus:by:(a, b) round-trips");

	printf("expression_format: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
