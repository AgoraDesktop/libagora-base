/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPredicate.m — the abstract base, the two constant predicates, and the collection categories.
 *
 * `+predicateWithValue:` AND `+predicateWithBlock:` ARE NOT SUBTLE AND ARE BOTH PRIVATE CLASSES: a predicate
 * that always answers YES is a predicate whose `-predicateFormat` is `TRUEPREDICATE`, which is a string the
 * parser produces too, so the two doors agree by construction rather than by coincidence.
 */

#import <Foundation/NSPredicate.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSExpression.h>
#import <Foundation/FNPredicatePrivate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#include <stdlib.h>

@interface FNValuePredicate : NSPredicate
{
	BOOL _value;
}
- (id)initWithValue:(BOOL)value;
@end

#if __has_feature(blocks)
@interface FNBlockPredicate : NSPredicate
{
	BOOL (^_block)(id, NSDictionary *);
}
- (id)initWithBlock:(BOOL (^)(id, NSDictionary *))block;
@end
#endif

@implementation FNValuePredicate

- (id)initWithValue:(BOOL)value
{
	self = [super init];
	if (self != nil) { _value = value; }
	return self;
}

- (BOOL)evaluateWithObject:(id)object { (void)object; return _value; }
- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings
{ (void)object; (void)bindings; return _value; }
- (NSString *)predicateFormat { return _value ? @"TRUEPREDICATE" : @"FALSEPREDICATE"; }
- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)v { (void)v; return self; }

- (id)copy
{
	return [[FNValuePredicate alloc] initWithValue:_value];
}

- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeBool:_value forKey:@"NSValue"]; }
- (id)initWithCoder:(NSCoder *)coder { return [self initWithValue:[coder decodeBoolForKey:@"NSValue"]]; }

@end

#if __has_feature(blocks)
@implementation FNBlockPredicate

- (id)initWithBlock:(BOOL (^)(id, NSDictionary *))block
{
	self = [super init];
	if (self != nil) { _block = [block copy]; }
	return self;
}

- (void)dealloc { [_block release]; [super dealloc]; }

- (BOOL)evaluateWithObject:(id)object { return _block(object, nil); }
- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings
{ return _block(object, bindings); }

/* A BLOCK CANNOT RENDER ITSELF, and saying `BLOCKPREDICATE` is honest about that: it is the same string the
 * parser refuses, so a block predicate cannot be saved and silently reloaded as something else. */
- (NSString *)predicateFormat { return @"BLOCKPREDICATE"; }
- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)v { (void)v; return self; }

- (id)copy
{
	return [[FNBlockPredicate alloc] initWithBlock:_block];
}

@end
#endif

@implementation NSPredicate

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat argumentArray:(NSArray *)arguments
{
	return FNParsePredicateFormat(predicateFormat, arguments);
}

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat, ...
{
	va_list ap;
	NSPredicate *p;
	va_start(ap, predicateFormat);
	p = [self predicateWithFormat:predicateFormat arguments:ap];
	va_end(ap);
	return p;
}

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat arguments:(va_list)argList
{
	/* THE ARGUMENTS ARE COLLECTED, NOT POSITIONALLY INTERPRETED HERE: `%K` and `%@` are interchangeable in
	 * position, so the parser has to see the format and the values together to know which door a given value
	 * came through. The list is walked once, here, into the array the parser reads. */
	NSMutableArray *values = [[NSMutableArray alloc] init];
	unichar *buf = NULL;
	NSUInteger i = 0, n = [predicateFormat length];

	buf = (unichar *)malloc(sizeof(unichar) * (n + 1));
	if (buf == NULL) {
		[values release];
		return nil;
	}
	for (i = 0; i < n; i++) { buf[i] = [predicateFormat characterAtIndex:i]; }

	i = 0;
	while (i < n) {
		if (buf[i] == '%' && i + 1 < n) {
			unichar c = buf[i + 1];
			if (c == '@' || c == 'K') {
				id obj = va_arg(argList, id);
				[values addObject:(obj != nil) ? obj : (id)[NSNull null]];
			} else if (c == 'd' || c == 'i') {
				[values addObject:[NSNumber numberWithInteger:(NSInteger)va_arg(argList, int)]];
			} else if (c == 'f' || c == 'g' || c == 'e') {
				[values addObject:[NSNumber numberWithDouble:va_arg(argList, double)]];
			}
			i += 2;
			continue;
		}
		i++;
	}
	free(buf);

	{
		NSPredicate *p = FNParsePredicateFormat(predicateFormat, values);
		[values release];
		return p;
	}
}

+ (NSPredicate *)predicateWithValue:(BOOL)value
{
	return [[[FNValuePredicate alloc] initWithValue:value] autorelease];
}

#if __has_feature(blocks)
+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id, NSDictionary *))block
{
	return [[[FNBlockPredicate alloc] initWithBlock:block] autorelease];
}
#endif

- (NSString *)predicateFormat { return @""; }
- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)variables { (void)variables; return self; }

- (BOOL)evaluateWithObject:(id)object { return [self evaluateWithObject:object substitutionVariables:nil]; }

- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings
{
	(void)object; (void)bindings;
	[NSException raise:NSInvalidArgumentException
	            format:@"NSPredicate: -evaluateWithObject: is abstract; use a concrete predicate"];
	return NO;
}

- (id)copy { return [self retain]; }
- (void)encodeWithCoder:(NSCoder *)coder { (void)coder; }
- (id)initWithCoder:(NSCoder *)coder { (void)coder; return self; }

@end

@implementation NSArray (NSPredicateSupport)

- (NSArray *)filteredArrayUsingPredicate:(NSPredicate *)predicate
{
	NSMutableArray *out = [[NSMutableArray alloc] init];
	NSUInteger i, n = [self count];

	for (i = 0; i < n; i++) {
		id v = [self objectAtIndex:i];
		if ([predicate evaluateWithObject:v]) {
			[out addObject:v];
		}
	}
	return [out autorelease];
}

@end

@implementation NSMutableArray (NSPredicateSupport)

- (void)filterUsingPredicate:(NSPredicate *)predicate
{
	NSArray *keep = [self filteredArrayUsingPredicate:predicate];
	[self setArray:keep];
}

@end

@implementation NSSet (NSPredicateSupport)

- (NSSet *)filteredSetUsingPredicate:(NSPredicate *)predicate
{
	NSMutableSet *out = [[NSMutableSet alloc] init];
	NSArray *all = [self allObjects];
	NSUInteger i, n = [all count];

	for (i = 0; i < n; i++) {
		id v = [all objectAtIndex:i];
		if ([predicate evaluateWithObject:v]) {
			[out addObject:v];
		}
	}
	return [out autorelease];
}

@end

@implementation NSMutableSet (NSPredicateSupport)

- (void)filterUsingPredicate:(NSPredicate *)predicate
{
	NSArray *all = [self allObjects];
	NSUInteger i, n = [all count];

	for (i = 0; i < n; i++) {
		id v = [all objectAtIndex:i];
		if (![predicate evaluateWithObject:v]) {
			[self removeObject:v];
		}
	}
}

@end
