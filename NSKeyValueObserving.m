/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSKeyValueObserving.m — the observer registry (F13.9). MANUAL OWNERSHIP.
 *
 * THE REGISTRY IS TWO TABLES AND NO IVARS, because NSObject's category cannot grow an instance and
 * this library has no associated objects. That is also why Cocoa's `-observationInfo` exists as a
 * door at all, and this file implements it as one — over its own table, kept separate from the
 * registry so a caller's bookkeeping cannot collide with it.
 *
 * NOTHING IS RETAINED: neither the observed object nor the observer, which is Cocoa's rule. The
 * tables hold `__unsafe_unretained` references, so removing observations before either object dies
 * is the caller's job exactly as it is in Cocoa.
 *
 * THE CHANGE IN FLIGHT is the interesting part. `-willChangeValueForKey:` captures the OLD value and
 * leaves a pending record; `-didChangeValueForKey:` reads the NEW value, builds one dictionary per
 * observer from the option bits that observer asked for, and clears the pending. So a change is
 * reported once, with the two values that surround it, and only to observers that wanted it.
 */

#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMethodSignature.h>
#import "FNObjectDeath.h"	/* §63.21: told when an object's address is going away */
#import "NSKeyValueObserving_internal.h"

#include <objc/runtime.h>	/* the automatic half: pairs, classes and IMPs */

/* ============================================================================================
 * AUTOMATIC NOTIFICATION: THE SETTER'S WRAPPER AND THE CLASS THAT CARRIES IT.
 * ============================================================================================ */
/* **A SETTER CALLED DIRECTLY IS THE CASE v1 COULD NOT SEE, AND THE ONE EVERY BINDING NEEDS.** `-setValue:forKey:`
 * announced its own writes, so a model written through KVC was observable; a model written as `[model setName:x]` —
 * which is what application code does — was not. The fix is Cocoa's own: when a key is first observed, the object is
 * moved to a DYNAMIC SUBCLASS that overrides the key's setter, and the override brackets the original IMP with
 * `-willChangeValueForKey:`/`-didChangeValueForKey:`. This file's slice does that without isa-swizzling's private
 * machinery: the subclass is created with `objc_allocateClassPair`, the original IMP is called through a typed
 * function pointer, and `-class` is overridden to keep answering the class the caller declared.
 *
 * **WHAT CANNOT BE INTERCEPTED IS NAMED, NOT FAKED.** A setter whose argument is a struct, a pointer, a C string or
 * a selector is not wrapped — the wrapper would have to know the ABI of every type — and a key with NO setter (the
 * KVC ivar path) has nothing to wrap. Both fall back to the documented manual pair, and `fn_kvo_auto_notifies` answers
 * NO so KVC's own wrapper still announces a `-setValue:forKey:` write exactly once. */
@interface FNAutoSetter : NSObject
{
@public
	Class _notifying;	/* the dynamic subclass (not retained: classes are permanent) */
	SEL _setter;		/* the wrapped selector */
	NSString *_key;		/* the key its wrapper announces */
	IMP _original;		/* the IMP the wrapper calls (not retained: code is permanent) */
}
@end

@implementation FNAutoSetter
- (void)dealloc
{
	[_key release];
	[super dealloc];
}
@end

/* ONE original-class -> notifying-class pair, so a second observation reuses the subclass. */
@interface FNKVONotifyingPair : NSObject
{
@public
	Class _original;
	Class _notifying;
}
@end

@implementation FNKVONotifyingPair
@end

static NSMutableArray *fn_autos = nil;
static NSMutableArray *fn_notify_pairs = nil;

/* THE DEPENDENT-KEY RELATION, in the two spellings Apple ships: the declarative `+keyPathsForValuesAffecting<Key>`
 * (which this file reads, not stores) and the deprecated per-class registration below. Class name -> key ->
 * set of dependent keys; class names are used as the outer key because a Class object is not a stable dictionary
 * key for a table that outlives a bundle unload. */
static NSMutableDictionary *fn_dependent_keys = nil;
static pthread_mutex_t fn_dependent_keys_lock = PTHREAD_MUTEX_INITIALIZER;

/* ONE THREAD'S KEYS IN FLIGHT, so a cycle in the dependent relation (A affects B affects A) terminates instead of
 * recursing until the stack ends. Thread-local and never freed: it lives for the thread's lifetime, and freeing it
 * from a thread with no pool would be the leak it is not worth fixing. */
static __thread NSMutableSet *fn_keys_in_flight = nil;

static NSString *fn_capitalised_key(NSString *key)
{
	if ([key length] == 0) {
		return key;
	}
	return [NSString stringWithFormat:@"%@%@", [[key substringToIndex:1] uppercaseString],
						 [key substringFromIndex:1]];
}

static BOOL fn_enter_key(NSString *key)
{
	if (fn_keys_in_flight == nil) {
		fn_keys_in_flight = [[NSMutableSet alloc] init];
	}
	if ([fn_keys_in_flight containsObject:key]) {
		return NO;
	}
	[fn_keys_in_flight addObject:key];
	return YES;
}

static void fn_leave_key(NSString *key)
{
	[fn_keys_in_flight removeObject:key];
}

static NSMutableSet *fn_registered_dependents(Class cls, NSString *key)
{
	NSString *className;
	NSMutableDictionary *byKey;
	NSMutableSet *dependents;

	pthread_mutex_lock(&fn_dependent_keys_lock);
	if (fn_dependent_keys == nil) {
		fn_dependent_keys = [[NSMutableDictionary alloc] init];
	}
	className = NSStringFromClass(cls);
	byKey = [fn_dependent_keys objectForKey:className];
	if (byKey == nil) {
		byKey = [NSMutableDictionary dictionary];
		[fn_dependent_keys setObject:byKey forKey:className];
	}
	dependents = [byKey objectForKey:key];
	if (dependents == nil) {
		dependents = [NSMutableSet set];
		[byKey setObject:dependents forKey:key];
	}
	pthread_mutex_unlock(&fn_dependent_keys_lock);
	return dependents;
}

static void fn_register_dependent(Class cls, NSString *key, NSString *dependentKey)
{
	NSMutableSet *dependents;

	pthread_mutex_lock(&fn_dependent_keys_lock);
	/* The helper above takes the lock itself, so this one inlines the same three steps rather than nesting a
	 * non-recursive mutex. */
	if (fn_dependent_keys == nil) {
		fn_dependent_keys = [[NSMutableDictionary alloc] init];
	}
	{
		NSString *className = NSStringFromClass(cls);
		NSMutableDictionary *byKey = [fn_dependent_keys objectForKey:className];

		if (byKey == nil) {
			byKey = [NSMutableDictionary dictionary];
			[fn_dependent_keys setObject:byKey forKey:className];
		}
		dependents = [byKey objectForKey:key];
		if (dependents == nil) {
			dependents = [NSMutableSet set];
			[byKey setObject:dependents forKey:key];
		}
	}
	[dependents addObject:dependentKey];
	pthread_mutex_unlock(&fn_dependent_keys_lock);
}

/* THE WHOLE CHAIN, because a subclass inherits its ancestors' registrations. */
static NSArray *fn_dependent_keys_for(Class cls, NSString *key)
{
	NSMutableArray *out = [NSMutableArray array];
	Class current;

	pthread_mutex_lock(&fn_dependent_keys_lock);
	for (current = cls; current != Nil; current = class_getSuperclass(current)) {
		NSMutableDictionary *byKey = [fn_dependent_keys objectForKey:NSStringFromClass(current)];
		NSMutableSet *dependents = [byKey objectForKey:key];

		if (dependents != nil) {
			[out addObjectsFromArray:[dependents allObjects]];
		}
	}
	pthread_mutex_unlock(&fn_dependent_keys_lock);
	return out;
}

NSString *const NSKeyValueChangeKindKey = @"NSKeyValueChangeKindKey";
NSString *const NSKeyValueChangeNewKey = @"NSKeyValueChangeNewKey";
NSString *const NSKeyValueChangeOldKey = @"NSKeyValueChangeOldKey";
NSString *const NSKeyValueChangeIndexesKey = @"NSKeyValueChangeIndexesKey";
NSString *const NSKeyValueChangeNotificationIsPriorKey = @"NSKeyValueChangeNotificationIsPriorKey";

/* ONE REGISTRATION: who is watching what, with which options and which context. */
@interface FNKVORegistration : NSObject
{
@public
	__unsafe_unretained NSObject *_observed;	/* NOT retained */
	__unsafe_unretained NSObject *_observer;	/* NOT retained */
	NSString *_keyPath;
	NSKeyValueObservingOptions _options;
	void *_context;
}
@end

@implementation FNKVORegistration
@end

/* ONE CHANGE between will and did, WHETHER IT IS A SETTING OR A TO-MANY MUTATION. The fields the to-many half
 * adds are nil/0 for a setting change, which is what keeps the two paths in one record and one registry. */
@interface FNKVOPending : NSObject
{
@public
	__unsafe_unretained NSObject *_observed;
	NSString *_key;
	/* ⚠ RETAINED. `-willChangeValueForKey:` captures the OLD value before the write, when the property is
	 * still its only owner, and `-didChangeValueForKey:` reads it back AFTER the setter has released it — so
	 * an old value nothing else held is deallocated in between and the change dictionary retains a stale
	 * pointer. The to-many arm's `_oldObjects` is retained for the same stated reason. */
	id _oldValue;			/* RETAINED, setting changes */
	BOOL _hasOld;
	/* THE TO-MANY HALF. `_changeKind` is 0 for a setting change and Insertion/Removal/Replacement otherwise;
	 * `_indexes` is the array form's affected indexes; `_oldObjects` is RETAINED because the mutation may free the
	 * objects before the `did` half reads them (a removal releases what it took out). */
	NSKeyValueChange _changeKind;
	NSIndexSet *_indexes;		/* RETAINED, array forms */
	id _oldObjects;			/* RETAINED, NSArray or NSSet */
	BOOL _setMutation;
	NSKeyValueSetMutationKind _mutationKind;
}
@end

@implementation FNKVOPending
- (void)dealloc
{
	[_key release];
	[_oldValue release];
	[_indexes release];
	[_oldObjects release];
	[super dealloc];
}
@end

/* ONE `-observationInfo`. */
@interface FNKVOInfo : NSObject
{
@public
	__unsafe_unretained NSObject *_object;		/* NOT retained */
	void *_info;
}
@end

@implementation FNKVOInfo
@end

static NSMutableArray *fn_registrations = nil;
static NSMutableArray *fn_pendings = nil;
static NSMutableArray *fn_infos = nil;

/* §63.21: AN OBJECT'S DEATH TAKES ITS ROWS WITH IT — what this file could NOT do before the death seam
 * existed. THE PROBLEM IS STRUCTURAL, NOT AN OVERSIGHT: Apple's registry is per-object, so it dies with the
 * object for free; OURS IS A PROCESS-GLOBAL TABLE KEYED BY POINTER IDENTITY, so an entry whose object has
 * died is not merely a leak — a NEW object allocated at the recycled address INHERITS the dead object's
 * registrations, and `-removeObserver:forKeyPath:` then SUCCEEDS for an observer it never had. Measured
 * before this hook existed: the fresh object matched the stale entry and the removal did not raise.
 *
 * ALL THREE TABLES ARE KEYED THE SAME WAY, so all three are swept here: registrations (`_observed`), pending
 * records (`_observed` — a `-willChangeValueForKey:` whose object died before the matching `-did` would
 * otherwise sit in the table forever), and `-observationInfo` entries (`_object`).
 *
 * THE CONTRACT, from FNObjectDeath.h: this runs for EVERY dying object, mid-death, and uses only the
 * ADDRESS. It is bounded by the tables' own size, which is why the seam is installed LAZILY (below) and why
 * a program that never registers an observer never reaches this function at all. */
static void fn_object_died(NSObject *object)
{
	NSUInteger i;

	if (fn_registrations == nil) {
		return;
	}
	/* BACKWARDS, because a removal shifts the tail; these tables are small by nature. */
	for (i = [fn_registrations count]; i > 0; i--) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i - 1];

		if (held->_observed == object) {
			[fn_registrations removeObjectAtIndex:i - 1];
		}
	}
	for (i = [fn_pendings count]; i > 0; i--) {
		FNKVOPending *held = [fn_pendings objectAtIndex:i - 1];

		if (held->_observed == object) {
			[fn_pendings removeObjectAtIndex:i - 1];
		}
	}
	for (i = [fn_infos count]; i > 0; i--) {
		FNKVOInfo *held = [fn_infos objectAtIndex:i - 1];

		if (held->_object == object) {
			[fn_infos removeObjectAtIndex:i - 1];
		}
	}
}

static void fn_kvo_init(void)
{
	if (fn_registrations == nil) {
		fn_registrations = [[NSMutableArray alloc] init];
		fn_pendings = [[NSMutableArray alloc] init];
		fn_infos = [[NSMutableArray alloc] init];
		fn_autos = [[NSMutableArray alloc] init];
		fn_notify_pairs = [[NSMutableArray alloc] init];
		/* INSTALLED HERE, NOT AT `+load` TIME: the tables exist from this moment, so the hook is needed
		 * from this moment — and a program that never calls KVO never installs one. */
		fn_object_death_hook = fn_object_died;
	}
}

/* ============================================================================================
 * THE AUTOMATIC HALF, IN THE ORDER IT IS USED: a key's setter name, the notifying class, the
 * wrapper, and the registry of wrappers.
 * ============================================================================================ */

/* "foo" -> "setFoo:". The empty key has no setter, and "URL" stays "URL" because only the FIRST character is
 * raised — the same rule KVC's capitalisation uses, read backwards. */
static SEL fn_setter_selector(NSString *key)
{
	NSString *name;
	NSString *first;
	NSString *rest;

	if (key == nil || [key length] == 0) {
		return NULL;
	}
	first = [[key substringToIndex:1] uppercaseString];
	rest = [key substringFromIndex:1];
	name = [NSString stringWithFormat:@"set%@%@:", first, rest];
	return NSSelectorFromString(name);
}

static Class fn_original_of_notifying(Class cls)
{
	NSUInteger i;

	if (cls == Nil || fn_notify_pairs == nil) {
		return Nil;
	}
	for (i = 0; i < [fn_notify_pairs count]; i++) {
		FNKVONotifyingPair *pair = [fn_notify_pairs objectAtIndex:i];

		if (pair->_notifying == cls) {
			return pair->_original;
		}
	}
	return Nil;
}

/* THE `-class` LIE COCOA DOCUMENTS: the object is a member of a dynamic subclass, and it answers the class the caller
 * declared. `-isKindOfClass:` needs no override — the dynamic class IS a subclass, so the chain answers truly. */
static Class fn_notifying_class_imp(id self, SEL _cmd)
{
	(void)_cmd;
	return class_getSuperclass(object_getClass(self));
}

/* THE SUBCLASS IS CREATED ONCE PER ORIGINAL CLASS AND REUSED.** A second observation of a different key on the same
 * object adds another setter override to it; a second object of the same class is moved to the same subclass. */
static Class fn_notifying_class_for(Class original)
{
	NSUInteger i;
	char name[512];
	Class existing;
	Class notifying;
	FNKVONotifyingPair *pair;

	if (original == Nil) {
		return Nil;
	}
	for (i = 0; i < [fn_notify_pairs count]; i++) {
		FNKVONotifyingPair *held = [fn_notify_pairs objectAtIndex:i];

		if (held->_original == original) {
			return held->_notifying;
		}
	}
	snprintf(name, sizeof name, "NSKVONotifying_%s", class_getName(original));
	existing = objc_getClass(name);
	if (existing != Nil) {
		/* ALREADY ALLOCATED BY AN EARLIER OBSERVATION whose pair was lost is not a state this file can be in;
		 * a class of that name from somewhere else is not ours to subclass. Either way the honest answer is to use
		 * it only if it is a subclass of the original. */
		if (class_getSuperclass(existing) == original) {
			notifying = existing;
		} else {
			return Nil;
		}
	} else {
		notifying = objc_allocateClassPair(original, name, 0);
		if (notifying == Nil) {
			return Nil;
		}
		class_addMethod(notifying, @selector(class), (IMP)fn_notifying_class_imp, "#@:");
		objc_registerClassPair(notifying);
	}
	pair = [[FNKVONotifyingPair alloc] init];
	pair->_original = original;
	pair->_notifying = notifying;
	[fn_notify_pairs addObject:pair];
	[pair release];
	return notifying;
}

static FNAutoSetter *fn_auto_record_for(Class notifying, SEL setter)
{
	NSUInteger i;

	if (fn_autos == nil) {
		return nil;
	}
	for (i = 0; i < [fn_autos count]; i++) {
		FNAutoSetter *held = [fn_autos objectAtIndex:i];

		if (held->_notifying == notifying && sel_isEqual(held->_setter, setter)) {
			return held;
		}
	}
	return nil;
}

/* ---- THE WRAPPERS: ONE PER ARGUMENT TYPE THIS TIER CAN INTERCEPT -------------------------------------------------
 *
 * EACH IS THE SAME THREE STEPS — announce, call the original IMP with the argument unchanged, announce the end — and
 * they are separate FUNCTIONS rather than one variadic trampoline because the call has to carry the argument in its
 * own C type. The original IMP is looked up in the wrapper registry by (the object's dynamic class, the selector), not
 * by parsing the encoding again. */
static FNAutoSetter *fn_auto_will(id self, SEL _cmd)
{
	FNAutoSetter *record = fn_auto_record_for(object_getClass(self), _cmd);

	if (record != nil) {
		[self willChangeValueForKey:record->_key];
	}
	return record;
}

static void fn_auto_did(id self, FNAutoSetter *record)
{
	if (record != nil) {
		[self didChangeValueForKey:record->_key];
	}
}

static void fn_set_id(id self, SEL _cmd, id value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, id))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_char(id self, SEL _cmd, char value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, char))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_short(id self, SEL _cmd, short value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, short))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_int(id self, SEL _cmd, int value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, int))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_long(id self, SEL _cmd, long value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, long))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_longlong(id self, SEL _cmd, long long value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, long long))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_float(id self, SEL _cmd, float value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, float))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

static void fn_set_double(id self, SEL _cmd, double value)
{
	FNAutoSetter *record = fn_auto_will(self, _cmd);

	((void (*)(id, SEL, double))record->_original)(self, _cmd, value);
	fn_auto_did(self, record);
}

/* THE CHOICE OF WRAPPER IS THE ARGUMENT'S ENCODING.** `@`/`#` are pointers; `c`/`C`/`B` one byte; and the integer
 * widths are kept apart rather than collapsed, because the wrapper's function type is the ABI. Anything else — a
 * struct, a pointer, a C string, a selector — is left UNWRAPPED on purpose and the header names the fallback. */
static IMP fn_wrapper_for_argument(const char *type)
{
	if (type == NULL) {
		return NULL;
	}
	switch (type[0]) {
	case '@':
	case '#':
		return (IMP)fn_set_id;
	case 'c':
	case 'C':
	case 'B':
		return (IMP)fn_set_char;
	case 's':
	case 'S':
		return (IMP)fn_set_short;
	case 'i':
	case 'I':
		return (IMP)fn_set_int;
	case 'l':
	case 'L':
		return (IMP)fn_set_long;
	case 'q':
	case 'Q':
		return (IMP)fn_set_longlong;
	case 'f':
		return (IMP)fn_set_float;
	case 'd':
		return (IMP)fn_set_double;
	default:
		return NULL;
	}
}

/* INSTALL, ONCE PER (CLASS, KEY).** A dotted key path is not decomposed here — that is a separate row — and a key with
 * no setter has nothing to wrap, so both leave the object's class alone and let KVC's own wrapper do the announcing. */
static void fn_install_auto_kvo(id object, NSString *keyPath)
{
	Class current;
	Class original;
	Class notifying;
	SEL setter;
	Method method;
	NSMethodSignature *signature;
	IMP wrapper;
	FNAutoSetter *record;

	if (object == nil || keyPath == nil || [keyPath length] == 0) {
		return;
	}
	if ([keyPath rangeOfString:@"."].location != NSNotFound) {
		return;
	}
	fn_kvo_init();
	current = object_getClass(object);
	original = fn_original_of_notifying(current);
	if (original == Nil) {
		original = current;
	}
	notifying = fn_notifying_class_for(original);
	if (notifying == Nil) {
		return;
	}
	setter = fn_setter_selector(keyPath);
	if (setter == NULL) {
		return;
	}
	if (fn_auto_record_for(notifying, setter) != nil) {
		if (current != notifying) {
			object_setClass(object, notifying);
		}
		return;
	}
	method = class_getInstanceMethod(original, setter);
	if (method == NULL) {
		return;		/* no setter: KVC's ivar path and the manual pair are the only writers */
	}
	signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
	if (signature == nil || [signature numberOfArguments] < 3) {
		return;
	}
	wrapper = fn_wrapper_for_argument([signature getArgumentTypeAtIndex:2]);
	if (wrapper == NULL) {
		return;		/* a struct, pointer, C string or selector: named as unwrapped */
	}
	class_addMethod(notifying, setter, wrapper, method_getTypeEncoding(method));
	record = [[FNAutoSetter alloc] init];
	record->_notifying = notifying;
	record->_setter = setter;
	record->_key = [keyPath copy];
	record->_original = method_getImplementation(method);
	[fn_autos addObject:record];
	[record release];
	if (current != notifying) {
		object_setClass(object, notifying);
	}
}

/* THE INTERNAL DOOR KVC ASKS: does this object's class already announce this key's setter? */
BOOL fn_kvo_auto_notifies(id object, NSString *key)
{
	Class current;
	Class original;
	SEL setter;
	Method wrapper;
	Method base;

	if (object == nil || key == nil || [key length] == 0) {
		return NO;
	}
	if ([key rangeOfString:@"."].location != NSNotFound) {
		return NO;
	}
	fn_kvo_init();
	current = object_getClass(object);
	original = fn_original_of_notifying(current);
	if (original == Nil) {
		return NO;
	}
	setter = fn_setter_selector(key);
	if (setter == NULL) {
		return NO;
	}
	wrapper = class_getInstanceMethod(current, setter);
	base = class_getInstanceMethod(original, setter);
	return (wrapper != NULL && base != NULL
		&& method_getImplementation(wrapper) != method_getImplementation(base));
}

/* IDENTITY, NOT EQUALITY: two distinct but equal objects are two different things to observe. */
static FNKVORegistration *fn_registration_for(NSObject *observed, NSString *key)
{
	NSUInteger i;

	fn_kvo_init();
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed == observed && [held->_keyPath isEqualToString:key]) {
			return held;
		}
	}
	return nil;
}

static NSUInteger fn_registration_count(NSObject *observed, NSString *key)
{
	NSUInteger i, count = 0;

	fn_kvo_init();
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed == observed && [held->_keyPath isEqualToString:key]) {
			count++;
		}
	}
	return count;
}

static FNKVOPending *fn_pending_for(NSObject *observed, NSString *key)
{
	NSUInteger i;

	fn_kvo_init();
	for (i = 0; i < [fn_pendings count]; i++) {
		FNKVOPending *held = [fn_pendings objectAtIndex:i];

		if (held->_observed == observed && [held->_key isEqualToString:key]) {
			return held;
		}
	}
	return nil;
}

/* THE TO-MANY PENDING IS A DIFFERENT RECORD FROM THE SETTING ONE, and the two lookups say so: an array proxy's
 * mutation must not be consumed by a plain setter's `did`, and a setting change must not be consumed by a proxy's. */
static FNKVOPending *fn_tomany_pending_for(NSObject *observed, NSString *key)
{
	NSUInteger i;

	fn_kvo_init();
	for (i = 0; i < [fn_pendings count]; i++) {
		FNKVOPending *held = [fn_pendings objectAtIndex:i];

		if (held->_observed == observed && held->_changeKind != 0 && [held->_key isEqualToString:key]) {
			return held;
		}
	}
	return nil;
}

static NSArray *fn_objects_at_indexes(NSArray *collection, NSIndexSet *indexes)
{
	NSMutableArray *objects = [NSMutableArray array];
	NSUInteger index;

	if (collection == nil || indexes == nil) {
		return objects;
	}
	for (index = [indexes firstIndex]; index != NSNotFound; index = [indexes indexGreaterThanIndex:index]) {
		if (index < [collection count]) {
			[objects addObject:[collection objectAtIndex:index]];
		}
	}
	return objects;
}

@implementation NSObject (NSKeyValueObserving)

- (void)addObserver:(NSObject *)observer
	 forKeyPath:(NSString *)keyPath
	    options:(NSKeyValueObservingOptions)options
	    context:(nullable void *)context
{
	FNKVORegistration *registration;

	if (observer == nil || keyPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"KVO: -addObserver:forKeyPath:options:context: needs both an observer "
				   "and a key path"];
	}
	fn_kvo_init();
	registration = [[FNKVORegistration alloc] init];
	registration->_observed = self;
	registration->_observer = observer;
	registration->_keyPath = [keyPath copy];
	registration->_options = options;
	registration->_context = context;
	[fn_registrations addObject:registration];
	/* **THE DEPENDENCY TABLE IS BUILT FROM THE DECLARATIVE FORM AT REGISTRATION TIME, AND IT IS THE INVERSE.**
	 * `+keyPathsForValuesAffectingValueForKey:@"fullName"` answers {firstName, lastName} — the keys that affect
	 * fullName — while the notification path needs "which keys DOES firstName affect". Registering the reverse at
	 * the moment somebody observes the dependent key is what makes the declarative method drive direct setters
	 * without scanning every method on every change. */
	if ([keyPath rangeOfString:@"."].location == NSNotFound) {
		NSSet *dependencies = [[self class] keyPathsForValuesAffectingValueForKey:keyPath];
		NSEnumerator *enumerator = [dependencies objectEnumerator];
		NSString *dependency;

		while ((dependency = [enumerator nextObject]) != nil) {
			fn_register_dependent(object_getClass(self), dependency, keyPath);
			/* THE DEPENDENCY'S OWN SETTER MUST ANNOUNCE TOO. Observing `fullName` is what makes KVO watch
			 * `firstName`; without this the direct setter has no wrapper and the dependent key never hears. */
			fn_install_auto_kvo(self, dependency);
		}
	}
	/* **THE OBJECT IS MOVED TO ITS NOTIFYING CLASS BEFORE THE INITIAL NOTIFICATION**, so the first observation and every
	 * later direct setter see the same world. The move is a no-op when the key has no wrappable setter. */
	fn_install_auto_kvo(self, keyPath);

	if ((options & NSKeyValueObservingOptionInitial) != 0) {
		/* THE INITIAL NOTIFICATION carries the value as it stands, and arrives BEFORE this call
		 * returns — that is what makes it useful for a first paint. */
		NSMutableDictionary *change = [NSMutableDictionary dictionaryWithCapacity:2];

		[change setObject:[NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting]
			   forKey:NSKeyValueChangeKindKey];
		if ((options & NSKeyValueObservingOptionNew) != 0) {
			id now = [self valueForKey:keyPath];

			[change setObject:(now != nil ? now : (id)[NSNull null])
				   forKey:NSKeyValueChangeNewKey];
		}
		[observer observeValueForKeyPath:keyPath ofObject:self change:change context:context];
	}
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
	NSUInteger i;

	/* THE TWO-ARGUMENT FORM IGNORES THE CONTEXT, which is the entire difference between it and the
	 * three-argument one: it removes whatever was registered for this observer and key path, however
	 * it was registered. Getting that wrong is how this file's first version RAISED on a removal
	 * Cocoa accepts — measured, after a marker showed the abort was one block earlier than the
	 * check that appeared to fail. */
	fn_kvo_init();
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed == self && held->_observer == observer &&
		    [held->_keyPath isEqualToString:keyPath]) {
			[fn_registrations removeObjectAtIndex:i];
			return;
		}
	}
	/* COCOA'S RULE: removing something that was never registered is a programming error, not a
	 * silent success — and it is the failure mode that leaves a dangling observer behind. */
	[NSException raise:NSInvalidArgumentException
		    format:@"KVO: %@ is not registered as an observer of \"%@\"",
			   [observer class], keyPath];
}

- (void)removeObserver:(NSObject *)observer
	    forKeyPath:(NSString *)keyPath
	       context:(nullable void *)context
{
	NSUInteger i;

	fn_kvo_init();
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed == self && held->_observer == observer &&
		    [held->_keyPath isEqualToString:keyPath] && held->_context == context) {
			[fn_registrations removeObjectAtIndex:i];
			return;
		}
	}
	/* COCOA'S RULE: removing something that was never registered is a programming error, not a
	 * silent success — and it is the failure mode that leaves a dangling observer behind. */
	[NSException raise:NSInvalidArgumentException
		    format:@"KVO: %@ is not registered as an observer of \"%@\"",
			   [observer class], keyPath];
}

- (void)fnWillChangeValueForKeyBody:(NSString *)key
{
	FNKVOPending *pending;
	BOOL wantsOld = NO;
	BOOL wantsPrior = NO;
	NSUInteger i;
	id current = nil;

	if (key == nil) {
		return;
	}
	fn_kvo_init();
	if (fn_registration_count(self, key) == 0) {
		/* NOBODY IS WATCHING: no pending record, no reads, nothing to undo in -didChange. */
		return;
	}
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed != self || ![held->_keyPath isEqualToString:key]) {
			continue;
		}
		if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
			wantsOld = YES;
		}
		if ((held->_options & NSKeyValueObservingOptionPrior) != 0) {
			wantsPrior = YES;
		}
	}
	if (wantsOld || wantsPrior) {
		current = [self valueForKey:key];
	}
	pending = [[FNKVOPending alloc] init];
	pending->_observed = self;
	pending->_key = [key copy];
	pending->_oldValue = [current retain];
	pending->_hasOld = (wantsOld || wantsPrior);
	[fn_pendings addObject:pending];
	[pending release];

	if (wantsPrior) {
		for (i = 0; i < [fn_registrations count]; i++) {
			FNKVORegistration *held = [fn_registrations objectAtIndex:i];
			NSMutableDictionary *change;

			if (held->_observed != self || ![held->_keyPath isEqualToString:key] ||
			    (held->_options & NSKeyValueObservingOptionPrior) == 0) {
				continue;
			}
			change = [NSMutableDictionary dictionaryWithCapacity:3];
			[change setObject:[NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting]
				   forKey:NSKeyValueChangeKindKey];
			[change setObject:[NSNumber numberWithBool:YES]
				   forKey:NSKeyValueChangeNotificationIsPriorKey];
			if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
				[change setObject:(current != nil ? current : (id)[NSNull null])
					   forKey:NSKeyValueChangeOldKey];
			}
			[held->_observer observeValueForKeyPath:key
						       ofObject:self
							 change:change
							context:held->_context];
		}
	}
}

- (void)fnDidChangeValueForKeyBody:(NSString *)key
{
	FNKVOPending *pending;
	NSUInteger i;

	if (key == nil) {
		return;
	}
	fn_kvo_init();
	pending = fn_pending_for(self, key);
	if (pending == nil) {
		return;			/* nothing was in flight (or nobody is watching) */
	}
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];
		NSMutableDictionary *change;

		if (held->_observed != self || ![held->_keyPath isEqualToString:key]) {
			continue;
		}
		change = [NSMutableDictionary dictionaryWithCapacity:3];
		[change setObject:[NSNumber numberWithUnsignedInteger:NSKeyValueChangeSetting]
			   forKey:NSKeyValueChangeKindKey];
		if ((held->_options & NSKeyValueObservingOptionNew) != 0) {
			/* THE NEW VALUE IS READ HERE, after the write — which is why this half exists. */
			id now = [self valueForKey:key];

			[change setObject:(now != nil ? now : (id)[NSNull null])
				   forKey:NSKeyValueChangeNewKey];
		}
		if ((held->_options & NSKeyValueObservingOptionOld) != 0 && pending->_hasOld) {
			[change setObject:(pending->_oldValue != nil ? pending->_oldValue
								     : (id)[NSNull null])
				   forKey:NSKeyValueChangeOldKey];
		}
		[held->_observer observeValueForKeyPath:key
					       ofObject:self
						 change:change
						context:held->_context];
	}
	[fn_pendings removeObjectIdenticalTo:pending];
}

/* ============================================================================================
 * THE PUBLIC PAIR, THE DEPENDENCY RULE, AND THE TWO CLASS-SIDE SWITCHES.
 *
 * THE PUBLIC PAIR IS A WRAPPER RATHER THAN THE BODY, because a dependent key has to be announced in the same
 * bracket as the key that changed: `will` for every dependent BEFORE the primary `will`, `did` for the primary
 * BEFORE the dependents. The bodies below are the original methods renamed, so the change is visible as the two
 * lines of ordering it actually is.
 *
 * THE IN-FLIGHT SET IS WHAT MAKES A CYCLE TERMINATE. `+keyPathsForValuesAffectingValueForKey:` is allowed to be
 * symmetric (two keys that affect each other), and a naive recursion would send `will` forever. A key already on
 * this thread's stack is not entered again, so each key is announced once per change.
 * ============================================================================================ */

static NSArray *fn_all_dependent_keys(id object, NSString *key)
{
	NSMutableSet *all = [NSMutableSet setWithArray:fn_dependent_keys_for(object_getClass(object), key)];
	NSSet *declared = [[object class] keyPathsForValuesAffectingValueForKey:key];

	if (declared != nil) {
		[all unionSet:declared];
	}
	return [all allObjects];
}

- (void)willChangeValueForKey:(NSString *)key
{
	BOOL entered = fn_enter_key(key);
	NSArray *dependents;
	NSUInteger i;

	if (entered) {
		dependents = fn_all_dependent_keys(self, key);
		for (i = 0; i < [dependents count]; i++) {
			[self willChangeValueForKey:[dependents objectAtIndex:i]];
		}
	}
	[self fnWillChangeValueForKeyBody:key];
	if (entered) {
		fn_leave_key(key);
	}
}

- (void)didChangeValueForKey:(NSString *)key
{
	BOOL entered = fn_enter_key(key);
	NSArray *dependents;
	NSUInteger i;

	[self fnDidChangeValueForKeyBody:key];
	if (entered) {
		dependents = fn_all_dependent_keys(self, key);
		for (i = 0; i < [dependents count]; i++) {
			[self didChangeValueForKey:[dependents objectAtIndex:i]];
		}
		fn_leave_key(key);
	}
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
	(void)key;
	return YES;
}

/* APPLE'S DECLARATIVE FORM: a class implements `+keyPathsForValuesAffecting<Key>` and this answers what it says.
 * `class_respondsToSelector` on the metaclass includes the inherited class methods, so a subclass inherits its
 * ancestors' declarations. The legacy registrations are added so both spellings drive the same notification path. */
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
	NSMutableSet *paths = [NSMutableSet set];
	NSString *name = [NSString stringWithFormat:@"keyPathsForValuesAffecting%@", fn_capitalised_key(key)];
	SEL sel = sel_registerName([name UTF8String]);

	if (class_respondsToSelector(object_getClass(self), sel)) {
		typedef NSSet *(*fn_paths_method)(id, SEL);
		fn_paths_method call = (fn_paths_method)[self methodForSelector:sel];
		NSSet *declared = call(self, sel);

		if (declared != nil) {
			[paths unionSet:declared];
		}
	}
	return paths;
}

- (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)dependentKey
{
	NSUInteger i;

	for (i = 0; i < [keys count]; i++) {
		fn_register_dependent(object_getClass(self), [keys objectAtIndex:i], dependentKey);
	}
}

/* ============================================================================================
 * THE TO-MANY PAIR: A COLLECTION MUTATION, ANNOUNCED WITH ITS INDEXES AND THE OBJECTS IT TOUCHED.
 * ============================================================================================ */
/* **THE OLD OBJECTS ARE CAPTURED BEFORE THE MUTATION AND RETAINED, BECAUSE THE MUTATION MAY FREE THEM.** A removal
 * takes the objects out of the collection and releases them; the `did` half and the prior notification still have to
 * name them, so the pending record owns an array of them rather than borrowing the collection's.
 *
 * **THE PRIOR PASS IS BUILT FROM THE SAME CAPTURE.** For an insertion the old value is NSNull (nothing was there);
 * for a removal or a replacement it is the affected objects. The ordinary pass adds the NEW side, which is read after
 * the mutation. */
- (void)willChange:(NSKeyValueChange)changeKind
   valuesAtIndexes:(NSIndexSet *)indexes
	    forKey:(NSString *)key
{
	FNKVOPending *pending;
	NSArray *current = nil;
	NSArray *oldObjects = nil;
	BOOL wantsOld = NO;
	BOOL wantsPrior = NO;
	NSUInteger i;

	if (key == nil || indexes == nil) {
		return;
	}
	fn_kvo_init();
	if (fn_registration_count(self, key) == 0) {
		return;
	}
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed != self || ![held->_keyPath isEqualToString:key]) {
			continue;
		}
		if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
			wantsOld = YES;
		}
		if ((held->_options & NSKeyValueObservingOptionPrior) != 0) {
			wantsPrior = YES;
		}
	}
	if (wantsOld || wantsPrior) {
		id collection = [self valueForKey:key];

		if ([collection isKindOfClass:[NSArray class]]) {
			current = (NSArray *)collection;
		}
	}
	if (changeKind == NSKeyValueChangeRemoval || changeKind == NSKeyValueChangeReplacement) {
		oldObjects = fn_objects_at_indexes(current, indexes);
	}
	pending = [[FNKVOPending alloc] init];
	pending->_observed = self;
	pending->_key = [key copy];
	pending->_changeKind = changeKind;
	pending->_indexes = [indexes copy];
	pending->_oldObjects = [oldObjects copy];
	pending->_hasOld = (oldObjects != nil);
	[fn_pendings addObject:pending];
	[pending release];

	if (wantsPrior) {
		for (i = 0; i < [fn_registrations count]; i++) {
			FNKVORegistration *held = [fn_registrations objectAtIndex:i];
			NSMutableDictionary *change;

			if (held->_observed != self || ![held->_keyPath isEqualToString:key] ||
			    (held->_options & NSKeyValueObservingOptionPrior) == 0) {
				continue;
			}
			change = [NSMutableDictionary dictionaryWithCapacity:4];
			[change setObject:[NSNumber numberWithUnsignedInteger:changeKind]
				   forKey:NSKeyValueChangeKindKey];
			[change setObject:indexes forKey:NSKeyValueChangeIndexesKey];
			[change setObject:[NSNumber numberWithBool:YES]
				   forKey:NSKeyValueChangeNotificationIsPriorKey];
			if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
				[change setObject:(oldObjects != nil ? (id)oldObjects : (id)[NSNull null])
					   forKey:NSKeyValueChangeOldKey];
			}
			[held->_observer observeValueForKeyPath:key
						       ofObject:self
							 change:change
							context:held->_context];
		}
	}
}

- (void)didChange:(NSKeyValueChange)changeKind
  valuesAtIndexes:(NSIndexSet *)indexes
	   forKey:(NSString *)key
{
	FNKVOPending *pending;
	NSArray *current = nil;
	NSArray *newObjects = nil;
	NSUInteger i;

	if (key == nil || indexes == nil) {
		return;
	}
	fn_kvo_init();
	pending = fn_tomany_pending_for(self, key);
	if (pending == nil || pending->_changeKind != changeKind || pending->_setMutation ||
	    ![pending->_indexes isEqual:indexes]) {
		return;
	}
	if (changeKind == NSKeyValueChangeInsertion || changeKind == NSKeyValueChangeReplacement) {
		id collection = [self valueForKey:key];

		if ([collection isKindOfClass:[NSArray class]]) {
			current = (NSArray *)collection;
		}
		newObjects = fn_objects_at_indexes(current, indexes);
	}
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];
		NSMutableDictionary *change;

		if (held->_observed != self || ![held->_keyPath isEqualToString:key]) {
			continue;
		}
		change = [NSMutableDictionary dictionaryWithCapacity:4];
		[change setObject:[NSNumber numberWithUnsignedInteger:changeKind]
			   forKey:NSKeyValueChangeKindKey];
		[change setObject:indexes forKey:NSKeyValueChangeIndexesKey];
		if ((held->_options & NSKeyValueObservingOptionNew) != 0) {
			[change setObject:(newObjects != nil ? (id)newObjects : (id)[NSNull null])
				   forKey:NSKeyValueChangeNewKey];
		}
		/* **AN OLD SIDE THAT DOES NOT EXIST IS STILL REPORTED, AS NSNull.** An insertion has no old objects; an
		 * observer that asked for Old gets NSNull rather than an absent key, which is Apple's contract and the
		 * difference between "nothing was there" and "nobody asked". */
		if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
			[change setObject:(pending->_oldObjects != nil ? pending->_oldObjects : (id)[NSNull null])
				   forKey:NSKeyValueChangeOldKey];
		}
		[held->_observer observeValueForKeyPath:key
					       ofObject:self
						 change:change
						context:held->_context];
	}
	[fn_pendings removeObjectIdenticalTo:pending];
}

/* **THE SET MUTATION IS THE SAME IDEA WITH SETS INSTEAD OF INDEXES.** The mutation kind names the operation; the
 * receiver turns it into the change kind a binding reads (union is an insertion, minus and intersect are removals,
 * set is a replacement), and the OLD and NEW objects are the members the operation touched. **THE VALUES ARE NSSets**,
 * which is the set form's contract and the reason a caller reads `NSKeyValueChangeNewKey` with `-member:`. */
- (void)willChangeValueForKey:(NSString *)key
	      withSetMutation:(NSKeyValueSetMutationKind)mutationKind
		 usingObjects:(NSSet *)objects
{
	FNKVOPending *pending;
	NSSet *current = nil;
	NSMutableSet *oldObjects = nil;
	NSKeyValueChange changeKind;
	BOOL wantsOld = NO;
	BOOL wantsPrior = NO;
	NSUInteger i;

	if (key == nil) {
		return;
	}
	fn_kvo_init();
	if (fn_registration_count(self, key) == 0) {
		return;
	}
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];

		if (held->_observed != self || ![held->_keyPath isEqualToString:key]) {
			continue;
		}
		if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
			wantsOld = YES;
		}
		if ((held->_options & NSKeyValueObservingOptionPrior) != 0) {
			wantsPrior = YES;
		}
	}
	if (wantsOld || wantsPrior) {
		id collection = [self valueForKey:key];

		if ([collection isKindOfClass:[NSSet class]]) {
			current = (NSSet *)collection;
		}
	}
	switch (mutationKind) {
	case NSKeyValueUnionSetMutation:
		changeKind = NSKeyValueChangeInsertion;
		oldObjects = nil;
		break;
	case NSKeyValueMinusSetMutation:
	case NSKeyValueIntersectSetMutation:
		changeKind = NSKeyValueChangeRemoval;
		oldObjects = [NSMutableSet setWithSet:(current != nil ? current : [NSSet set])];
		[oldObjects intersectSet:objects];
		break;
	case NSKeyValueSetSetMutation:
	default:
		changeKind = NSKeyValueChangeReplacement;
		oldObjects = [NSMutableSet setWithSet:(current != nil ? current : [NSSet set])];
		break;
	}
	pending = [[FNKVOPending alloc] init];
	pending->_observed = self;
	pending->_key = [key copy];
	pending->_changeKind = changeKind;
	pending->_oldObjects = [oldObjects copy];
	pending->_hasOld = (oldObjects != nil);
	pending->_setMutation = YES;
	pending->_mutationKind = mutationKind;
	[fn_pendings addObject:pending];
	[pending release];

	if (wantsPrior) {
		for (i = 0; i < [fn_registrations count]; i++) {
			FNKVORegistration *held = [fn_registrations objectAtIndex:i];
			NSMutableDictionary *change;

			if (held->_observed != self || ![held->_keyPath isEqualToString:key] ||
			    (held->_options & NSKeyValueObservingOptionPrior) == 0) {
				continue;
			}
			change = [NSMutableDictionary dictionaryWithCapacity:3];
			[change setObject:[NSNumber numberWithUnsignedInteger:changeKind]
				   forKey:NSKeyValueChangeKindKey];
			[change setObject:[NSNumber numberWithBool:YES]
				   forKey:NSKeyValueChangeNotificationIsPriorKey];
			if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
				[change setObject:(oldObjects != nil ? (id)oldObjects : (id)[NSNull null])
					   forKey:NSKeyValueChangeOldKey];
			}
			[held->_observer observeValueForKeyPath:key
						       ofObject:self
							 change:change
							context:held->_context];
		}
	}
}

- (void)didChangeValueForKey:(NSString *)key
	     withSetMutation:(NSKeyValueSetMutationKind)mutationKind
		usingObjects:(NSSet *)objects
{
	FNKVOPending *pending;
	NSSet *current = nil;
	NSMutableSet *newObjects = nil;
	NSKeyValueChange changeKind;
	NSUInteger i;

	if (key == nil) {
		return;
	}
	fn_kvo_init();
	pending = fn_tomany_pending_for(self, key);
	if (pending == nil || !pending->_setMutation || pending->_mutationKind != mutationKind) {
		return;
	}
	changeKind = pending->_changeKind;
	if (changeKind == NSKeyValueChangeInsertion || changeKind == NSKeyValueChangeReplacement) {
		id collection = [self valueForKey:key];

		if ([collection isKindOfClass:[NSSet class]]) {
			current = (NSSet *)collection;
		}
	}
	switch (mutationKind) {
	case NSKeyValueUnionSetMutation:
		newObjects = [NSMutableSet setWithSet:(current != nil ? current : [NSSet set])];
		[newObjects intersectSet:objects];
		break;
	case NSKeyValueSetSetMutation:
		newObjects = [NSMutableSet setWithSet:(current != nil ? current : [NSSet set])];
		break;
	case NSKeyValueMinusSetMutation:
	case NSKeyValueIntersectSetMutation:
	default:
		newObjects = nil;
		break;
	}
	for (i = 0; i < [fn_registrations count]; i++) {
		FNKVORegistration *held = [fn_registrations objectAtIndex:i];
		NSMutableDictionary *change;

		if (held->_observed != self || ![held->_keyPath isEqualToString:key]) {
			continue;
		}
		change = [NSMutableDictionary dictionaryWithCapacity:3];
		[change setObject:[NSNumber numberWithUnsignedInteger:changeKind]
			   forKey:NSKeyValueChangeKindKey];
		if ((held->_options & NSKeyValueObservingOptionNew) != 0) {
			[change setObject:(newObjects != nil ? (id)newObjects : (id)[NSNull null])
				   forKey:NSKeyValueChangeNewKey];
		}
		if ((held->_options & NSKeyValueObservingOptionOld) != 0) {
			[change setObject:(pending->_oldObjects != nil ? pending->_oldObjects : (id)[NSNull null])
				   forKey:NSKeyValueChangeOldKey];
		}
		[held->_observer observeValueForKeyPath:key
					       ofObject:self
						 change:change
						context:held->_context];
	}
	[fn_pendings removeObjectIdenticalTo:pending];
}

- (nullable void *)observationInfo
{
	NSUInteger i;

	fn_kvo_init();
	for (i = 0; i < [fn_infos count]; i++) {
		FNKVOInfo *held = [fn_infos objectAtIndex:i];

		if (held->_object == self) {
			return held->_info;
		}
	}
	return NULL;
}

- (void)setObservationInfo:(nullable void *)info
{
	NSUInteger i;

	fn_kvo_init();
	for (i = 0; i < [fn_infos count]; i++) {
		FNKVOInfo *held = [fn_infos objectAtIndex:i];

		if (held->_object == self) {
			held->_info = info;
			return;
		}
	}
	{
		FNKVOInfo *fresh = [[FNKVOInfo alloc] init];

		fresh->_object = self;
		fresh->_info = info;
		[fn_infos addObject:fresh];
	}
}


/* THE OBSERVER'S DEFAULT, WHICH IS A RAISE. Apple's contract: a class that registers itself as an observer and does
 * not override this is a programming error, and the failure must be loud rather than a silent no-op. */
@end

@implementation NSObject (NSKeyValueObservingObserver)

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	(void)object;
	(void)change;
	(void)context;
	[NSException raise:NSInternalInconsistencyException
		    format:@"%@ received -observeValueForKeyPath:%@ but does not implement it",
			   [self class], keyPath];
}

@end

