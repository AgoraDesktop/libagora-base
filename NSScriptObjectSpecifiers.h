/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptObjectSpecifiers.h — how a script names an object, and the NSObject doors that answer it.
 *
 * An object specifier is a PATH: a container (another specifier, the object being tested, or the top-level object),
 * a key into it, and a subclass that says WHICH element of the key's value is meant (an index, a name, a unique ID,
 * a range, a relative position, the middle, a random one, or the ones a test accepts). `-objectsByEvaluatingSpecifier`
 * walks that path and answers the objects — which is the whole of the model, and what makes a command's receivers and
 * arguments evaluable without the command knowing where they came from.
 *
 * THE EVALUATION IS REAL AND THE ERROR IS A VALUE. A specifier that names nothing answers nil/empty and records
 * `-evaluationErrorNumber`; it does not raise, because a script that asks for a missing element is a script error the
 * command reports, not a crash.
 */
#ifndef FOUNDATION_NSSCRIPTOBJECTSPECIFIERS_H
#define FOUNDATION_NSSCRIPTOBJECTSPECIFIERS_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSCoding.h>

@class NSArray;
@class NSCoder;
@class NSScriptClassDescription;
@class NSAppleEventDescriptor;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NSRelativePosition) {
	NSRelativeAfter = 0,
	NSRelativeBefore = 1
};

typedef NS_ENUM(NSUInteger, NSWhoseSubelementIdentifier) {
	NSIndexSubelement = 0,
	NSEverySubelement = 1,
	NSMiddleSubelement = 2,
	NSRandomSubelement = 3,
	NSNoSubelement = 4
};

typedef NS_ENUM(NSUInteger, NSPositioning) {
	NSPositionAfter = 0,
	NSPositionBefore = 1,
	NSPositionBeginning = 2,
	NSPositionEnd = 3,
	NSPositionReplace = 4
};

/* ---- THE SPECIFIER TREE ---------------------------------------------------------------------------------------- */

/* THE CODER DOOR (§NSCoding). A specifier is a value a document and a script both keep, so it archives: the base class
 * writes the shared fields and each subclass writes its own below. The CONTAINER CLASS DESCRIPTION is the one field
 * that cannot be written — it is a registry object with no coder of its own — so a specifier that holds one cannot be
 * archived, which the base's -encodeWithCoder: says by raising rather than writing half a graph. */
@interface NSScriptObjectSpecifier : NSObject <NSCoding>
{
@protected
	NSScriptClassDescription *_containerClassDescription;
	NSScriptObjectSpecifier *_containerSpecifier;
	NSString *_key;
	NSScriptObjectSpecifier *_childSpecifier;
	BOOL _containerIsObjectBeingTested;
	BOOL _containerIsRangeContainerObject;
	NSInteger _evaluationErrorNumber;
	NSScriptObjectSpecifier *_evaluationErrorSpecifier;
}

- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithContainerSpecifier:(nullable NSScriptObjectSpecifier *)container
				       key:(NSString *)property;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (void)encodeWithCoder:(NSCoder *)coder;

@property (nullable, strong) NSScriptClassDescription *containerClassDescription;
@property (nullable, strong) NSScriptObjectSpecifier *containerSpecifier;
@property (copy) NSString *key;
@property (nullable, strong) NSScriptObjectSpecifier *childSpecifier;
@property BOOL containerIsObjectBeingTested;
@property BOOL containerIsRangeContainerObject;
@property (nullable, readonly) NSScriptClassDescription *keyClassDescription;
@property NSInteger evaluationErrorNumber;
@property (nullable, strong) NSScriptObjectSpecifier *evaluationErrorSpecifier;

/* THE EVALUATION. `-objectsByEvaluatingSpecifier` is the public answer; the two container forms are the seam a
 * subclass implements (`-indicesOfObjectsByEvaluatingWithContainer:count:`) and the base walks. */
- (nullable id)objectsByEvaluatingSpecifier;
- (NSArray *)objectsByEvaluatingWithContainers:(nullable id)containers;
- (nullable NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count;

/* THE APPLE-EVENT FORM. This library's descriptor is a data type, so the specifier travels as a typeObjectSpecifier
 * descriptor whose data is a small textual path; the class method reads it back as a property specifier. */
- (nullable NSAppleEventDescriptor *)descriptor NS_AVAILABLE_MAC(10_5);
+ (nullable NSScriptObjectSpecifier *)objectSpecifierWithDescriptor:(NSAppleEventDescriptor *)descriptor NS_AVAILABLE_MAC(10_5);

@end

/* THE CONCRETE KINDS. Each one answers `-indicesOfObjectsByEvaluatingWithContainer:count:`. */
@interface NSPropertySpecifier : NSScriptObjectSpecifier
@end

@interface NSIndexSpecifier : NSScriptObjectSpecifier
{
@private
	NSInteger _index;
}
- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property
					  index:(NSInteger)index NS_DESIGNATED_INITIALIZER;
@property NSInteger index;
/* DESIGNATED TOO, because this class marks a designated initializer of its own: the inherited coder door has to be
 * overridden as a designated one, which is what makes it an override rather than a convenience init calling super. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@end

@interface NSNameSpecifier : NSScriptObjectSpecifier
{
@private
	NSString *_name;
}
- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property
					   name:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@property (copy) NSString *name;
@end

@interface NSUniqueIDSpecifier : NSScriptObjectSpecifier
{
@private
	id _uniqueID;
}
- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property
				       uniqueID:(id)uniqueID NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@property (strong) id uniqueID;
@end

@interface NSRangeSpecifier : NSScriptObjectSpecifier
{
@private
	NSScriptObjectSpecifier *_startSpecifier;
	NSScriptObjectSpecifier *_endSpecifier;
}
- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property
				 startSpecifier:(nullable NSScriptObjectSpecifier *)startSpecifier
				   endSpecifier:(nullable NSScriptObjectSpecifier *)endSpecifier NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@property (nullable, strong) NSScriptObjectSpecifier *startSpecifier;
@property (nullable, strong) NSScriptObjectSpecifier *endSpecifier;
@end

@interface NSRelativeSpecifier : NSScriptObjectSpecifier
{
@private
	NSRelativePosition _relativePosition;
	NSScriptObjectSpecifier *_baseSpecifier;
}
- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property
			       relativePosition:(NSRelativePosition)relPos
				  baseSpecifier:(nullable NSScriptObjectSpecifier *)baseSpecifier NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@property NSRelativePosition relativePosition;
@property (nullable, strong) NSScriptObjectSpecifier *baseSpecifier;
@end

@interface NSMiddleSpecifier : NSScriptObjectSpecifier
@end

@interface NSRandomSpecifier : NSScriptObjectSpecifier
@end

@class NSScriptWhoseTest;

@interface NSWhoseSpecifier : NSScriptObjectSpecifier
{
@private
	NSScriptWhoseTest *_test;
	NSWhoseSubelementIdentifier _startSubelementIdentifier;
	NSInteger _startSubelementIndex;
	NSWhoseSubelementIdentifier _endSubelementIdentifier;
	NSInteger _endSubelementIndex;
}
- (instancetype)initWithContainerClassDescription:(nullable NSScriptClassDescription *)classDescription
			       containerSpecifier:(nullable NSScriptObjectSpecifier *)container
					    key:(NSString *)property
					   test:(NSScriptWhoseTest *)test NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
@property (strong) NSScriptWhoseTest *test;
@property NSWhoseSubelementIdentifier startSubelementIdentifier;
@property NSInteger startSubelementIndex;
@property NSWhoseSubelementIdentifier endSubelementIdentifier;
@property NSInteger endSubelementIndex;
@end

/* ---- INSERTION POSITIONS --------------------------------------------------------------------------------------- */

@interface NSPositionalSpecifier : NSObject
{
@private
	NSPositioning _position;
	NSScriptObjectSpecifier *_objectSpecifier;
	NSScriptClassDescription *_insertionClassDescription;
	id _insertionContainer;
	NSString *_insertionKey;
	NSInteger _insertionIndex;
	BOOL _insertionReplaces;
}
- (instancetype)initWithPosition:(NSPositioning)position
		objectSpecifier:(NSScriptObjectSpecifier *)specifier NS_DESIGNATED_INITIALIZER;
@property (readonly) NSPositioning position NS_AVAILABLE_MAC(10_5);
@property (readonly, strong) NSScriptObjectSpecifier *objectSpecifier NS_AVAILABLE_MAC(10_5);
@property (nullable, strong) NSScriptClassDescription *insertionClassDescription;
- (void)evaluate;
@property (nullable, readonly) id insertionContainer;
@property (nullable, readonly, copy) NSString *insertionKey;
@property (readonly) NSInteger insertionIndex;
@property (readonly) BOOL insertionReplaces;
@end

/* ---- THE CONTEXT AND THE COERCER ------------------------------------------------------------------------------- */

@interface NSScriptExecutionContext : NSObject
{
@private
	id _topLevelObject;
	id _objectBeingTested;
	id _rangeContainerObject;
}
+ (NSScriptExecutionContext *)sharedScriptExecutionContext;
@property (nullable, strong) id topLevelObject;
@property (nullable, strong) id objectBeingTested;
@property (nullable, strong) id rangeContainerObject;
@end

@interface NSScriptCoercionHandler : NSObject
{
@private
	id _coercers;
}
+ (NSScriptCoercionHandler *)sharedCoercionHandler;
- (void)registerCoercer:(id)coercer
	       selector:(SEL)selector
	 toConvertFromClass:(Class)fromClass
		     toClass:(Class)toClass;
- (nullable id)coerceValue:(id)value toClass:(Class)toClass;
@end

/* ---- THE NSObject DOORS ---------------------------------------------------------------------------------------- */

@interface NSObject (NSScriptObjectSpecifiers)

- (nullable NSScriptObjectSpecifier *)objectSpecifier;
- (nullable NSArray *)indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *)specifier;

- (nullable id)valueAtIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key;
- (void)insertValue:(id)value atIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key;
- (void)removeValueAtIndex:(NSUInteger)index fromPropertyWithKey:(NSString *)key;
- (void)replaceValueAtIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key withValue:(id)value;
- (void)insertValue:(id)value inPropertyWithKey:(NSString *)key;

- (nullable id)valueWithName:(NSString *)name inPropertyWithKey:(NSString *)key;
- (nullable id)valueWithUniqueID:(id)uniqueID inPropertyWithKey:(NSString *)key;

- (nullable id)scriptingValueForSpecifier:(NSScriptObjectSpecifier *)specifier NS_AVAILABLE_MAC(10_5);

@end

@interface NSObject (NSObjectScripting)

@property (nullable, copy) NSDictionary *scriptingProperties;

- (nullable id)copyScriptingValue:(id)value forKey:(NSString *)key withProperties:(nullable NSDictionary *)properties NS_AVAILABLE_MAC(10_5);
- (nullable id)newScriptingObjectOfClass:(Class)objectClass
			  forValueForKey:(NSString *)key
		       withContentsValue:(nullable id)contentsValue
			      properties:(nullable NSDictionary *)properties NS_AVAILABLE_MAC(10_5);
- (nullable id)coerceValue:(id)value forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTOBJECTSPECIFIERS_H */
