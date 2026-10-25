/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSObject — the root class of the Foundation (docs/design/foundation-plan.md).
 *
 * WHY THE NAME HAS A PREFIX. The runtime we ship declares a class called
 * `Object` in <objc/Object.h> AND registers it at startup (builtin_classes.c);
 * both facts were measured, and each breaks a first-party root class: importing
 * that header here is `error: duplicate interface definition for class 'Object'`,
 * and a class *named* Object makes the loader print "Loading two versions of
 * Object. The class that will be used is undefined" and die. The runtime also
 * owns Protocol/ProtocolGCC/ProtocolGSv1/__IncompleteProtocol, and the blocks
 * runtime owns the _NSConcrete*Block names. The `NS` prefix (the user's
 * amendment, 2026-09-17) is what keeps the whole family out of the way; that
 * header stays off-limits, and tools/foundation-gate.py enforces it.
 */

#ifndef FOUNDATION_NSOBJECT_H
#define FOUNDATION_NSOBJECT_H

#include <objc/runtime.h>
#include <stdint.h>
#include <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>

@class NSString;
@class NSMethodSignature;
@class NSInvocation;
@class NSCoder;

/*
 * NULLABILITY (F6). The sweep's rules, in one place: everything below is NONNULL
 * by default, and the handful of declarations that can legitimately answer nil say
 * so — a class with no superclass, a selector the runtime cannot find, a
 * -performSelector: whose method answers nil, and a -forwardingTargetForSelector:
 * meaning "no fast forwarding". `-zone` is NONNULL: an object always belongs to a
 * zone, and the default zone is the answer for memory allocated outside a custom one.
 */
NS_ASSUME_NONNULL_BEGIN

/*
 * The copying protocols, in COCOA'S SHAPE. `-copyWithZone:` is the member and the
 * override point, exactly as it is on macOS; `-copy` on NSObject is the convenience
 * that calls it with a NULL zone. A class that implements `-copy` instead is still
 * callable through `-copy`, but it is not conforming: the protocol promises the zone
 * door, and duplicating the copy point is what made Core Foundation's
 * `copyWithZone:NULL` dispatch miss Foundation classes in the first place.
 */
@protocol NSCopying
- (id)copyWithZone:(nullable NSZone *)zone;
@end

@protocol NSMutableCopying
- (id)mutableCopyWithZone:(nullable NSZone *)zone;
@end

/*
 * THE ROOT-CLASS ATTRIBUTE, and it is LOAD-BEARING — not decoration to silence a
 * warning. Without it, clang does not treat this as a root class of the modern
 * ABI, and in a translation unit that includes this header a `@"..."` literal is
 * NOT emitted as an object: it is folded into a bogus immediate constant
 * (measured: `movabs $0xc790000000000014`, with no relocation and no
 * `__objc_constant_string` entry to fill it), so every constant string is
 * garbage and a message send to it faults inside the runtime.
 *
 * Our runtime's own tests mark their root class exactly this way (Test/Test.h),
 * which is how the difference was found.
 */
/*
 * THE NSObject PROTOCOL (W2h) - the group of methods that make an object a first-class object. It
 * is what makes `id<NSObject>` a usable type, and the reason it is here first (§12: a missing
 * dependency is ADDED, not refused).
 *
 * THE MEMBER LIST IS APPLE'S PUBLISHED ONE, checked against the documentation rather than recalled
 * (this library's ledger is symbol-level, so it could not supply it): isEqual:, hash, superclass,
 * class, self, isProxy, isKindOfClass:, isMemberOfClass:, conformsToProtocol:, respondsToSelector:,
 * description, debugDescription, retain, release, autorelease, retainCount, and the three
 * performSelector: forms. `-methodForSelector:` and `-doesNotRecognizeSelector:` are NOT in it -
 * they belong to the NSObject CLASS - which is a distinction the documentation settled.
 *
 * `-zone` IS PRESENT, as Apple's protocol has it. Zones are real again: the type is declared in
 * NSObjCRuntime.h and the allocator in NSZone.h, so a protocol that promises a zone can keep the
 * promise. The class below repeats the declaration because a protocol member is not an
 * implementation and a caller importing only the header must see the return type.
 */
@protocol NSObject

@property (readonly) NSUInteger hash;
@property (readonly, copy) NSString *description;
@property (readonly, copy) NSString *debugDescription;

- (BOOL)isEqual:(id)object;
- (nullable Class)superclass;	/* a ROOT class's superclass IS nil */
- (Class)class;
- (instancetype)self;
- (BOOL)isProxy;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isMemberOfClass:(Class)aClass;
- (BOOL)conformsToProtocol:(Protocol *)aProtocol;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (instancetype)retain;
- (oneway void)release;
- (instancetype)autorelease;
- (NSUInteger)retainCount;
- (NSZone *)zone;
- (nullable id)performSelector:(SEL)aSelector;
- (nullable id)performSelector:(SEL)aSelector withObject:(id)object;
- (nullable id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;

@end

#if __has_attribute(objc_root_class)
__attribute__((objc_root_class))
#endif

@interface NSObject <NSObject>
{
	/*
	 * THE STORAGE RULE. class_createInstance() returns nil when
	 * instance_size < sizeof(Class) (runtime.c:360), so a root class with no
	 * instance variables silently produces no instances at all. The isa is
	 * the runtime's to manage; this declaration is what makes it exist.
	 */
	Class isa;
}

/*
 * Creation. These names are Cocoa's ON PURPOSE: ARC decides ownership from the
 * METHOD NAME (+alloc/+new/-init/-copy/-mutableCopy return +1, everything else
 * +0), so they keep those names whatever the class is called.
 */
+ (id)alloc;
/* THE ALLOCATION DOOR COCOA USES. `+alloc` calls this with the default zone, and the
 * Objective-C allocator (`objc_allocWithZone`) reaches it directly, as Swift's
 * `__allocating_init` does for every `T()`. A class cluster or singleton overrides
 * THIS method to substitute a class or answer a shared instance. The zone is recorded
 * against the object; the runtime itself has one heap, so the memory is the runtime's
 * and the zone is the identity the object reports. */
+ (id)allocWithZone:(nullable NSZone *)zone;
+ (id)new;
- (id)init;

/*
 * The three lifetimes. They delegate to the runtime rather than keeping a count
 * of their own: the count lives in a word *before* the allocation
 * (gc_none.c:allocate_class), so an ARC caller (objc_retain/objc_release) and an
 * MRR caller ([obj retain]) share ONE count.
 *
 * This class is marked ARC-compatible to the runtime — see
 * -_ARCCompliantRetainRelease in NSObject.m, without which those delegations
 * recurse.
 */
- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (NSUInteger)retainCount;
- (void)dealloc;		/* the root class frees the allocation */

/* Identity, class membership and introspection. */
+ (Class)class;
+ (nullable Class)superclass;
+ (BOOL)isSubclassOfClass:(Class)aClass;
+ (BOOL)conformsToProtocol:(Protocol *)aProtocol;
- (Class)class;
- (nullable Class)superclass;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isMemberOfClass:(Class)aClass;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (BOOL)conformsToProtocol:(Protocol *)aProtocol;

/* ===================================================================================================
 * WHAT AN ARCHIVER RECORDS, WHICH IS NOT ALWAYS `-class` — and this is the door a CLASS CLUSTER exists
 * to answer (docs/design/foundation-clusters-plan.md §C.3, item 4).
 *
 * An instance of a cluster belongs to a PRIVATE CONCRETE class, so an archive that recorded `-class`
 * would carry a name no caller ever wrote and no reader could look up. These answer the class to record
 * instead, and THE DEFAULTS SUBSTITUTE NOTHING: `-classForCoder` answers `[self class]`, and
 * `-classForArchiver` answers `-classForCoder`. A cluster's public front overrides them to answer
 * ITSELF, and its concrete subclasses inherit that — which is what keeps an archive of a cluster
 * carrying the public name.
 *
 * THE CONTRACT IS GNUstep's published NSObject reference, which is this project's admissible secondary
 * spec for such things: "-classForCoder ... default implementation returns [self class] (no
 * substitution)"; "-classForArchiver ... default implementation returns -classForCoder". Apple's own
 * NSObject page did not resolve from the documentation endpoint when this was written (a 404 on that
 * id), and THAT is also why our derived selector surface carries no NSObject rows at all: the doors are
 * declared here from a citable source rather than from memory, and the sweep gap is recorded in the
 * plan's §C.5 M0 entry.
 * =================================================================================================== */
- (Class)classForCoder;
- (Class)classForArchiver;

/*
 * THE CODER-SIDE CLASS DOORS, in Apple's own category shape (`NSObject (NSCoderMethods)`, NSObject.h).
 * `+version`/`+setVersion:` are the class version an archiver may consult; the default is the runtime's
 * class version, which starts at 0 and is what an unversioned class answers.
 * `-replacementObjectForCoder:` is the OLD substitution seam that `-classForCoder` grew out of: an object
 * may answer a DIFFERENT object to be encoded in its place, and the default substitutes nothing.
 * `-awakeAfterUsingCoder:` is the decoder's post-decode hook, answered SELF by default.
 */
+ (NSInteger)version;
+ (void)setVersion:(NSInteger)aVersion;
- (nullable id)replacementObjectForCoder:(NSCoder *)aCoder;
- (nullable id)awakeAfterUsingCoder:(NSCoder *)aDecoder;

/*
 * `+poseAsClass:` IS DEPRECATED SINCE 10.5 AND REFUSED BY NAME HERE. It asked the runtime to swap the
 * receiver into the hierarchy in place of aClass for all future message sends. libobjc2 has no
 * `class_poseAs` — the runtime removed the mechanism, which is why Apple deprecated it — and emulating it by
 * rewriting every existing class reference is not something a library can do correctly. So the door exists,
 * compiles, and raises with the reason instead of doing half of it. (Apple's own header marks it unavailable
 * to 64-bit code, so a 64-bit caller cannot reach it there either.)
 */
+ (void)poseAsClass:(Class)aClass NS_DEPRECATED_MAC(10_0, 10_5);

/*
 * THE DISCARDABLE-CONTENT PROXY (10.6). For an object whose content can be purged, this answers a proxy that
 * brackets each use with `-beginContentAccess`/`-endContentAccess`. The root class's default is SELF, which is
 * Apple's answer for an object with no purgeable content; NSDiscardableContent is where a class declares that
 * it has some, and NSPurgeableData is the concrete one this tree ships.
 */
- (id)autoContentAccessingProxy NS_AVAILABLE_MAC(10_6);

/*
 * THE GARBAGE COLLECTOR'S HOOK, and a NO-OP BY DOCUMENTATION rather than by omission: `-finalize` was sent
 * once, by the collector, before an object was freed. This library has no collector (NSGarbageCollector is
 * declared and refuses), so there is nothing to send it; a class that overrides it still compiles.
 */
- (void)finalize;

- (id)self;

/*
 * THE COPYING FAMILY, in Cocoa's shape. `-copy` and `-mutableCopy` are the
 * conveniences; they call the zone doors with a NULL zone, and the zone doors are
 * where a class overrides. The root class's defaults are A LOUD FAILURE.
 *
 * The loudness is the whole point of the audit's fix A: before it existed, sending
 * `-copy` to a class that did not implement it did not raise, it returned NIL (the
 * runtime's forwarding path), so a dictionary handed an NSNumber key filed a phantom
 * entry under a nil key and the value became unreachable — silently, with a count
 * that said otherwise.
 */
- (id)copy;		/* calls -copyWithZone: with a NULL zone */
- (id)copyWithZone:(nullable NSZone *)zone;	/* default: doesNotRecognizeSelector: */
- (id)mutableCopy;	/* calls -mutableCopyWithZone: with a NULL zone */
- (id)mutableCopyWithZone:(nullable NSZone *)zone;	/* default: doesNotRecognizeSelector: */
- (void)doesNotRecognizeSelector:(SEL)aSelector;

/* WHICH ZONE THIS OBJECT BELONGS TO. The default zone is the answer for an object the
 * runtime allocated normally; NSAllocateObject records a custom zone against the object.
 * `-setZone:` is declared for OpenStep-era source; on this runtime it changes the
 * recorded identity, not the address, because the runtime owns one heap. */
- (NSZone *)zone;
- (void)setZone:(nullable NSZone *)zone;

/* Messaging, which is how Cocoa code calls a selector it only knows by name. */
- (nullable id)performSelector:(SEL)aSelector;
- (nullable id)performSelector:(SEL)aSelector withObject:(nullable id)object;
- (nullable id)performSelector:(SEL)aSelector withObject:(nullable id)object1 withObject:(nullable id)object2;

/* Messaging and introspection, the rest of Cocoa's root-class surface. */
/* THE SIGNATURE OF A SELECTOR, and the FORWARDING that uses it (stage F). The
 * lookup needs no invocation; -forwardInvocation: IS the invocation — built by the
 * runtime's __objc_msg_forward2 hook (NSInvocation.m) and delivered here. */
- (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
+ (nullable NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
- (nullable id)forwardingTargetForSelector:(SEL)aSelector;	/* default: nil */
- (void)forwardInvocation:(NSInvocation *)anInvocation;	/* default: doesNotRecognizeSelector: */

- (nullable IMP)methodForSelector:(SEL)aSelector;
+ (BOOL)respondsToSelector:(SEL)aSelector;
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;

/*
 * THE RUNTIME'S HOOKS AND THE CLASS-SIDE METHOD LOOKUPS. `+resolveInstanceMethod:`/`+resolveClassMethod:`
 * are what a runtime calls once before it gives up on a selector (GNUstep's runtime does, and Apple's does);
 * the root class answers NO, which is Apple's default and the only default that cannot change another
 * class's behaviour. A class that wants dynamic method generation overrides them, adds the method with
 * `class_addMethod`, and answers YES.
 *
 * `+instanceMethodForSelector:` and `+instanceMethodSignatureForSelector:` are the CLASS-side questions the
 * runtime's method list answers: the instance method's IMP and its types. They are not the same lookup as
 * `+methodForSelector:`, which asks the metaclass for a CLASS method — the distinction Apple's two doors make
 * and the one this tree's `fn_signature_for` helper already honours for `-methodSignatureForSelector:`.
 */
+ (BOOL)resolveInstanceMethod:(SEL)aSelector;
+ (BOOL)resolveClassMethod:(SEL)aSelector;
+ (nullable IMP)instanceMethodForSelector:(SEL)aSelector;
+ (nullable NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)aSelector;
+ (void)load;			/* the runtime calls these; declared so overrides match */
+ (void)initialize;
- (BOOL)isProxy;
/* THE ZONE IS THE OBJECT'S ALLOCATION IDENTITY, declared here through the NSObject protocol and
 * implemented on the class above. A root class that conforms to the protocol supplies it. */

/*
 * Equality and hashing. The defaults are identity and the pointer, which is
 * exactly what a Dictionary key has to override.
 */
- (BOOL)isEqual:(id)other;
@property (readonly) NSUInteger hash;

/*
 * Every object describes itself: `-description` names the class (docs, F1), and
 * `-debugDescription` is the debugger's spelling. BOTH ARE PROPERTIES, as they
 * are in the protocol above and on Darwin, and that is not cosmetic: the Swift
 * importer takes the shape of the *class's* declaration, and a method-shaped
 * `description` cannot satisfy `CustomStringConvertible`, which is what the
 * overlay's conformance needs. Declaring the getters twice, once as a property
 * and once as a method, is legal Objective-C but the method wins the import.
 */
@property (readonly, copy) NSString *description;
@property (readonly, copy) NSString *debugDescription;

/*
 * THE C ACCESSORS (W2a, docs/design/foundation-plan.md §12.3): the boundary between the
 * runtime's names and this library's strings. Apple declares them in NSObjCRuntime.h, and
 * they CANNOT live there in this tree: that header is the lowest level and has no
 * `NSString` in scope, and opening a nullability region in it would subject its C block
 * typedef to the completeness check the gate exempts it from. So they are declared here,
 * where the class they answer with is already forward-declared.
 *
 * The contracts worth stating: `NSClassFromString` answers Nil for a name nothing
 * registers and `NSStringFromClass(nil)` answers nil; `NSSelectorFromString` REGISTERS a
 * name that was never compiled (the runtime's behaviour, not a lookup failure).
 */
NSString * _Nullable NSStringFromClass(Class _Nullable aClass);
Class _Nullable NSClassFromString(NSString *aClassName);
NSString *NSStringFromSelector(SEL aSelector);
/* APPLE'S HEADER IS THE SPECIFICATION, AND APPLE'S DOCUMENTATION IS THE BEHAVIOUR, and here the
 * two disagree: the declaration is nonnull, while the documentation says "if aSelectorName is nil,
 * or cannot be converted to UTF-8 ... it returns (SEL)0". D8 of §11.6.1 asked which one wins, and
 * the answer is the API surface — so this is declared nonnull exactly as Apple's is, the writer
 * keeps returning the null selector exactly as Apple documents, and the single building site
 * silences -Wnonnull (which Apple's own build must do as well). A nullable here was NOT necessary,
 * which is the only test the policy allows. */
SEL NSSelectorFromString(NSString *aSelectorName);
NSString *NSStringFromRange(NSRange range);

/* THE PAGE FUNCTIONS (W2e): a region of the process's address space, named for pages. They live
 * here because Apple declares them with the object-allocation functions — a region to allocate
 * an object in is the same layer. The pointers are NONNULL by contract: a caller checks the
 * answer before using it, which is what the probe does. */
void * _Nullable NSAllocateMemoryPages(NSUInteger numberOfBytes);
void NSCopyMemoryPages(const void *source, void *dest, NSUInteger numberOfBytes);
void NSDeallocateMemoryPages(void *ptr, NSUInteger numberOfBytes);

/* THE OBJECT-ALLOCATION FAMILY. `NSAllocateObject` is the primitive `+allocWithZone:` uses: it
 * creates the instance through the runtime (so the retain count and C++ construction are the
 * runtime's) and records the zone. `NSCopyObject` is the raw byte copy — instance variables only,
 * a fresh count of one, extra bytes zeroed — and is the primitive a class's `-copyWithZone:` can
 * use when every ivar is a value. A class with owned object pointers must implement its own copy
 * instead; the primitive cannot know which pointers need retaining. */
FOUNDATION_EXPORT id NSAllocateObject(Class aClass, NSUInteger extraBytes, NSZone * _Nullable zone);
FOUNDATION_EXPORT void NSDeallocateObject(id object);
FOUNDATION_EXPORT id NSCopyObject(id object, NSUInteger extraBytes, NSZone * _Nullable zone);
/* YES when a copy into `requestedZone` must retain the object: that is, when the zones differ (or
 * no zone was requested). A copy within the same zone may share the reference. */
FOUNDATION_EXPORT BOOL NSShouldRetainWithZone(id anObject, NSZone * _Nullable requestedZone);

NS_ASSUME_NONNULL_END

@end

#endif /* FOUNDATION_NSOBJECT_H */
