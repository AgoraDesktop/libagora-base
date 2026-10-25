/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSKeyValueCoding — reaching a property by NAME. docs/design/foundation-plan.md, F9.
 *
 * KVC IS A SET OF NAMING RULES, and that is the whole of it: given the key
 * `@"title"`, look for `-getTitle`, `-title`, `-isTitle`, then the ivars `_title`,
 * `_isTitle`, `title`, `isTitle`, and for writing `-setTitle:` then `_title` and
 * `title`. Nothing here needs a database, a registry or a stack, which is why the
 * family ships whole — and why what is NOT here is refused by name rather than
 * half-built (the list at the foot of this comment).
 *
 * THE ONE THING TO KNOW ABOUT THE SHAPE: Cocoa declares NSKeyValueCoding as an
 * INFORMAL protocol — NSObject answers its methods through a category, and the
 * protocol exists for adopters. That is what this is: `conformsToProtocol:` is NOT
 * the test for "does this object do KVC"; `respondsToSelector:` is, which is what
 * the probe asserts.
 *
 * A KEY PATH is the same lookup one dot at a time, and an `@`-led segment is an
 * OPERATOR over the collection the path has reached: `@count`, `@sum`, `@avg`,
 * `@max`, `@min`, `@unionOfObjects`, `@distinctUnionOfObjects`. Those are FOLDS,
 * so they are rules; the ones that would return a SET are refused, because there
 * is no NSSet here.
 *
 * REFUSED BY NAME, each needing something this library does not ship:
 *   - KEY-VALUE OBSERVING (the NSKeyValueObserving family): -addObserver:...,
 *     -willChangeValueForKey:, -didChangeValueForKey:, -observeValueForKeyPath:... —
 *     KVO is a REGISTRY of observers with a dependency graph. It is a service, not
 *     a naming rule, and the two are different sizes of thing;
 *   - the ORDERED-SET PROXY: -mutableOrderedSetValueForKey: and its ...KeyPath: form
 *     return a live proxy over NSMutableOrderedSet, which is a later row. The ARRAY and
 *     SET proxies ARE implemented (see the protocol's note);
 *   - the SET-returning operators: @unionOfArrays, @unionOfSets,
 *     @distinctUnionOfArrays, @distinctUnionOfSets — no NSSet ships;
 *   - the legacy dictionary-era API -takeValue:forKey: / -takeValuesFromDictionary:,
 *     which Cocoa removed as well.
 *
 * THE FAILURE DEFAULTS ARE THE HONEST ONES: an undefined key RAISES rather than
 * answering nil, and setting nil through a SCALAR key raises too. Both are the
 * methods a subclass overrides, and both are asserted by the probe.
 */

#ifndef FOUNDATION_NSKEYVALUECODING_H
#define FOUNDATION_NSKEYVALUECODING_H

#import <Foundation/NSObject.h>
/* The three are IMPORTED, not forward-declared: a category cannot be declared on
 * an undefined class, and this header defines categories on all three.
 * NSError need only be named, so it stays a forward declaration. */
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>

@class NSError;

NS_ASSUME_NONNULL_BEGIN

/*
 * The protocol, declared for ADOPTERS (see the header note). Every method is
 * implemented for NSObject by the category below.
 */
@protocol NSKeyValueCoding

- (nullable id)valueForKey:(NSString *)key;
- (void)setValue:(nullable id)value forKey:(NSString *)key;
- (nullable id)valueForKeyPath:(NSString *)keyPath;
- (void)setValue:(nullable id)value forKeyPath:(NSString *)keyPath;

/* **THE LIVE COLLECTION PROXIES.** A mutation through one of these is a mutation of the receiver's property: the
 * proxy reads and writes through `-valueForKey:`/`-setValue:forKey:` and announces a to-many change (insertion,
 * removal or replacement with the affected indexes) when the property's collection is mutable, or a whole-value
 * change when it is not. The proxy is an `NSMutableArray`/`NSMutableSet`, so it can be held wherever one is
 * expected; its target is NOT retained, exactly as a KVO registration does not retain its observed object. */
- (NSMutableArray *)mutableArrayValueForKey:(NSString *)key;
- (NSMutableArray *)mutableArrayValueForKeyPath:(NSString *)keyPath;
- (NSMutableSet *)mutableSetValueForKey:(NSString *)key;
- (NSMutableSet *)mutableSetValueForKeyPath:(NSString *)keyPath;

/* The hooks. The -ForUndefinedKey: pair and -setNilValueForKey: RAISE as
 * implemented; -validateValue:forKey:error: answers YES unless the class has a
 * -validate<Key>:error: of its own. All four are overridable, and that is the
 * point of declaring them. */
- (nullable id)valueForUndefinedKey:(NSString *)key;
- (void)setValue:(nullable id)value forUndefinedKey:(NSString *)key;
- (void)setNilValueForKey:(NSString *)key;
- (BOOL)validateValue:(id _Nullable * _Nullable)ioValue
	       forKey:(NSString *)key
		error:(NSError * _Nullable * _Nullable)outError;

/*
 * THE OPENSTEP-ERA SPELLINGS AND THE STORED-ACCESSOR PAIR. `-takeValue:forKey:` is Apple's pre-10.3 name for
 * `-setValue:forKey:` and is still declared in NSKeyValueCoding.h; the stored pair is the one with different
 * SEMANTICS rather than a different word: it reads and writes the INSTANCE VARIABLE and never an accessor, which is
 * what a class needs when it wants to bypass its own validation while decoding.
 *
 * `+accessInstanceVariablesDirectly` is the switch that lets KVC touch ivars at all. This tree's KVC searches
 * `_key`, `_isKey`, `key` and `isKey` after the accessors, so the default is YES — Apple's default too — and a class
 * that wants to hide its ivars overrides it to answer NO (its KVC then ends in `-valueForUndefinedKey:`).
 *
 * THE TWO DICTIONARY DOORS ARE THE BATCH FORM of `-valueForKey:`/`-setValue:forKey:`, and they use NSNull for nil:
 * a dictionary cannot hold nil, so `-dictionaryWithValuesForKeys:` substitutes NSNull for a nil value and
 * `-setValuesForKeysWithDictionary:` turns NSNull back into nil. That round trip is the contract, and it is the one
 * that makes an archive of a properties dictionary possible.
 */
+ (BOOL)accessInstanceVariablesDirectly;
- (nullable id)storedValueForKey:(NSString *)key;
- (void)takeStoredValue:(nullable id)value forKey:(NSString *)key;
- (void)takeValue:(nullable id)value forKey:(NSString *)key;
- (void)takeValue:(nullable id)value forKeyPath:(NSString *)keyPath;
- (void)takeValuesFromDictionary:(NSDictionary *)properties;
- (NSArray *)valuesForKeys:(NSArray *)keys;
- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys;
- (void)setValuesForKeysWithDictionary:(NSDictionary *)keyedValues;
- (nullable id)handleQueryWithUnboundKey:(NSString *)key;
- (void)handleTakeValue:(nullable id)value forUnboundKey:(NSString *)key;
- (void)unableToSetNilForKey:(NSString *)key;
- (BOOL)useStoredAccessor;
- (BOOL)validateValue:(id _Nullable * _Nullable)ioValue
	    forKeyPath:(NSString *)keyPath
		 error:(NSError * _Nullable * _Nullable)outError;

@end

/*
 * The defaults, on NSObject — and this is the informal-protocol shape, not a
 * conformance: `@interface NSObject <NSKeyValueCoding>` would need the protocol's
 * definition here, and this header needs NSObject's, so a category is what both
 * Cocoa and this library use.
 */
@interface NSObject (NSKeyValueCoding)

- (nullable id)valueForKey:(NSString *)key;
- (void)setValue:(nullable id)value forKey:(NSString *)key;
- (nullable id)valueForKeyPath:(NSString *)keyPath;
- (void)setValue:(nullable id)value forKeyPath:(NSString *)keyPath;

/* THE LIVE COLLECTION PROXIES, on the same category Apple puts them on. See the protocol's note above. */
- (NSMutableArray *)mutableArrayValueForKey:(NSString *)key;
- (NSMutableArray *)mutableArrayValueForKeyPath:(NSString *)keyPath;
- (NSMutableSet *)mutableSetValueForKey:(NSString *)key;
- (NSMutableSet *)mutableSetValueForKeyPath:(NSString *)keyPath;

- (nullable id)valueForUndefinedKey:(NSString *)key;
- (void)setValue:(nullable id)value forUndefinedKey:(NSString *)key;
- (void)setNilValueForKey:(NSString *)key;
- (BOOL)validateValue:(id _Nullable * _Nullable)ioValue
	       forKey:(NSString *)key
		error:(NSError * _Nullable * _Nullable)outError;

/*
 * THE OPENSTEP-ERA SPELLINGS AND THE STORED-ACCESSOR PAIR. `-takeValue:forKey:` is Apple's pre-10.3 name for
 * `-setValue:forKey:` and is still declared in NSKeyValueCoding.h; the stored pair is the one with different
 * SEMANTICS rather than a different word: it reads and writes the INSTANCE VARIABLE and never an accessor, which is
 * what a class needs when it wants to bypass its own validation while decoding.
 *
 * `+accessInstanceVariablesDirectly` is the switch that lets KVC touch ivars at all. This tree's KVC searches
 * `_key`, `_isKey`, `key` and `isKey` after the accessors, so the default is YES — Apple's default too — and a class
 * that wants to hide its ivars overrides it to answer NO (its KVC then ends in `-valueForUndefinedKey:`).
 *
 * THE TWO DICTIONARY DOORS ARE THE BATCH FORM of `-valueForKey:`/`-setValue:forKey:`, and they use NSNull for nil:
 * a dictionary cannot hold nil, so `-dictionaryWithValuesForKeys:` substitutes NSNull for a nil value and
 * `-setValuesForKeysWithDictionary:` turns NSNull back into nil. That round trip is the contract, and it is the one
 * that makes an archive of a properties dictionary possible.
 */
+ (BOOL)accessInstanceVariablesDirectly;
- (nullable id)storedValueForKey:(NSString *)key NS_DEPRECATED_MAC(10_0, 10_4);
- (void)takeStoredValue:(nullable id)value forKey:(NSString *)key NS_DEPRECATED_MAC(10_0, 10_4);
- (void)takeValue:(nullable id)value forKey:(NSString *)key NS_DEPRECATED_MAC(10_0, 10_3);
- (void)takeValue:(nullable id)value forKeyPath:(NSString *)keyPath NS_DEPRECATED_MAC(10_0, 10_3);
- (void)takeValuesFromDictionary:(NSDictionary *)properties NS_DEPRECATED_MAC(10_0, 10_3);
- (NSArray *)valuesForKeys:(NSArray *)keys NS_DEPRECATED_MAC(10_0, 10_3);
- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys;
- (void)setValuesForKeysWithDictionary:(NSDictionary *)keyedValues;
- (nullable id)handleQueryWithUnboundKey:(NSString *)key NS_DEPRECATED_MAC(10_0, 10_3);
- (void)handleTakeValue:(nullable id)value forUnboundKey:(NSString *)key NS_DEPRECATED_MAC(10_0, 10_3);
- (void)unableToSetNilForKey:(NSString *)key NS_DEPRECATED_MAC(10_0, 10_3);
- (BOOL)useStoredAccessor NS_DEPRECATED_MAC(10_0, 10_4);
- (BOOL)validateValue:(id _Nullable * _Nullable)ioValue
	    forKeyPath:(NSString *)keyPath
		 error:(NSError * _Nullable * _Nullable)outError;

@end

/*
 * AN ARRAY MAPS. `[array valueForKey:@"title"]` answers an array of the elements'
 * `-valueForKey:@"title"`, which is what makes `valueForKeyPath:@"@sum.price"`
 * mean anything: the operator folds what the path produced.
 */
@interface NSArray (NSKeyValueCoding)
- (nullable id)valueForKey:(NSString *)key;
@end

/*
 * A DICTIONARY LOOKS UP — unless the key is `@`-led, in which case it FOLDS over
 * its VALUES, exactly as Cocoa does. So `[dict valueForKey:@"@count"]` is the
 * number of values, not a missing key. It is the FOLD (through -valueForKeyPath:)
 * rather than the array's map: mapping an operator means asking each value for the
 * operator, which is not a question about the dictionary at all.
 */
@interface NSDictionary (NSKeyValueCoding)
- (nullable id)valueForKey:(NSString *)key;
@end


/*
 * THE COLLECTION OPERATORS (W2f), and these are the one family in W2 whose VALUES ARE NOT OURS:
 * each constant is the OPERATOR STRING a program also types into `-valueForKeyPath:`
 * ("@avg", "@count", …), so Apple publishes them as SYNTAX, and a value that did not match
 * would break the documented usage rather than merely differ from an unpublished number.
 * `@count` is the one this library's KVC is measured to implement, and the probe exercises it
 * THROUGH the API as well as asserting the string.
 */
typedef NSString *NSKeyValueOperator;

extern NSString *const NSAverageKeyValueOperator;
extern NSString *const NSCountKeyValueOperator;
extern NSString *const NSDistinctUnionOfArraysKeyValueOperator;
extern NSString *const NSDistinctUnionOfObjectsKeyValueOperator;
extern NSString *const NSDistinctUnionOfSetsKeyValueOperator;
extern NSString *const NSMaximumKeyValueOperator;
extern NSString *const NSMinimumKeyValueOperator;
extern NSString *const NSSumKeyValueOperator;
extern NSString *const NSUnionOfArraysKeyValueOperator;
extern NSString *const NSUnionOfObjectsKeyValueOperator;
extern NSString *const NSUnionOfSetsKeyValueOperator;

/* THE KVC ERROR CODE (W2f). Apple's number names a KVC validation failure; this library's own
 * `-validateValue:forKey:error:` is where such an error would be built, and the number is stated
 * once, here, so the two cannot disagree. */
extern NSInteger NSKeyValueValidationError;
NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSKEYVALUECODING_H */
