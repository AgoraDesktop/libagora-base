/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * predicate — the family COREDATA-PLAN.md §4.1 restores, measured rather than declared.
 *
 * THIS SUITE EXISTS BECAUSE THE FAMILY WAS REMOVED WITHOUT ONE (§63.161), and a class that nothing calls is a
 * class nobody measures: the tree's own `string_split` suite records the same lesson about a split that hung
 * on its first caller. So every door here has a caller, and the two that matter most are the ones a
 * declaration cannot fake — `-evaluateWithObject:` over real objects, and the ROUND TRIP through
 * `-predicateFormat`, because Core Data loads predicates from strings in nib files and model resources.
 *
 * The object is a plain NSObject subclass with accessors, which is what `-valueForKeyPath:` meets in
 * application code, and the collections are the real ones: `-filteredArrayUsingPredicate:` is asked of an
 * NSArray, not of a bespoke loop.
 */

#import <Foundation/Foundation.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>

static int failures = 0;
static int checks = 0;

#define CHECK(cond, what) do { \
	checks++; \
	if (!(cond)) { failures++; fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, (what)); } \
} while (0)

@interface Person : NSObject
{
	NSString *_name;
	NSNumber *_age;
	NSArray *_tags;
}
- (id)initWithName:(NSString *)name age:(int)age tags:(NSArray *)tags;
- (NSString *)name;
- (NSNumber *)age;
- (NSArray *)tags;
@end

@implementation Person

- (id)initWithName:(NSString *)name age:(int)age tags:(NSArray *)tags
{
	self = [super init];
	if (self != nil) {
		_name = [name retain];
		_age = [[NSNumber alloc] initWithInt:age];
		_tags = [[NSArray alloc] initWithArray:tags];	/* a SNAPSHOT: the fixture reuses one mutable array */
	}
	return self;
}

- (void)dealloc { [_name release]; [_age release]; [_tags release]; [super dealloc]; }

- (NSString *)name { return _name; }
- (NSNumber *)age { return _age; }
- (NSArray *)tags { return _tags; }

@end

static NSArray *People(void)
{
	NSMutableArray *people = [[NSMutableArray alloc] init];
	NSMutableArray *t = [[NSMutableArray alloc] init];

	[t addObject:@"admin"];
	[t addObject:@"staff"];
	[people addObject:[[[Person alloc] initWithName:@"alice" age:40 tags:t] autorelease]];
	[t removeAllObjects];
	[t addObject:@"guest"];
	[people addObject:[[[Person alloc] initWithName:@"bob" age:25 tags:t] autorelease]];
	[t removeAllObjects];
	[t addObject:@"staff"];
	[people addObject:[[[Person alloc] initWithName:@"Carol" age:33 tags:t] autorelease]];
	[t release];
	return [people autorelease];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSArray *people = People();
	NSPredicate *p;
	NSArray *hits;

	/* 1. a comparison, on the object it names */
	p = [NSPredicate predicateWithFormat:@"age > 30"];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "age > 30 holds for 40");
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == NO, "age > 30 fails for 25");

	/* 2. AND, OR and NOT, with the precedence the grammar gives them */
	p = [NSPredicate predicateWithFormat:@"age > 30 AND name == \"alice\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "AND: 40 and alice");
	CHECK([p evaluateWithObject:[people objectAtIndex:2]] == NO, "AND: 33 and Carol");
	p = [NSPredicate predicateWithFormat:@"age < 30 OR age > 35"];
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == YES, "OR: 25");
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "OR: 40");
	CHECK([p evaluateWithObject:[people objectAtIndex:2]] == NO, "OR: 33");
	p = [NSPredicate predicateWithFormat:@"NOT (age > 30)"];
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == YES, "NOT over a group");

	/* 2b. `!=` AND `<>`, which nothing in this suite evaluated until a 10^5-row Core Data run found that the
	 * operator RECURSED FOR EVER — it called itself with the same operator, so the first `!=` in the tree
	 * overflowed the stack. A suite that tests `==` and not `!=` is a suite with a hole in it. */
	p = [NSPredicate predicateWithFormat:@"age != 40"];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == NO, "!= is false for 40");
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == YES, "and true for 25");
	p = [NSPredicate predicateWithFormat:@"age <> 40"];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == NO, "<> is the same operator");
	p = [NSPredicate predicateWithFormat:@"name != nil"];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "!= nil is true for a string");

	/* 3. the string operators, including the case-insensitive option */
	p = [NSPredicate predicateWithFormat:@"name BEGINSWITH[c] \"al\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "BEGINSWITH[c] al -> alice");
	p = [NSPredicate predicateWithFormat:@"name ENDSWITH \"ol\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:2]] == YES, "ENDSWITH ol -> Carol");

	/* 4. BETWEEN and IN, which take the aggregate braces */
	p = [NSPredicate predicateWithFormat:@"age BETWEEN {18, 30}"];
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == YES, "BETWEEN includes 25");
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == NO, "BETWEEN excludes 40");
	p = [NSPredicate predicateWithFormat:@"name IN {\"alice\", \"bob\"}"];
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == YES, "IN holds for bob");
	CHECK([p evaluateWithObject:[people objectAtIndex:2]] == NO, "IN fails for Carol");

	/* 5. ANY over a to-many, which is the modifier that makes a collection a value */
	p = [NSPredicate predicateWithFormat:@"ANY tags == \"staff\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "ANY tags == staff: alice");
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == NO, "ANY tags == staff: bob");
	p = [NSPredicate predicateWithFormat:@"ALL tags == \"staff\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:2]] == YES, "ALL tags == staff: Carol");
	p = [NSPredicate predicateWithFormat:@"NONE tags == \"admin\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == NO, "NONE tags == admin: alice has it");

	/* 6. the collection doors §63.161 removed */
	hits = [people filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"age >= 30"]];
	CHECK([hits count] == 2, "filteredArrayUsingPredicate keeps two of three");

	/* 7. substitution variables, which is the door Core Data's SUBQUERY uses */
	p = [NSPredicate predicateWithFormat:@"age > $floor"];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]
	        substitutionVariables:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:35] forKey:@"floor"]]
	      == YES, "substitution variables bind $floor");

	/* 8. the ROUND TRIP: what -predicateFormat prints must parse back to the same answers */
	p = [NSPredicate predicateWithFormat:@"age > 30 AND name BEGINSWITH \"a\""];
	{
		NSString *text = [p predicateFormat];
		NSPredicate *again = [NSPredicate predicateWithFormat:text];
		CHECK([again evaluateWithObject:[people objectAtIndex:0]] ==
		      [p evaluateWithObject:[people objectAtIndex:0]], "round trip: alice agrees");
		CHECK([again evaluateWithObject:[people objectAtIndex:1]] ==
		      [p evaluateWithObject:[people objectAtIndex:1]], "round trip: bob agrees");
	}

	/* 9. the two constants, and that a bare expression is a truth test */
	CHECK([[NSPredicate predicateWithValue:YES] evaluateWithObject:nil] == YES, "TRUEPREDICATE");
	CHECK([[NSPredicate predicateWithValue:NO] evaluateWithObject:nil] == NO, "FALSEPREDICATE");
	CHECK([[NSPredicate predicateWithFormat:@"TRUEPREDICATE"] evaluateWithObject:nil] == YES,
	      "TRUEPREDICATE parses");

	/* 9b. `FUNCTION(receiver, "selector")`, which the parser used to read as a function named `FUNCTION:` —
	 * the gap a 5,000-row Core Data suite found by tripping over it (§0.15). */
	p = [NSPredicate predicateWithFormat:@"FUNCTION(name, \"uppercaseString\") == \"ALICE\""];
	CHECK([p evaluateWithObject:[people objectAtIndex:0]] == YES, "FUNCTION(_, \"uppercaseString\") upper-cases");
	CHECK([p evaluateWithObject:[people objectAtIndex:1]] == NO, "and is false for bob");
	{
		NSString *text = [p predicateFormat];
		NSPredicate *again = [NSPredicate predicateWithFormat:text];

		CHECK([text rangeOfString:@"FUNCTION("].location != NSNotFound, "and renders back as FUNCTION(...)");
		CHECK([again evaluateWithObject:[people objectAtIndex:0]] ==
		      [p evaluateWithObject:[people objectAtIndex:0]], "which parses to the same answer");
	}
	{
		BOOL raised = NO;

		@try {
			(void)[[NSPredicate predicateWithFormat:@"FUNCTION(name, \"noSuchSelector\") == \"x\""]
			       evaluateWithObject:[people objectAtIndex:0]];
		} @catch (NSException *e) {
			raised = YES;
		}
		CHECK(raised == YES, "an unknown selector refuses by name rather than crashing");
	}

	/* 10. text this tree cannot honour REFUSES, and says where — the plan's §4.3 rule at the format door */
	{
		BOOL raised = NO;
		@try {
			(void)[NSPredicate predicateWithFormat:@"age > "];
		} @catch (NSException *e) {
			raised = YES;
		}
		CHECK(raised == YES, "a truncated predicate raises instead of parsing to something else");
	}

	printf("predicate: %d checks, %d failure(s)\n", checks, failures);
	[pool release];
	return (failures == 0) ? 0 : 1;
}
