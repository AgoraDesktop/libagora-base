/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSet / NSMutableSet — an unordered collection with no duplicates. docs/design/foundation-plan.md
 * §10 (the un-refusal program), F13.8.
 *
 * THIS CLASS IS A GAP §10 COULD NOT EXPLAIN AWAY, and it is the first one that family adds. Every
 * other entry in the plan's refusal table was refused for a REASON — a table, a service, an
 * evaluator. A set was never refused: it was simply missing, and the plan's own KVC section says so
 * in passing ("the set-returning operators need an NSSet that does not exist here"). So this is what
 * the un-refusal program looks like when the boundary is not the point.
 *
 * THE RULE IS THE ONE EVERY COLLECTION HERE FOLLOWS: a member's place is decided by ITS OWN -hash
 * and -isEqual:, so a set of strings dedupes BY VALUE — two distinct NSString objects with the same
 * characters are ONE member — and -member: finds an object by value rather than by pointer. That is
 * Cocoa's contract, and it is what makes a set different from an array.
 *
 * TWO DESIGN FACTS WORTH STATING RATHER THAN DISCOVERING:
 *   * THE MEMBERS ARE RETAINED, NOT COPIED — Cocoa's rule. That is also why the storage is NOT a
 *     dictionary keyed by the members: NSDictionary COPIES its keys (F3's audited rule), so a set built
 *     on one would copy its members and would refuse a member that cannot be copied. **THE INDEX ADDED
 *     BELOW IS KEYED BY `-hash`, NOT BY THE MEMBER**, which is how a set keeps this rule and still stops
 *     being linear;
 *   * AN IMMUTABLE SET'S MUTATION REPLACES the member array rather than editing it, so a loop running
 *     over it cannot be handed storage a later mutation frees. A MUTABLE set owns its array and appends
 *     in place — the guarantee there is the mutation token, which `-countByEnumeratingWithState:objects:
 *     count:` checks, not the replacement.
 *
 * ⚠ **LOOKUP AND APPEND WERE LINEAR AND ARE NOT ANY MORE (2026-10-23).** This header used to say that
 * "lookup is LINEAR, which is honest at this scale and leaves a real hash table as a later optimisation".
 * The scale arrived: a 10^5-row Core Data workload is built out of sets, and `-addObject:` was O(n) per
 * member — copy the whole array, scan it for the duplicate — so adding n members was O(n^2). MEASURED:
 * 0.6 s for 2,000, 2.7 s for 4,000, **10.4 s for 8,000**, which made the 10^5 case a twenty-minute
 * timeout rather than a test. A mutable set now owns a mutable array and keeps `_index`: `-hash` bucket
 * → members with that hash, built on the first mutation and consulted by `-member:`. `-hash` and
 * `-isEqual:` still decide membership, so a member that changes its hash while in a set is still a
 * caller's error — the same rule Cocoa states.
 *
 * It also had NO `-dealloc`, so every set leaked its member array, and `-fnReplaceMembers:` leaked the
 * array it replaced. Both are fixed; neither was found by reading.
 *
 * WHAT IS NOT HERE, named: NSCountedSet (its counts are its own structure), and NSOrderedSet (a
 * different collection with its own ordering rules) — each its own step.
 */

#ifndef FOUNDATION_NSSET_H
#define FOUNDATION_NSSET_H

#import <Foundation/NSObject.h>
#import <Foundation/NSFastEnumeration.h>

@class NSMutableDictionary;
/* FOR `NSCoding` AND THE `NSCoder` ITS TWO DOORS TAKE (§63.11): these collections conform on Apple's platform,
 * so a class that declares the protocol here is one whose `-conformsToProtocol:` answers the same. */
#import <Foundation/NSCoding.h>
#import <Foundation/NSIndexSet.h>	/* NSEnumerationOptions, which is ITS to declare */

@class NSArray<ObjectType>, NSEnumerator<ObjectType>;

NS_ASSUME_NONNULL_BEGIN

/* SWIFT SPELLS THIS CLASS `Set<AnyHashable>` (`swift_bridge`; §2.19 of
 * SWIFT-PORT-HANDOFF.md). `NSSet *` in an imported signature becomes a Swift
 * `Set`, and the overlay's `Set: _ObjectiveCBridgeable` puts an `NSSet *` back
 * on the wire. The element is `AnyHashable` for the same reason a dictionary
 * key is (this class's type parameter is unconstrained); an explicit
 * `NSSet<NSString *> *` imports as `Set<String>`.
 *
 * The mutable class is NOT bridged - a `NSMutableSet *` stays the class. */
__attribute__((swift_bridge("Swift.Set")))
@interface NSSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration, NSCoding>
{
	NSArray *_members;		/* the members, once each; REPLACED by an immutable set's mutation, APPENDED IN
	                                 * PLACE by a mutable one's */
	unsigned long _mutations;	/* the for-in consistency token */
	NSMutableDictionary *_index;	/* MUTABLE SETS ONLY: -hash bucket -> members with that hash. nil on any set
	                                 * that has never been mutated, and rebuilt on the first mutation. */
}

/* THE NSCoding DOORS (§63.11), the same pair the ordered sets took in §63.10 and for the same reasons: the
 * members go under the SHARED key (FNKeyedWire.h) that the archive's own structural branch uses, the decoder
 * reads it back through `-initWithArray:` — so the dedup rule and the class-choosing rule stay the
 * INITIALIZER's — and the ARCHIVER never calls either, because its structural branch recognises a set by
 * KIND. They exist for a caller who names them, and for `-conformsToProtocol:`.
 *
 * AND NSCountedSet INHERITS THIS PAIR WITHOUT A SECOND IMPLEMENTATION, which is a BOUNDARY rather than a
 * convenience: its MULTIPLICITIES are not part of what `-allObjects` answers, so they are not part of what
 * these doors carry. They survive the ARCHIVE (the structural branch writes them under `NS.counts`, §63.5)
 * and they do not survive a direct `-initWithCoder:` — use `-countForObject:` after either to see the
 * difference. Stated so the gap is a known edge of the pair and not a later surprise. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (void)encodeWithCoder:(NSCoder *)coder;

+ (instancetype)set;
+ (instancetype)setWithObject:(ObjectType)object;
/* THE NIL-TERMINATED VARIADIC FORM. It is Apple's, and this tree did not declare it until 2026-09-30: the
 * selector ledger carried the row as `open`, which is how an absence that has a NAME stays visible rather
 * than becoming an assumption. `NSArray` has had its counterpart all along, so the two families' factories
 * now read the same way. */
+ (instancetype)setWithObjects:(ObjectType)firstObject, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)setWithObjects:(const ObjectType _Nonnull * _Nullable)objects count:(NSUInteger)count;
+ (instancetype)setWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)setWithSet:(NSSet<ObjectType> *)set;

- (instancetype)initWithObjects:(const ObjectType _Nonnull * _Nullable)objects count:(NSUInteger)count NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
/* THE VARIADIC INITIALIZER (Apple's, nil-terminated) and the COPYING one. The copying form sends -copy to
 * each member once, which for an immutable member answers itself and for a mutable one gives the set a
 * private snapshot — the difference is the caller's to ask for. */
/* THE FIRST PARAMETER IS EXPLICITLY NULLABLE because the implementation ACCEPTS nil - it answers the empty
 * set - which is what this library's annotations are supposed to say. */
- (instancetype)initWithObjects:(ObjectType _Nullable)firstObject, ... NS_REQUIRES_NIL_TERMINATION;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set copyItems:(BOOL)copyItems;

@property (readonly) NSUInteger count;
/* BY VALUE: the member that is -isEqual: to `object`, or nil. This is the door that separates a set
 * from an array, and the probe measures exactly that (a distinguished object finds its twin). */
- (nullable ObjectType)member:(ObjectType)object;
- (BOOL)containsObject:(ObjectType)object;
@property (nullable, readonly) ObjectType anyObject;
@property (readonly, copy) NSArray<ObjectType> *allObjects;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType object, BOOL *stop))block NS_AVAILABLE_MAC(10_6);

/* THE OPTIONS FORM (§63.178): NSEnumerationReverse is honoured, and NSEnumerationConcurrent is the hint
 * this library ignores everywhere (so a loop is always serial and synchronous) — the same reading the
 * array family and NSIndexSet's enumerators take. THE ORDER OF AN UNORDERED COLLECTION IS UNSPECIFIED,
 * which is why nothing here promises one: reverse means the reverse of whatever order -allObjects
 * happened to answer, and a caller who needs an order sorts first. */
- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)options
			 usingBlock:(void (^)(ObjectType object, BOOL *stop))block NS_AVAILABLE_MAC(10_6);

/* THE PER-OBJECT DOORS: every member gets the message, in no promised order, and the selector must take
 * no argument (or exactly one object, in the `withObject:` form). */
- (void)makeObjectsPerformSelector:(SEL)aSelector;
- (void)makeObjectsPerformSelector:(SEL)aSelector withObject:(nullable id)argument;

/* THE TEST DOORS: a NEW immutable set of the members the block accepted. `stop` ends the walk, and the
 * predicate's two arguments are both answers, as in NSIndexSet's scan. */
- (NSSet<ObjectType> *)objectsPassingTest:(BOOL (^)(ObjectType object, BOOL *stop))predicate NS_AVAILABLE_MAC(10_6);
- (NSSet<ObjectType> *)objectsWithOptions:(NSEnumerationOptions)options
			      passingTest:(BOOL (^)(ObjectType object, BOOL *stop))predicate NS_AVAILABLE_MAC(10_6);

- (BOOL)isEqualToSet:(NSSet<ObjectType> *)other;
- (BOOL)isSubsetOfSet:(NSSet<ObjectType> *)other;
- (BOOL)intersectsSet:(NSSet<ObjectType> *)other;

/* The three "adding" forms answer a NEW set (the receiver is immutable), which is why no addObject:
 * exists here at all. */
- (instancetype)setByAddingObject:(ObjectType)object NS_AVAILABLE_MAC(10_5);
- (instancetype)setByAddingObjectsFromSet:(NSSet<ObjectType> *)other NS_AVAILABLE_MAC(10_5);
- (instancetype)setByAddingObjectsFromArray:(NSArray<ObjectType> *)other NS_AVAILABLE_MAC(10_5);

- (NSArray *)sortedArrayUsingDescriptors:(NSArray *)descriptors NS_AVAILABLE_MAC(10_6);

- (BOOL)isEqual:(id)other;
- (NSUInteger)hash;
- (NSString *)description;

/* THE LOCALE FORM, in the SHAPE THE ARRAY FAMILY ALREADY USES (§63.178): members on their own lines,
 * indented four spaces per level, and each member asked its own locale-aware description when it has one
 * — so a nested collection prints as a collection. The single-line -description above is this library's
 * compact spelling and is left exactly as it was. */
- (NSString *)descriptionWithLocale:(nullable id)locale;

@end

@interface NSMutableSet<ObjectType> : NSSet<ObjectType>

+ (instancetype)setWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;
/* APPLE DECLARES THIS ON THE MUTABLE CLASS TOO (§63.11), so it is redeclared here rather than left to
 * inheritance: a source-compatible caller reading THIS header must find it, and the ledger's shipped test is
 * a declaration in the owner's own block. Its implementation lives in this class's own `@implementation`
 * for the same reason — `--unimplemented` counts an implementation in the class or a SUBCLASS, so the
 * front's body does not satisfy this declaration. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (void)addObject:(ObjectType)object;
- (void)removeObject:(ObjectType)object;
- (void)removeAllObjects;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)unionSet:(NSSet<ObjectType> *)other;
- (void)minusSet:(NSSet<ObjectType> *)other;
- (void)intersectSet:(NSSet<ObjectType> *)other;
- (void)setSet:(NSSet<ObjectType> *)other;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSET_H */
