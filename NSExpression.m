/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSExpression.m — MANUAL OWNERSHIP, like the rest of this library.
 *
 * THE CONSTRUCTORS ARE NOT SYMMETRIC AND THAT IS APPLE'S SHAPE, not an accident: `-initWithExpressionType:`
 * gives a type and nothing else, so a caller can build a key-path expression with `-initWithExpressionType:`
 * and set nothing, and every accessor will then answer nil. Apple's are total accessors over a payload that
 * may not be there; so are these.
 *
 * EVALUATION IS WHERE THE CLASS EARNS ITS EXISTENCE, and it is a dispatch on the type tag plus a small table
 * of function symbols. What is NOT implemented is named rather than approximated: an unknown function raises
 * `NSInvalidArgumentException` naming the symbol, because a function expression that silently evaluated to
 * nil would make `NSPredicate` disagree with `+predicateWithFormat:` about the same text.
 *
 * `-collection` and `-arguments` are the two accessors whose return type is the payload's, so they are the two
 * that a caller can be surprised by: an aggregate answers its subexpressions through `-collection`, and Apple
 * documents it that way. Both are caches of the same array here, because a subquery's source and an
 * aggregate's elements are both "the expressions this expression was built from".
 */

#import <Foundation/NSExpression.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
/* NSMutableSet lives in NSSet.h, as Apple puts it there */
#import <Foundation/NSDictionary.h>

#import <Foundation/NSNumber.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSCoder.h>
#include <math.h>
#include <stdlib.h>
#include <Block.h>

@implementation NSExpression

+ (NSExpression *)expressionForConstantValue:(id)obj
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSConstantValueExpressionType];
	e->_constantValue = [obj retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForEvaluatedObject
{
	return [[[self alloc] initWithExpressionType:NSEvaluatedObjectExpressionType] autorelease];
}

+ (NSExpression *)expressionForVariable:(NSString *)string
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSVariableExpressionType];
	e->_variable = [string retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSKeyPathExpressionType];
	e->_keyPath = [keyPath retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSFunctionExpressionType];
	e->_function = [name retain];
	e->_arguments = [parameters retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForAggregate:(NSArray *)subexpressions
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSAggregateExpressionType];
	e->_collection = [subexpressions retain];
	e->_arguments = [subexpressions retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSUnionSetExpressionType];
	e->_left = [left retain];
	e->_right = [right retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSIntersectSetExpressionType];
	e->_left = [left retain];
	e->_right = [right retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSMinusSetExpressionType];
	e->_left = [left retain];
	e->_right = [right retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForSubquery:(NSExpression *)expression
                 usingIteratorVariable:(NSString *)variable
                             predicate:(id)predicate
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSSubqueryExpressionType];
	e->_collection = [expression retain];
	e->_variable = [variable retain];
	e->_predicate = [predicate retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForFunction:(NSExpression *)target
                           selectorName:(NSString *)name
                              arguments:(NSArray *)parameters
{
	NSExpression *e = [[self alloc] initWithExpressionType:NSFunctionExpressionType];
	e->_operand = [target retain];
	e->_function = [name retain];
	e->_arguments = [parameters retain];
	return [e autorelease];
}

+ (NSExpression *)expressionForBlock:(id (^)(id, NSArray *, NSMutableDictionary *))block
                           arguments:(NSArray *)arguments
{
	/* A BLOCK EXPRESSION IS A 10.6 ADDITION AND ITS PAYLOAD IS THE BLOCK ITSELF. The block is copied because
	 * it may be stack-allocated where it was written and outlive that frame — the same rule `NSPredicate`'s
	 * `+predicateWithBlock:` follows, and the reason both use `Block_copy`'s Foundation spelling. */
	NSExpression *e = [[self alloc] initWithExpressionType:NSBlockExpressionType];
	/* Block_copy, NOT -copy: see the note in NSPredicate.m's FNBlockPredicate. */
	e->_constantValue = Block_copy(block);
	e->_arguments = [arguments retain];
	return [e autorelease];
}

- (id)initWithExpressionType:(NSExpressionType)type
{
	self = [super init];
	if (self != nil) {
		_type = type;
	}
	return self;
}

- (void)dealloc
{
	/* A BLOCK PAYLOAD IS RELEASED WITH Block_release, not -release. */
	if (_type == NSBlockExpressionType && _constantValue != NULL) {
		Block_release(_constantValue);
	} else {
		[_constantValue release];
	}
	[_keyPath release];
	[_variable release];
	[_function release];
	[_arguments release];
	[_collection release];
	[_predicate release];
	[_operand release];
	[_left release];
	[_right release];
	[super dealloc];
}

- (NSExpressionType)expressionType { return _type; }
- (id)constantValue { return _constantValue; }
- (NSString *)keyPath { return _keyPath; }
- (NSString *)function { return _function; }
- (NSString *)variable { return _variable; }
- (NSExpression *)operand { return _operand; }
- (NSArray *)arguments { return _arguments; }
- (id)collection { return _collection; }
- (NSPredicate *)predicate { return _predicate; }
- (NSExpression *)leftExpression { return _left; }
- (NSExpression *)rightExpression { return _right; }

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	NSExpression *e = [[NSExpression allocWithZone:zone] initWithExpressionType:_type];
	e->_constantValue = [_constantValue retain];
	e->_keyPath = [_keyPath retain];
	e->_variable = [_variable retain];
	e->_function = [_function retain];
	e->_arguments = [_arguments retain];
	e->_collection = [_collection retain];
	e->_predicate = [_predicate retain];
	e->_operand = [_operand retain];
	e->_left = [_left retain];
	e->_right = [_right retain];
	return e;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInteger:(NSInteger)_type forKey:@"NSExpressionType"];
	[coder encodeObject:_constantValue forKey:@"NSConstantValue"];
	[coder encodeObject:_keyPath forKey:@"NSKeyPath"];
	[coder encodeObject:_variable forKey:@"NSVariable"];
	[coder encodeObject:_function forKey:@"NSFunction"];
	[coder encodeObject:_arguments forKey:@"NSArguments"];
	[coder encodeObject:_collection forKey:@"NSCollection"];
	[coder encodeObject:_predicate forKey:@"NSPredicate"];
	[coder encodeObject:_operand forKey:@"NSOperand"];
	[coder encodeObject:_left forKey:@"NSLeft"];
	[coder encodeObject:_right forKey:@"NSRight"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil) {
		_type = (NSExpressionType)[coder decodeIntegerForKey:@"NSExpressionType"];
		_constantValue = [[coder decodeObjectForKey:@"NSConstantValue"] retain];
		_keyPath = [[coder decodeObjectForKey:@"NSKeyPath"] retain];
		_variable = [[coder decodeObjectForKey:@"NSVariable"] retain];
		_function = [[coder decodeObjectForKey:@"NSFunction"] retain];
		_arguments = [[coder decodeObjectForKey:@"NSArguments"] retain];
		_collection = [[coder decodeObjectForKey:@"NSCollection"] retain];
		_predicate = [[coder decodeObjectForKey:@"NSPredicate"] retain];
		_operand = [[coder decodeObjectForKey:@"NSOperand"] retain];
		_left = [[coder decodeObjectForKey:@"NSLeft"] retain];
		_right = [[coder decodeObjectForKey:@"NSRight"] retain];
	}
	return self;
}

/* ---- the evaluation table ------------------------------------------------------------------------- */

static NSArray *FNCollectionOf(id value)
{
	if (value == nil) {
		return nil;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSSet class]]) {
		return [value allObjects];
	}
	return nil;
}

/* ONE AGGREGATE OVER A COLLECTION, and it takes the name so the refusal can name what it was given. */
static id FNAggregate(NSString *function, NSArray *values)
{
	NSUInteger i, n = [values count];
	double total = 0.0;
	double best = 0.0;
	NSUInteger matched = 0;

	for (i = 0; i < n; i++) {
		id v = [values objectAtIndex:i];
		if (v == nil || ![v respondsToSelector:@selector(doubleValue)]) {
			continue;
		}
		double d = [v doubleValue];
		if (matched == 0) {
			best = d;
		} else if ([function isEqualToString:@"max:"]) {
			if (d > best) { best = d; }
		} else if ([function isEqualToString:@"min:"]) {
			if (d < best) { best = d; }
		}
		total += d;
		matched++;
	}
	if (matched == 0) {
		return nil;
	}
	if ([function isEqualToString:@"count:"]) {
		return [NSNumber numberWithInteger:(NSInteger)n];
	}
	if ([function isEqualToString:@"sum:"]) {
		return [NSNumber numberWithDouble:total];
	}
	if ([function isEqualToString:@"average:"]) {
		return [NSNumber numberWithDouble:(total / (double)matched)];
	}
	return [NSNumber numberWithDouble:best];
}

- (id)_valueOfArgument:(NSUInteger)index object:(id)object context:(NSMutableDictionary *)context
{
	if (_arguments == nil || index >= [_arguments count]) {
		return nil;
	}
	return [[_arguments objectAtIndex:index] expressionValueWithObject:object context:context];
}

- (id)expressionValueWithObject:(id)object context:(NSMutableDictionary *)context
{
	switch (_type) {
	case NSConstantValueExpressionType:
		return _constantValue;

	case NSEvaluatedObjectExpressionType:
		return object;

	case NSVariableExpressionType:
		return [context objectForKey:_variable];

	case NSKeyPathExpressionType:
		if ([_keyPath isEqualToString:@"SELF"]) {
			return object;
		}
		return [object valueForKeyPath:_keyPath];

	case NSAggregateExpressionType: {
		NSMutableArray *out = [[NSMutableArray alloc] init];
		NSUInteger i, n = [_arguments count];
		for (i = 0; i < n; i++) {
			id v = [[_arguments objectAtIndex:i] expressionValueWithObject:object context:context];
			if (v != nil) {
				[out addObject:v];
			}
		}
		return [out autorelease];
	}

	case NSUnionSetExpressionType:
	case NSIntersectSetExpressionType:
	case NSMinusSetExpressionType: {
		NSArray *l = FNCollectionOf([_left expressionValueWithObject:object context:context]);
		NSArray *r = FNCollectionOf([_right expressionValueWithObject:object context:context]);
		NSMutableSet *out = [[NSMutableSet alloc] init];
		NSUInteger i;
		if (l != nil) {
			for (i = 0; i < [l count]; i++) { [out addObject:[l objectAtIndex:i]]; }
		}
		if (_type == NSUnionSetExpressionType) {
			if (r != nil) {
				for (i = 0; i < [r count]; i++) { [out addObject:[r objectAtIndex:i]]; }
			}
		} else {
			NSSet *keep = (r != nil) ? [NSSet setWithArray:r] : [NSSet set];
			NSArray *all = [out allObjects];
			for (i = 0; i < [all count]; i++) {
				id v = [all objectAtIndex:i];
				BOOL inRight = [keep containsObject:v];
				BOOL wanted = (_type == NSIntersectSetExpressionType) ? inRight : !inRight;
				if (!wanted) { [out removeObject:v]; }
			}
		}
		return [out autorelease];
	}

	case NSSubqueryExpressionType: {
		NSArray *source = FNCollectionOf([_collection expressionValueWithObject:object context:context]);
		NSMutableDictionary *inner = [[NSMutableDictionary alloc] init];
		NSUInteger i, hits = 0;
		if (source != nil) {
			for (i = 0; i < [source count]; i++) {
				id v = [source objectAtIndex:i];
				[inner setObject:v forKey:_variable];
				if ([_predicate evaluateWithObject:v substitutionVariables:inner]) {
					hits++;
				}
			}
		}
		[inner release];
		return [NSNumber numberWithInteger:(NSInteger)hits];
	}

	case NSFunctionExpressionType: {
		/* THE SELECTOR FORM: `FUNCTION(receiver, "selector", args…)`, which has an OPERAND and invokes a method on
		 * it rather than looking the name up in the table below. Zero, one and two arguments are supported, which is
		 * what `-performSelector:` declares; more is refused by name. */
		if (_operand != nil) {
			id target = [_operand expressionValueWithObject:object context:context];
			SEL selector = NSSelectorFromString(_function);
			NSUInteger n = [_arguments count];

			if (selector == NULL) {
				[NSException raise:NSInvalidArgumentException
				            format:@"NSExpression: FUNCTION names the selector `%@`, which does not exist", _function];
			}
			if (target == nil) {
				return nil;
			}
			if (n == 0) {
				return [target performSelector:selector];
			}
			if (n == 1) {
				return [target performSelector:selector
				                    withObject:[[_arguments objectAtIndex:0] expressionValueWithObject:object
				                                                                                context:context]];
			}
			if (n == 2) {
				return [target performSelector:selector
				                    withObject:[[_arguments objectAtIndex:0] expressionValueWithObject:object
				                                                                                context:context]
				                    withObject:[[_arguments objectAtIndex:1] expressionValueWithObject:object
				                                                                                context:context]];
			}
			[NSException raise:NSInvalidArgumentException
			            format:@"NSExpression: FUNCTION(_, \"%@\") with %lu arguments; -performSelector: takes at most "
			                   @"two", _function, (unsigned long)n];
		}
		if ([_function isEqualToString:@"now"]) {
			return [NSDate date];
		}
		if ([_function isEqualToString:@"count:"] ||
		    [_function isEqualToString:@"sum:"] ||
		    [_function isEqualToString:@"min:"] ||
		    [_function isEqualToString:@"max:"] ||
		    [_function isEqualToString:@"average:"]) {
			id arg = [self _valueOfArgument:0 object:object context:context];
			NSArray *values = FNCollectionOf(arg);
			if (values == nil) {
				return ([_function isEqualToString:@"count:"]) ? [NSNumber numberWithInteger:0] : nil;
			}
			return FNAggregate(_function, values);
		}
		if ([_function isEqualToString:@"abs:"] || [_function isEqualToString:@"sqrt:"] ||
		    [_function isEqualToString:@"floor:"] || [_function isEqualToString:@"ceiling:"] ||
		    [_function isEqualToString:@"exp:"] || [_function isEqualToString:@"ln:"]) {
			id arg = [self _valueOfArgument:0 object:object context:context];
			double d = [arg doubleValue];
			if ([_function isEqualToString:@"abs:"]) { d = fabs(d); }
			else if ([_function isEqualToString:@"sqrt:"]) { d = sqrt(d); }
			else if ([_function isEqualToString:@"floor:"]) { d = floor(d); }
			else if ([_function isEqualToString:@"ceiling:"]) { d = ceil(d); }
			else if ([_function isEqualToString:@"exp:"]) { d = exp(d); }
			else { d = log(d); }
			return [NSNumber numberWithDouble:d];
		}
		if ([_function isEqualToString:@"add:to:"] || [_function isEqualToString:@"multiply:by:"] ||
		    [_function isEqualToString:@"from:subtract:"] || [_function isEqualToString:@"divide:by:"] ||
		    [_function isEqualToString:@"modulus:by:"]) {
			double a = [[self _valueOfArgument:0 object:object context:context] doubleValue];
			double b = [[self _valueOfArgument:1 object:object context:context] doubleValue];
			double r = a;
			if ([_function isEqualToString:@"add:to:"]) { r = a + b; }
			else if ([_function isEqualToString:@"multiply:by:"]) { r = a * b; }
			else if ([_function isEqualToString:@"from:subtract:"]) { r = a - b; }
			else if ([_function isEqualToString:@"divide:by:"]) { r = (b == 0.0) ? 0.0 : a / b; }
			else { r = (b == 0.0) ? 0.0 : fmod(a, b); }
			return [NSNumber numberWithDouble:r];
		}
		/* NOT A SILENT nil: an unknown symbol is a format the caller wrote and this tree cannot honour, and
		 * saying so here is the rule COREDATA-PLAN.md §4.3 asks for at every door. */
		[NSException raise:NSInvalidArgumentException
		            format:@"NSExpression: the function `%@` is not implemented (COREDATA-PLAN.md §4.1)", _function];
		return nil;
	}

	case NSBlockExpressionType: {
		id (^block)(id, NSArray *, NSMutableDictionary *) = (id (^)(id, NSArray *, NSMutableDictionary *))_constantValue;
		NSMutableArray *values = [[NSMutableArray alloc] init];
		NSUInteger i, n = [_arguments count];
		for (i = 0; i < n; i++) {
			id v = [[_arguments objectAtIndex:i] expressionValueWithObject:object context:context];
			[values addObject:(v != nil) ? v : (id)[NSNull null]];
		}
		id result = block(object, values, context);
		[values release];
		return result;
	}
	}
	return nil;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<NSExpression %p: type %lu>", (void *)self, (unsigned long)_type];
}

@end
