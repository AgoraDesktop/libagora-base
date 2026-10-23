/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSKeyValueCoding.m — the naming rules, on the runtime's ivar table.
 * docs/design/foundation-plan.md, F9.
 *
 * MANUAL OWNERSHIP. It owns the temporary strings it builds; nothing else.
 *
 * THE LOOKUP ORDER IS THE SPECIFICATION, so it is written once, in this order:
 *
 *   reading   -get<Key>, -<key>, -is<Key>, then the ivars _<key>, _is<Key>,
 *             <key>, is<Key>
 *   writing   -set<Key>:, then the ivars _<key>, <key>
 *
 * where <Key> is the key with its first letter CAPITALISED and <key> is the key
 * as given. Both readings go through the same helpers, so a key cannot resolve
 * one way when read and another when written.
 *
 * THE IVAR ARM IS THE RUNTIME'S. `class_getInstanceVariable` finds an ivar by
 * name — INCLUDING one a superclass declared, which is why the probe tests that
 * case — and `object_getIvar`/`object_setIvar` handle object-typed ones. A
 * SCALAR ivar is not an object, so it is read through its `ivar_getTypeEncoding`
 * and boxed: that is the one place this file touches raw memory, and it is the
 * reason the type switch exists rather than a cast.
 *
 * NOTHING HERE OBSERVES. KVO is refused by name in the header: it is a registry,
 * not a rule.
 */

#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNull.h>	/* the mapping keeps its SHAPE: nil becomes NSNull */
#import <Foundation/NSException.h>
#import <Foundation/NSError.h>
#import <Foundation/NSMethodSignature.h>
#import <objc/runtime.h>
#import "NSKeyValueObserving_internal.h"
#include <string.h>

/* The operator arm is implemented with the fold, BELOW the class that calls it,
 * so it is declared here. A private category is the house's way of saying
 * "in this file only". */
@interface NSObject (FNKeyValueOperators)
- (nullable id)fnValueForKeyPathOperator:(NSString *)keyPath;
@end

/* ---------------------------------------------------------- key spellings */

static NSString *fn_capitalise(NSString *key)
{
	NSMutableString *out;
	NSString *head;

	if ([key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 0) {
		return key;
	}
	head = [[key substringToIndex:1] uppercaseString];
	out = [[NSMutableString alloc] init];
	[out appendString:head];
	[out appendString:[key substringFromIndex:1]];
	return out;
}

/* The selector names the order is built from: "get" + Key, Key, "is" + Key. */
static NSString *fn_prefixed(NSString *prefix, NSString *key)
{
	NSMutableString *out = [[NSMutableString alloc] initWithString:prefix];

	[out appendString:key];
	return out;
}

static SEL fn_selector_for_name(NSString *name, BOOL withColon)
{
	NSMutableString *text = [[NSMutableString alloc] initWithString:name];
	SEL found;

	if (withColon) {
		[text appendString:@":"];
	}
	found = sel_registerName([text UTF8String]);
	return found;
}

/* ------------------------------------------------------------- the ivars */

/* Read the ivar as an OBJECT, boxing a scalar. `*found` says whether the ivar
 * EXISTS, which is a different question from whether its value is nil — an
 * object ivar holding nil is FOUND and answers nil, and collapsing the two would
 * walk past it to the next spelling and then raise. */
static id fn_ivar_value(id object, Class cls, NSString *name, BOOL *found)
{
	Ivar ivar;
	const char *type;
	void *slot;

	*found = NO;
	ivar = class_getInstanceVariable(cls, [name UTF8String]);
	if (ivar == NULL) {
		return nil;
	}
	*found = YES;
	type = ivar_getTypeEncoding(ivar);
	slot = (char *)(__bridge void *)object + ivar_getOffset(ivar);
	if (type == NULL) {
		return nil;
	}
	switch (type[0]) {
	case '@':
	case '#':
		return *(id __unsafe_unretained *)slot;
	case ':':
		return [NSString stringWithUTF8String:sel_getName(*(SEL *)slot)];
	case 'c': case 'C': return [NSNumber numberWithInt:(int)*(unsigned char *)slot];
	case 's': case 'S': return [NSNumber numberWithInt:(int)*(short *)slot];
	case 'i': case 'I': return [NSNumber numberWithInt:*(int *)slot];
	case 'l': case 'L': return [NSNumber numberWithLong:*(long *)slot];
	case 'q': case 'Q': return [NSNumber numberWithLongLong:*(long long *)slot];
	case 'B': return [NSNumber numberWithBool:(*(unsigned char *)slot) ? YES : NO];
	case 'f': return [NSNumber numberWithFloat:*(float *)slot];
	case 'd': return [NSNumber numberWithDouble:*(double *)slot];
	default: return nil;
	}
}

/* ------------------------------------------------------------ the accessors */

/* AN ACCESSOR IS CALLED THROUGH ITS OWN RETURN TYPE, not through
 * -performSelector:, and that is not a nicety: -performSelector: is typed as
 * returning `id`, so a getter returning a SCALAR hands that number back as if it
 * were a pointer. Cocoa boxes a scalar accessor's result, and so does this — the
 * type switch below IS the boxing. Its absence is what the first run of the
 * probe died on: the value 20, read as an address. */
static id fn_call_accessor(id receiver, SEL sel)
{
	NSMethodSignature *signature = [receiver methodSignatureForSelector:sel];
	const char *type = signature != nil ? [signature methodReturnType] : NULL;

	if (type == NULL) {
		return nil;
	}
	switch (type[0]) {
	case '@': case '#': case '^': case '?': {
		typedef id (*fn_object)(id, SEL);

		return ((fn_object)[receiver methodForSelector:sel])(receiver, sel);
	}
	case ':': {
		typedef SEL (*fn_selector)(id, SEL);

		return [NSString stringWithUTF8String:sel_getName(
			((fn_selector)[receiver methodForSelector:sel])(receiver, sel))];
	}
	case 'c': case 'C': case 'B': {
		typedef unsigned char (*fn_u8)(id, SEL);

		return [NSNumber numberWithInt:
			(int)((fn_u8)[receiver methodForSelector:sel])(receiver, sel)];
	}
	case 's': case 'S': {
		typedef short (*fn_i16)(id, SEL);

		return [NSNumber numberWithInt:
			(int)((fn_i16)[receiver methodForSelector:sel])(receiver, sel)];
	}
	case 'i': case 'I': {
		typedef int (*fn_i32)(id, SEL);

		return [NSNumber numberWithInt:
			((fn_i32)[receiver methodForSelector:sel])(receiver, sel)];
	}
	case 'l': case 'L': {
		typedef long (*fn_long)(id, SEL);

		return [NSNumber numberWithLong:
			((fn_long)[receiver methodForSelector:sel])(receiver, sel)];
	}
	case 'q': case 'Q': {
		typedef long long (*fn_i64)(id, SEL);

		return [NSNumber numberWithLongLong:
			((fn_i64)[receiver methodForSelector:sel])(receiver, sel)];
	}
	case 'f': {
		typedef float (*fn_f32)(id, SEL);

		return [NSNumber numberWithFloat:
			((fn_f32)[receiver methodForSelector:sel])(receiver, sel)];
	}
	case 'd': {
		typedef double (*fn_f64)(id, SEL);

		return [NSNumber numberWithDouble:
			((fn_f64)[receiver methodForSelector:sel])(receiver, sel)];
	}
	default:
		/* A struct or a void return is not a value to answer with. */
		return nil;
	}
}

/* And the same on the way IN. NO means the setter cannot take this value, which
 * the caller turns into -setNilValueForKey: — there is ONE place that decides
 * what happens to a nil, and it is the hook. */
static BOOL fn_call_setter(id receiver, SEL sel, id value)
{
	NSMethodSignature *signature = [receiver methodSignatureForSelector:sel];
	const char *type = signature != nil && [signature numberOfArguments] == 3
		? [signature getArgumentTypeAtIndex:2] : NULL;

	if (type == NULL) {
		return NO;
	}
	/* **NIL IS LEGAL FOR AN OBJECT SETTER AND ILLEGAL FOR A SCALAR ONE, AND THE TYPE HAS TO BE ASKED FIRST.** This
	 * used to refuse every nil before looking at the argument, so `-setValue:nil forKey:` raised "cannot set nil for the
	 * scalar key" for an `id` property whose setter takes nil perfectly well — the binding layer's null placeholder is
	 * the caller that measured it. A pointer, a Class or a block takes nil too; a scalar still goes to
	 * `-setNilValueForKey:`. */
	if (value == nil) {
		switch (type[0]) {
		case '@': case '#': case '^': case '?': {
			typedef void (*fn_object_nil)(id, SEL, id);

			((fn_object_nil)[receiver methodForSelector:sel])(receiver, sel, nil);
			return YES;
		}
		default:
			return NO;
		}
	}
	switch (type[0]) {
	case '@': case '#': case '^': case '?': {
		typedef void (*fn_object)(id, SEL, id);

		((fn_object)[receiver methodForSelector:sel])(receiver, sel, value);
		return YES;
	}
	case 'c': case 'C': case 'B': {
		typedef void (*fn_u8)(id, SEL, unsigned char);

		((fn_u8)[receiver methodForSelector:sel])(receiver, sel,
			(unsigned char)[value charValue]);
		return YES;
	}
	case 's': case 'S': {
		typedef void (*fn_i16)(id, SEL, short);

		((fn_i16)[receiver methodForSelector:sel])(receiver, sel,
			(short)[value shortValue]);
		return YES;
	}
	case 'i': case 'I': {
		typedef void (*fn_i32)(id, SEL, int);

		((fn_i32)[receiver methodForSelector:sel])(receiver, sel, [value intValue]);
		return YES;
	}
	case 'l': case 'L': {
		typedef void (*fn_long)(id, SEL, long);

		((fn_long)[receiver methodForSelector:sel])(receiver, sel,
			(long)[value longValue]);
		return YES;
	}
	case 'q': case 'Q': {
		typedef void (*fn_i64)(id, SEL, long long);

		((fn_i64)[receiver methodForSelector:sel])(receiver, sel,
			(long long)[value longLongValue]);
		return YES;
	}
	case 'f': {
		typedef void (*fn_f32)(id, SEL, float);

		((fn_f32)[receiver methodForSelector:sel])(receiver, sel, [value floatValue]);
		return YES;
	}
	case 'd': {
		typedef void (*fn_f64)(id, SEL, double);

		((fn_f64)[receiver methodForSelector:sel])(receiver, sel, [value doubleValue]);
		return YES;
	}
	default:
		return NO;
	}
}

/* ============================================================================================
 * THE MUTABLE COLLECTION PROXIES.
 * ============================================================================================ */
/* **A PROXY HOLDS AN OBJECT AND A KEY, AND EVERY PRIMITIVE GOES THROUGH THEM.** Both collection families are built
 * over a small primitive set — seven for the array, one for the set — so a subclass that overrides those primitives
 * and keeps its elements elsewhere is a live view rather than a copy. The array's seven include the fast-enumeration
 * word, which is why each proxy carries one of its own.
 *
 * **THE MUTATION IS ANNOUNCED EITHER AS A TO-MANY CHANGE OR AS A WHOLE-VALUE ONE, AND WHICH IS A FACT ABOUT THE
 * BACKING STORE.** A property that already holds an `NSMutableArray`/`NSMutableSet` is mutated IN PLACE, wrapped in
 * the to-many pair, so an observer gets the indexes and the affected objects; a property whose value is immutable (a
 * computed collection, a copy returned by its getter) is replaced by a mutable copy through `-setValue:forKey:`, so
 * the observer gets the ordinary setting change. That is the honest split, and a caller can tell which happened from
 * `NSKeyValueChangeKindKey`. */
@interface NSMutableSet (AGKVCMutableStorage)
- (void)fnReplaceMembers:(NSArray *)members;
- (unsigned long *)fnMutationWord;
@end

@interface NSArray (AGKVCMutableStorage)
- (unsigned long *)fnMutationWord;
@end

@interface FNKVMutableArray : NSMutableArray
{
	__unsafe_unretained id _target;	/* NOT retained: the proxy is a view of the caller's object */
	NSString *_key;			/* RETAINED (a copy) */
	unsigned long _mutationWord;
}
- (id)initWithTarget:(id)target key:(NSString *)key;
@end

@interface FNKVMutableSet : NSMutableSet
{
	__unsafe_unretained id _target;	/* NOT retained */
	NSString *_key;			/* RETAINED (a copy) */
	unsigned long _mutationWord;
}
- (id)initWithTarget:(id)target key:(NSString *)key;
@end

@implementation FNKVMutableArray

- (id)initWithTarget:(id)target key:(NSString *)key
{
	self = [super init];
	if (self != nil) {
		_target = target;
		_key = [key copy];
	}
	return self;
}

- (void)dealloc
{
	[_key release];
	[super dealloc];
}

- (NSMutableArray *)fn_collection
{
	id value = [_target valueForKey:_key];

	return [value isKindOfClass:[NSMutableArray class]] ? (NSMutableArray *)value : nil;
}

- (NSArray *)fn_view
{
	id value = [_target valueForKey:_key];

	return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : [NSArray array];
}

/* THE PRIMITIVES: TWO READS, FOUR MUTATIONS, AND THE WORD. */
- (NSUInteger)count
{
	return [[self fn_view] count];
}

- (id)objectAtIndex:(NSUInteger)index
{
	return [[self fn_view] objectAtIndex:index];
}

- (unsigned long *)fnMutationWord
{
	return &_mutationWord;
}

- (NSEnumerator *)objectEnumerator
{
	return [[self fn_view] objectEnumerator];
}

/* **THE IN-PLACE ARM IS THE ONE THAT NEEDS THE TO-MANY PAIR; THE COPY ARM DOES NOT.** Mutating the caller's mutable
 * array changes no property, so nothing else would announce it; replacing an immutable value through KVC announces
 * itself. A copy is built only when the value is not a mutable array — which includes a nil value, where the copy
 * starts empty and the property is created by the first insertion. */
- (void)fn_mutateInPlace:(NSKeyValueChange)kind
		 indexes:(NSIndexSet *)indexes
		mutation:(void (^)(NSMutableArray *array))mutation
{
	NSMutableArray *collection = [self fn_collection];

	if (collection != nil) {
		[_target willChange:kind valuesAtIndexes:indexes forKey:_key];
		mutation(collection);
		[_target didChange:kind valuesAtIndexes:indexes forKey:_key];
	} else {
		NSArray *current = [self fn_view];
		NSMutableArray *copy = [[NSMutableArray alloc] initWithArray:current];

		mutation(copy);
		[_target setValue:copy forKey:_key];
		[copy release];
	}
	_mutationWord++;
}

- (void)insertObject:(id)object atIndex:(NSUInteger)index
{
	if (object == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertObject:atIndex: needs an object"];
	}
	[self fn_mutateInPlace:NSKeyValueChangeInsertion
		       indexes:[NSIndexSet indexSetWithIndex:index]
		      mutation:^(NSMutableArray *array) {
		[array insertObject:object atIndex:index];
	}];
}

- (void)removeObjectAtIndex:(NSUInteger)index
{
	if (index >= [self count]) {
		[NSException raise:NSRangeException
			    format:@"-removeObjectAtIndex: %lu is outside 0..%lu",
				(unsigned long)index, (unsigned long)[self count]];
	}
	[self fn_mutateInPlace:NSKeyValueChangeRemoval
		       indexes:[NSIndexSet indexSetWithIndex:index]
		      mutation:^(NSMutableArray *array) {
		[array removeObjectAtIndex:index];
	}];
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)object
{
	if (index >= [self count]) {
		[NSException raise:NSRangeException
			    format:@"-replaceObjectAtIndex: %lu is outside 0..%lu",
				(unsigned long)index, (unsigned long)[self count]];
	}
	if (object == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-replaceObjectAtIndex:withObject: needs an object"];
	}
	[self fn_mutateInPlace:NSKeyValueChangeReplacement
		       indexes:[NSIndexSet indexSetWithIndex:index]
		      mutation:^(NSMutableArray *array) {
		[array replaceObjectAtIndex:index withObject:object];
	}];
}

- (void)removeAllObjects
{
	NSUInteger count = [self count];

	if (count == 0) {
		return;
	}
	[self fn_mutateInPlace:NSKeyValueChangeRemoval
		       indexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)]
		      mutation:^(NSMutableArray *array) {
		[array removeAllObjects];
	}];
}

@end

@implementation FNKVMutableSet

- (id)initWithTarget:(id)target key:(NSString *)key
{
	self = [super init];
	if (self != nil) {
		_target = target;
		_key = [key copy];
	}
	return self;
}

- (void)dealloc
{
	[_key release];
	[super dealloc];
}

- (NSSet *)fn_view
{
	id value = [_target valueForKey:_key];

	return [value isKindOfClass:[NSSet class]] ? (NSSet *)value : [NSSet set];
}

- (NSUInteger)count
{
	return [[self fn_view] count];
}

- (id)member:(id)object
{
	return [[self fn_view] member:object];
}

- (NSEnumerator *)objectEnumerator
{
	return [[self fn_view] objectEnumerator];
}

- (unsigned long *)fnMutationWord
{
	return &_mutationWord;
}

/* **THE SET'S ONE STORAGE PRIMITIVE IS `-fnReplaceMembers:`, SO THE DIFF IS COMPUTED HERE.** The base class's
 * `-addObject:`, `-removeObject:`, `-unionSet:`, `-minusSet:`, `-intersectSet:`, `-setSet:` and `-removeAllObjects` all
 * funnel through it with the new member list, which is what lets one override announce every one of them: the members
 * gained and lost are the difference between the current set and the new list, and their sizes choose the mutation
 * kind the KVO pair carries. */
- (void)fnReplaceMembers:(NSArray *)members
{
	NSSet *current = [self fn_view];
	NSSet *next = [NSSet setWithArray:members];
	NSMutableSet *added = [NSMutableSet setWithSet:next];
	NSMutableSet *removed = [NSMutableSet setWithSet:current];

	[added minusSet:current];
	[removed minusSet:next];
	if ([current isKindOfClass:[NSMutableSet class]]) {
		if ([added count] > 0 && [removed count] == 0) {
			[_target willChangeValueForKey:_key withSetMutation:NSKeyValueUnionSetMutation
					  usingObjects:added];
			[(NSMutableSet *)current unionSet:added];
			[_target didChangeValueForKey:_key withSetMutation:NSKeyValueUnionSetMutation
					 usingObjects:added];
		} else if ([removed count] > 0 && [added count] == 0) {
			[_target willChangeValueForKey:_key withSetMutation:NSKeyValueMinusSetMutation
					  usingObjects:removed];
			[(NSMutableSet *)current minusSet:removed];
			[_target didChangeValueForKey:_key withSetMutation:NSKeyValueMinusSetMutation
					 usingObjects:removed];
		} else if ([added count] > 0 || [removed count] > 0) {
			[_target willChangeValueForKey:_key withSetMutation:NSKeyValueSetSetMutation
					  usingObjects:next];
			[(NSMutableSet *)current setSet:next];
			[_target didChangeValueForKey:_key withSetMutation:NSKeyValueSetSetMutation
					 usingObjects:next];
		}
	} else if ([added count] > 0 || [removed count] > 0) {
		/* THE COPY ARM WRITES A MUTABLE SET, so the NEXT mutation is an in-place one; an immutable copy would make
		 * every later change a setting change and keep the proxy from ever reaching the to-many path. */
		[_target setValue:[NSMutableSet setWithSet:next] forKey:_key];
	}
	_mutationWord++;
}

@end

/* ------------------------------------------------------------------ NSObject */

@implementation NSObject (NSKeyValueCoding)

- (nullable id)valueForKey:(NSString *)key
{
	NSString *capitalised = fn_capitalise(key);
	NSString *name;
	SEL sel;
	Class cls;

	if (key == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-valueForKey: needs a key"];
	}
	/* 1. the accessors, in Cocoa's order — each called through its OWN return
	 * type, because a scalar accessor's result must be boxed. */
	name = fn_prefixed(@"get", capitalised);
	sel = fn_selector_for_name(name, NO);
	if ([self respondsToSelector:sel]) {
		return fn_call_accessor(self, sel);
	}
	sel = fn_selector_for_name(key, NO);
	if ([self respondsToSelector:sel]) {
		return fn_call_accessor(self, sel);
	}
	name = fn_prefixed(@"is", capitalised);
	sel = fn_selector_for_name(name, NO);
	if ([self respondsToSelector:sel]) {
		return fn_call_accessor(self, sel);
	}
	/* 2. the ivars, in Cocoa's order — including a superclass's. `found` is what
	 * makes an ivar holding nil answer nil rather than being skipped. */
	cls = object_getClass(self);
	{
		BOOL found = NO;
		id value;

		value = fn_ivar_value(self, cls, fn_prefixed(@"_", key), &found);
		if (found) {
			return value;
		}
		value = fn_ivar_value(self, cls, fn_prefixed(@"_is", capitalised), &found);
		if (found) {
			return value;
		}
		value = fn_ivar_value(self, cls, key, &found);
		if (found) {
			return value;
		}
		value = fn_ivar_value(self, cls, fn_prefixed(@"is", capitalised), &found);
		if (found) {
			return value;
		}
	}
	/* 3. the hook, which raises by default. */
	return [self valueForUndefinedKey:key];
}

/* THE OBSERVING WRAPPER: every KVC write goes through here, so a change made with
 * -setValue:forKey: is announced to KVO automatically. The body is unchanged and now lives in
 * -fnSetValue:forKey:, which is what makes "automatic" mean the same thing here as in Cocoa for
 * this library's writers. */
- (void)setValue:(nullable id)value forKey:(NSString *)key
{
	/* **ONE ANNOUNCEMENT PER WRITE, WHICHEVER DOOR IT CAME THROUGH.** When the object's class carries KVO's automatic
	 * setter for this key, THAT wrapper is the announcer and this one must stay quiet; when it does not — an unwrapped
	 * scalar/struct, an ivar write with no setter, or a dotted key — this is the only announcement there is. The seam
	 * asks the class, not this call, which is what keeps the two doors from disagreeing. */
	BOOL autoNotifies = fn_kvo_auto_notifies(self, key);

	if (!autoNotifies) {
		[self willChangeValueForKey:key];
	}
	[self fnSetValue:value forKey:key];
	if (!autoNotifies) {
		[self didChangeValueForKey:key];
	}
}

- (void)fnSetValue:(nullable id)value forKey:(NSString *)key
{
	SEL sel;
	Class cls;

	if (key == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-setValue:forKey: needs a key"];
	}
	sel = fn_selector_for_name(fn_prefixed(@"set", fn_capitalise(key)), YES);
	if ([self respondsToSelector:sel]) {
		if (fn_call_setter(self, sel, value)) {
			return;
		}
		/* The setter is there but cannot take this value — a nil through a
		 * SCALAR setter — and what that means is the hook's question. */
		[self setNilValueForKey:key];
		return;
	}
	/* The ivars, object-typed first: a nil through an object ivar is legal, and
	 * that is the difference the scalar arm below has to refuse. */
	cls = object_getClass(self);
	{
		NSString *underscored = fn_prefixed(@"_", key);
		Ivar ivar = class_getInstanceVariable(cls, [underscored UTF8String]);

		if (ivar == NULL) {
			ivar = class_getInstanceVariable(cls, [key UTF8String]);
		}
		if (ivar != NULL) {
			const char *type = ivar_getTypeEncoding(ivar);
			void *slot = (char *)(__bridge void *)self + ivar_getOffset(ivar);

			if (type != NULL && (type[0] == '@' || type[0] == '#')) {
				object_setIvar(self, ivar, value);
				return;
			}
			/* A SCALAR cannot hold nil. Cocoa's -setNilValueForKey: is the
			 * hook for that, and it raises as implemented here. */
			if (value == nil) {
				[self setNilValueForKey:key];
				return;
			}
			if (type != NULL) {
				switch (type[0]) {
				case 'c': case 'C': case 'B':
					*(unsigned char *)slot = (unsigned char)[value charValue];
					return;
				case 's': case 'S':
					*(short *)slot = (short)[value shortValue];
					return;
				case 'i': case 'I':
					*(int *)slot = [value intValue];
					return;
				case 'l': case 'L':
					*(long *)slot = (long)[value longValue];
					return;
				case 'q': case 'Q':
					*(long long *)slot = [value longLongValue];
					return;
				case 'f':
					*(float *)slot = [value floatValue];
					return;
				case 'd':
					*(double *)slot = [value doubleValue];
					return;
				default:
					break;
				}
			}
		}
	}
	[self setValue:value forUndefinedKey:key];
}

- (nullable id)valueForKeyPath:(NSString *)keyPath
{
	NSRange dot;

	if (keyPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-valueForKeyPath: needs a key path"];
	}
	/* AN @-LED FIRST SEGMENT IS AN OPERATOR, not a key, and that is the one rule
	 * this method has to decide before it walks anything. */
	if ([keyPath hasPrefix:@"@"]) {
		return [self fnValueForKeyPathOperator:keyPath];
	}
	dot = [keyPath rangeOfString:@"."];
	if (dot.location == NSNotFound) {
		return [self valueForKey:keyPath];
	}
	{
		NSString *head = [keyPath substringToIndex:dot.location];
		NSString *rest = [keyPath substringFromIndex:dot.location + 1];
		id step = [self valueForKey:head];

		/* A nil in the middle of a path answers nil: there is no object left to
		 * ask, which is Cocoa's behaviour and the only one that does not raise
		 * for a half-built graph. */
		if (step == nil) {
			return nil;
		}
		return [step valueForKeyPath:rest];
	}
}

- (void)setValue:(nullable id)value forKeyPath:(NSString *)keyPath
{
	NSRange dot = [keyPath rangeOfString:@"."];

	if (dot.location == NSNotFound) {
		[self setValue:value forKey:keyPath];
		return;
	}
	{
		NSString *head = [keyPath substringToIndex:dot.location];
		NSString *rest = [keyPath substringFromIndex:dot.location + 1];
		id step = [self valueForKey:head];

		if (step == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"-setValue:forKeyPath: cannot walk through a nil "
					   "at %@", head];
		}
		[step setValue:value forKeyPath:rest];
	}
}

/* ------------------------------------------------ the mutable collection proxies */

/* **THE PROXY IS ALWAYS ANSWERED; THE COLLECTION IT VIEWS MAY BE EMPTY.** A key with no value yet is a proxy whose
 * reads are empty and whose first insertion creates the property through `-setValue:forKey:` — which is exactly what a
 * binding on a not-yet-populated content array needs. */
- (NSMutableArray *)mutableArrayValueForKey:(NSString *)key
{
	if (key == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-mutableArrayValueForKey: needs a key"];
	}
	return [[[FNKVMutableArray alloc] initWithTarget:self key:key] autorelease];
}

- (NSMutableArray *)mutableArrayValueForKeyPath:(NSString *)keyPath
{
	NSRange dot;
	id head;

	if (keyPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-mutableArrayValueForKeyPath: needs a key path"];
	}
	dot = [keyPath rangeOfString:@"."];
	if (dot.location == NSNotFound) {
		return [self mutableArrayValueForKey:keyPath];
	}
	head = [self valueForKey:[keyPath substringToIndex:dot.location]];
	if (head == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-mutableArrayValueForKeyPath: cannot walk through a nil at %@",
				   [keyPath substringToIndex:dot.location]];
	}
	return [head mutableArrayValueForKey:[keyPath substringFromIndex:dot.location + 1]];
}

- (NSMutableSet *)mutableSetValueForKey:(NSString *)key
{
	if (key == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-mutableSetValueForKey: needs a key"];
	}
	return [[[FNKVMutableSet alloc] initWithTarget:self key:key] autorelease];
}

- (NSMutableSet *)mutableSetValueForKeyPath:(NSString *)keyPath
{
	NSRange dot;
	id head;

	if (keyPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-mutableSetValueForKeyPath: needs a key path"];
	}
	dot = [keyPath rangeOfString:@"."];
	if (dot.location == NSNotFound) {
		return [self mutableSetValueForKey:keyPath];
	}
	head = [self valueForKey:[keyPath substringToIndex:dot.location]];
	if (head == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-mutableSetValueForKeyPath: cannot walk through a nil at %@",
				   [keyPath substringToIndex:dot.location]];
	}
	return [head mutableSetValueForKey:[keyPath substringFromIndex:dot.location + 1]];
}

/* ------------------------------------------------ the hooks, and their defaults */

- (nullable id)valueForUndefinedKey:(NSString *)key
{
	[NSException raise:NSInvalidArgumentException
		    format:@"[%@ %@]: this class is not key value coding-compliant for "
			   "the key %@", [self class], @"valueForKey:", key];
	return nil;
}

- (void)setValue:(nullable id)value forUndefinedKey:(NSString *)key
{
	[NSException raise:NSInvalidArgumentException
		    format:@"[%@ %@]: this class is not key value coding-compliant for "
			   "the key %@", [self class], @"setValue:forKey:", key];
}

- (void)setNilValueForKey:(NSString *)key
{
	[NSException raise:NSInvalidArgumentException
		    format:@"[%@ %@]: cannot set nil for the scalar key %@",
			   [self class], @"setValue:forKey:", key];
}

/* The rule: a class MAY have a -validate<Key>:error:. Without one the value is
 * valid, which is the answer that does not invent a policy. */
- (BOOL)validateValue:(id _Nullable * _Nullable)ioValue
	       forKey:(NSString *)key
		error:(NSError * _Nullable * _Nullable)outError
{
	/* TWO COLONS: the rule is -validate<Key>:error:, which takes the value
	 * pointer AND the error pointer. One colon would look for a selector nothing
	 * implements, and EVERY value would come back valid — which is what the
	 * probe's first run measured, and why its detail reads "accepted a negative
	 * age" rather than a selector that could not be found. */
	NSString *name = [NSString stringWithFormat:@"validate%@:error:",
			  fn_capitalise(key)];
	SEL sel = sel_registerName([name UTF8String]);

	if ([self respondsToSelector:sel]) {
		typedef BOOL (*fn_validator)(id, SEL, id *, NSError **);
		fn_validator call = (fn_validator)[self methodForSelector:sel];

		return call(self, sel, ioValue, outError);
	}
	return YES;
}

@end

/* ------------------------------------------------------ the collection rules */

/* @sum and friends, over the values `-valueForKey:` produced. */
static id fn_fold(NSString *operator, NSArray *values)
{
	NSInteger count = (NSInteger)[values count];

	if ([operator isEqualToString:@"count"]) {
		return [NSNumber numberWithInteger:count];
	}
	if ([operator isEqualToString:@"unionOfObjects"]) {
		return values;
	}
	if ([operator isEqualToString:@"distinctUnionOfObjects"]) {
		NSMutableArray *distinct = [[NSMutableArray alloc] init];
		NSInteger i, j;

		for (i = 0; i < count; i++) {
			id candidate = [values objectAtIndex:(NSUInteger)i];
			BOOL seen = NO;

			for (j = 0; j < (NSInteger)[distinct count]; j++) {
				if ([[distinct objectAtIndex:(NSUInteger)j] isEqual:candidate]) {
					seen = YES;
					break;
				}
			}
			if (!seen) {
				[distinct addObject:candidate];
			}
		}
		return distinct;
	}
	/* THE FOUR COLLECTION UNIONS: unlike the folds above, the members' VALUES are themselves
	 * collections, and the answer is one of them. The grouping is by the value's FAMILY — arrays for
	 * @unionOfArrays/@distinctUnionOfArrays, sets for @unionOfSets/@distinctUnionOfSets — and the
	 * only pair that can differ in SIZE is the array pair, because a union of sets is already
	 * distinct. They are handled HERE, with @unionOfObjects, and NOT below the empty-collection
	 * guard: an empty collection has an empty answer rather than no answer. */
	if ([operator isEqualToString:@"unionOfArrays"] ||
	    [operator isEqualToString:@"distinctUnionOfArrays"]) {
		NSMutableArray *result = [NSMutableArray array];
		BOOL distinct = [operator isEqualToString:@"distinctUnionOfArrays"];
		NSInteger i;

		for (i = 0; i < count; i++) {
			NSArray *theirs = [values objectAtIndex:(NSUInteger)i];
			NSUInteger j;

			if (![theirs isKindOfClass:[NSArray class]]) {
				[NSException raise:NSInvalidArgumentException
					    format:@"@%@ expects every value to be an array, and found %@",
					   operator, [theirs class]];
			}
			for (j = 0; j < [theirs count]; j++) {
				id object = [theirs objectAtIndex:j];

				if (distinct && [result containsObject:object]) {
					continue;
				}
				[result addObject:object];
			}
		}
		return result;
	}
	if ([operator isEqualToString:@"unionOfSets"] ||
	    [operator isEqualToString:@"distinctUnionOfSets"]) {
		NSMutableSet *result = [NSMutableSet set];
		NSInteger i;

		for (i = 0; i < count; i++) {
			id theirs = [values objectAtIndex:(NSUInteger)i];

			if (![theirs isKindOfClass:[NSSet class]]) {
				[NSException raise:NSInvalidArgumentException
					    format:@"@%@ expects every value to be a set, and found %@",
					   operator, [theirs class]];
			}
			[result unionSet:theirs];
		}
		return result;
	}
	if (count == 0) {
		/* There is nothing to fold: sum is 0, and the others have no answer. */
		if ([operator isEqualToString:@"sum"]) {
			return [NSNumber numberWithInt:0];
		}
		[NSException raise:NSInvalidArgumentException
			    format:@"@%@ over an empty collection has no value", operator];
	}
	if ([operator isEqualToString:@"sum"] || [operator isEqualToString:@"avg"]) {
		double total = 0;
		NSInteger i;

		for (i = 0; i < count; i++) {
			total += [[values objectAtIndex:(NSUInteger)i] doubleValue];
		}
		if ([operator isEqualToString:@"avg"]) {
			return [NSNumber numberWithDouble:total / (double)count];
		}
		return [NSNumber numberWithDouble:total];
	}
	if ([operator isEqualToString:@"max"] || [operator isEqualToString:@"min"]) {
		id best = [values objectAtIndex:0];
		NSInteger i;

		for (i = 1; i < count; i++) {
			id candidate = [values objectAtIndex:(NSUInteger)i];
			NSComparisonResult order = [candidate compare:best];

			if ([operator isEqualToString:@"max"] ? order == NSOrderedDescending
							      : order == NSOrderedAscending) {
				best = candidate;
			}
		}
		return best;
	}
	[NSException raise:NSInvalidArgumentException
		    format:@"@%@ is not an operator this library implements "
			   "(@count, @sum, @avg, @max, @min, @unionOfObjects, "
			   "@distinctUnionOfObjects, @unionOfArrays, "
			   "@distinctUnionOfArrays, @unionOfSets, @distinctUnionOfSets)", operator];
	return nil;
}

@implementation NSObject (NSKeyValueCodingOperators)

/* -valueForKeyPath: with an @-led FIRST segment is an operator over the receiver
 * AS A COLLECTION — which is what `[array valueForKeyPath:@"@sum.price"]` is. */
- (nullable id)fnValueForKeyPathOperator:(NSString *)keyPath
{
	NSRange dot = [keyPath rangeOfString:@"."];
	NSString *operator = dot.location == NSNotFound
		? keyPath : [keyPath substringToIndex:dot.location];
	NSString *rest = dot.location == NSNotFound
		? nil : [keyPath substringFromIndex:dot.location + 1];
	NSArray *values;

	/*
	 * THE RECEIVER IS ANY COLLECTION, which is Apple's rule for the collection operators and
	 * what makes the three spellings of this family agree: an array folds over its ELEMENTS, a
	 * set over its MEMBERS, a dictionary over its VALUES — the same answer the -valueForKey:
	 * spelling next to it already gave for a dictionary, because that spelling routes an @-led
	 * key through [allValues valueForKeyPath:]. Until this arm accepted all three, one spelling
	 * raised where the other answered, inside this same library.
	 */
	if ([self isKindOfClass:[NSArray class]]) {
		values = (NSArray *)self;
	} else if ([self isKindOfClass:[NSSet class]]) {
		values = [(NSSet *)self allObjects];
	} else if ([self isKindOfClass:[NSDictionary class]]) {
		values = [(NSDictionary *)self allValues];
	} else {
		[NSException raise:NSInvalidArgumentException
			    format:@"the operator %@ needs a collection, and %@ is not one",
				   operator, [self class]];
		values = nil;	/* not reached: -raise: does not return */
	}
	if (rest == nil || [rest lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 0) {
		/* `@count` and the unions apply to the collection itself. */
		;
	} else {
		values = [values valueForKey:rest];
	}
	return fn_fold([operator substringFromIndex:1], values);
}

@end

@implementation NSArray (NSKeyValueCoding)

/* A MAP, Cocoa's override: the array of each element's value for the key. */
- (nullable id)valueForKey:(NSString *)key
{
	NSMutableArray *out = [[NSMutableArray alloc] init];
	NSUInteger count = [self count];
	NSUInteger i;

	for (i = 0; i < count; i++) {
		id element = [self objectAtIndex:i];
		id value = [element valueForKey:key];

		/* THE MAPPING KEEPS ITS SHAPE: a nil answer becomes NSNull. That is Cocoa's
		 * contract, and the difference is observable — the mapped array's count follows
		 * the RECEIVER's, so skipping the element changes the answer. The comment here
		 * used to say there was no NSNull, and it was true when it was written; NSNull
		 * shipped at F13.8c and the claim outlived its truth. */
		[out addObject:(value != nil) ? value : (id)[NSNull null]];
	}
	return out;
}

@end

@implementation NSDictionary (NSKeyValueCoding)

/* A LOOKUP, unless the key is `@`-led: then it FOLDS over the VALUES, which is
 * what makes `[dict valueForKey:@"@count"]` the number of entries. It is
 * `valueForKeyPath:` that folds (its operator arm), NOT `valueForKey:` — the
 * array's `valueForKey:` MAPS, and mapping an operator is not what is meant. */
- (nullable id)valueForKey:(NSString *)key
{
	if ([key hasPrefix:@"@"]) {
		return [[self allValues] valueForKeyPath:key];
	}
	return [self objectForKey:key];
}


/*
 * THE COLLECTION OPERATORS (W2f). The strings are Apple's published operator syntax, and they are
 * what `-valueForKeyPath:` is handed — see NSKeyValueCoding.h for why this family's values are
 * NOT ours to choose.
 */
NSString *const NSAverageKeyValueOperator = @"@avg";
NSString *const NSCountKeyValueOperator = @"@count";
NSString *const NSDistinctUnionOfArraysKeyValueOperator = @"@distinctUnionOfArrays";
NSString *const NSDistinctUnionOfObjectsKeyValueOperator = @"@distinctUnionOfObjects";
NSString *const NSDistinctUnionOfSetsKeyValueOperator = @"@distinctUnionOfSets";
NSString *const NSMaximumKeyValueOperator = @"@max";
NSString *const NSMinimumKeyValueOperator = @"@min";
NSString *const NSSumKeyValueOperator = @"@sum";
NSString *const NSUnionOfArraysKeyValueOperator = @"@unionOfArrays";
NSString *const NSUnionOfObjectsKeyValueOperator = @"@unionOfObjects";
NSString *const NSUnionOfSetsKeyValueOperator = @"@unionOfSets";

/* THE KVC ERROR CODE (W2f): a number whose only requirement is that the code RAISING it and the
 * code READING it agree, and both are in this library. */
NSInteger NSKeyValueValidationError = 1020;
@end
