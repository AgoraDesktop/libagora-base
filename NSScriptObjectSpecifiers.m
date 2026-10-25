/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptObjectSpecifiers.m — the specifier tree, its evaluation, and the NSObject doors that answer it.
 *
 * THE EVALUATION IS A WALK OVER CONTAINERS. Every specifier answers "which indices of my container's value do I
 * name?"; the base class turns those indices into objects. A property specifier answers "no indices", which means the
 * value itself. That one sentence is the model, and every subclass below is a different index rule.
 */
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#include <objc/runtime.h>
#include <stdlib.h>

/* Normalize a container answer (a single object, an array, or nil) into an array. */
static NSArray *fn_containers(id containers)
{
	if (containers == nil) {
		return [NSArray array];
	}
	if ([containers isKindOfClass:[NSArray class]]) {
		return containers;
	}
	return [NSArray arrayWithObject:containers];
}

/* An index set as an NSArray of NSNumbers, which is what the evaluation seam returns. */
static NSArray *fn_index_array(NSIndexSet *indexes)
{
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:[indexes count]];
	NSUInteger index = [indexes firstIndex];

	while (index != NSNotFound) {
		[out addObject:[NSNumber numberWithUnsignedInteger:index]];
		index = [indexes indexGreaterThanIndex:index];
	}
	return out;
}

static id fn_collection_object(NSArray *collection, NSUInteger index)
{
	if ([collection isKindOfClass:[NSArray class]]) {
		return index < [collection count] ? [collection objectAtIndex:index] : nil;
	}
	if ([collection isKindOfClass:[NSSet class]]) {
		NSArray *all = [(NSSet *)collection allObjects];

		return index < [all count] ? [all objectAtIndex:index] : nil;
	}
	return nil;
}

@implementation NSScriptObjectSpecifier

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_containerClassDescription = [classDescription retain];
	_containerSpecifier = [container retain];
	_key = [property copy];
	return self;
}

- (instancetype)initWithContainerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)property
{
	return [self initWithContainerClassDescription:nil containerSpecifier:container key:property];
}

- (void)dealloc
{
	[_containerClassDescription release];
	[_containerSpecifier release];
	[_key release];
	[_childSpecifier release];
	[_evaluationErrorSpecifier release];
	[super dealloc];
}

- (NSScriptClassDescription *)containerClassDescription { return _containerClassDescription; }
- (void)setContainerClassDescription:(NSScriptClassDescription *)value
{
	[value retain];
	[_containerClassDescription release];
	_containerClassDescription = value;
}
- (NSScriptObjectSpecifier *)containerSpecifier { return _containerSpecifier; }
- (void)setContainerSpecifier:(NSScriptObjectSpecifier *)value
{
	[value retain];
	[_containerSpecifier release];
	_containerSpecifier = value;
}
- (NSString *)key { return _key; }
- (void)setKey:(NSString *)value { [_key release]; _key = [value copy]; }
- (NSScriptObjectSpecifier *)childSpecifier { return _childSpecifier; }
- (void)setChildSpecifier:(NSScriptObjectSpecifier *)value
{
	[value retain];
	[_childSpecifier release];
	_childSpecifier = value;
}
- (BOOL)containerIsObjectBeingTested { return _containerIsObjectBeingTested; }
- (void)setContainerIsObjectBeingTested:(BOOL)flag { _containerIsObjectBeingTested = flag; }
- (BOOL)containerIsRangeContainerObject { return _containerIsRangeContainerObject; }
- (void)setContainerIsRangeContainerObject:(BOOL)flag { _containerIsRangeContainerObject = flag; }
- (NSScriptClassDescription *)keyClassDescription
{
	return [_containerClassDescription classDescriptionForKey:_key];
}
- (NSInteger)evaluationErrorNumber { return _evaluationErrorNumber; }
- (void)setEvaluationErrorNumber:(NSInteger)number { _evaluationErrorNumber = number; }
- (NSScriptObjectSpecifier *)evaluationErrorSpecifier { return _evaluationErrorSpecifier; }
- (void)setEvaluationErrorSpecifier:(NSScriptObjectSpecifier *)specifier
{
	[specifier retain];
	[_evaluationErrorSpecifier release];
	_evaluationErrorSpecifier = specifier;
}

/* THE CONTAINERS, IN APPLE'S ORDER: the container specifier's objects, the object being tested, the range container,
 * and finally the top-level object. A nil answer is an empty array rather than a failure; the failure is recorded when
 * the key cannot be read. */
- (NSArray *)fnContainers
{
	NSScriptExecutionContext *context = [NSScriptExecutionContext sharedScriptExecutionContext];

	if (_containerSpecifier != nil) {
		return fn_containers([_containerSpecifier objectsByEvaluatingSpecifier]);
	}
	if (_containerIsObjectBeingTested) {
		return fn_containers([context objectBeingTested]);
	}
	if (_containerIsRangeContainerObject) {
		return fn_containers([context rangeContainerObject]);
	}
	return fn_containers([context topLevelObject]);
}

- (NSArray *)objectsByEvaluatingWithContainers:(id)containers
{
	NSMutableArray *objects = [NSMutableArray array];
	NSArray *list = fn_containers(containers);
	NSUInteger i;

	for (i = 0; i < [list count]; i++) {
		id container = [list objectAtIndex:i];
		id collection = container;
		NSArray *indices;

		if (_key != nil && [_key length] > 0) {
			/* A KEY THE CONTAINER DOES NOT ANSWER IS AN EVALUATION ERROR, NOT AN EXCEPTION: `-valueForKey:` raises
			 * for an undefined key, and a script asking an object it did not understand for a property is exactly
			 * the case the script-error fields exist for. */
			@try {
				collection = [container valueForKey:_key];
			} @catch (id exception) {
				(void)exception;
				_evaluationErrorNumber = 1;
				[self setEvaluationErrorSpecifier:self];
				continue;
			}
		}
		if (collection == nil) {
			continue;
		}
		indices = [self indicesOfObjectsByEvaluatingWithContainer:container count:
			   ([collection isKindOfClass:[NSArray class]] ? (NSInteger)[(NSArray *)collection count]
								       : ([collection isKindOfClass:[NSSet class]]
									  ? (NSInteger)[(NSSet *)collection count] : 1))];
		if (indices == nil) {
			[objects addObject:collection];		/* a property: the value itself */
			continue;
		}
		{
			NSUInteger j;

			for (j = 0; j < [indices count]; j++) {
				id object = fn_collection_object(collection,
					(NSUInteger)[[indices objectAtIndex:j] integerValue]);

				if (object != nil) {
					[objects addObject:object];
				}
			}
		}
	}
	if ([objects count] == 0) {
		_evaluationErrorNumber = 1;
		[self setEvaluationErrorSpecifier:self];
	}
	return objects;
}

- (id)objectsByEvaluatingSpecifier
{
	if (_childSpecifier != nil) {
		if ([_childSpecifier containerSpecifier] == nil) {
			[_childSpecifier setContainerSpecifier:self];
		}
		return [_childSpecifier objectsByEvaluatingSpecifier];
	}
	{
		NSArray *objects = [self objectsByEvaluatingWithContainers:[self fnContainers]];

		/* A PROPERTY'S ANSWER IS THE VALUE, NOT A ONE-ELEMENT ARRAY; every element specifier answers an array. */
		return [self isKindOfClass:[NSPropertySpecifier class]] && [objects count] == 1
			? [objects objectAtIndex:0] : objects;
	}
}

/* THE BASE ANSWERS nil: "no indices" means the container's value itself. */
- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	(void)container;
	(void)count;
	return nil;
}

/* THE DESCRIPTOR IS A PATH STRING. Apple's real encoding is a private AppleEvent record; this library's descriptor is
 * a data type, so the specifier travels as `typeObjectSpecifier` with a dotted key path, and the class method reads a
 * chain of property specifiers back. It round-trips THIS library's specifiers and is documented as such. */
- (NSString *)fnPath
{
	if (_containerSpecifier != nil) {
		NSString *base = [_containerSpecifier fnPath];

		return base != nil ? [NSString stringWithFormat:@"%@.%@", base, _key] : _key;
	}
	return _key != nil ? _key : @"";
}

- (NSAppleEventDescriptor *)descriptor
{
	NSData *bytes = [[self fnPath] dataUsingEncoding:NSUTF8StringEncoding];

	return [NSAppleEventDescriptor descriptorWithDescriptorType:'obj '
							      data:bytes];
}

+ (NSScriptObjectSpecifier *)objectSpecifierWithDescriptor:(NSAppleEventDescriptor *)descriptor
{
	NSString *path;
	NSArray *components;
	NSScriptObjectSpecifier *specifier = nil;
	NSUInteger i;

	if (descriptor == nil || [descriptor descriptorType] != 'obj ') {
		return nil;
	}
	path = [[[NSString alloc] initWithData:[descriptor data] encoding:NSUTF8StringEncoding] autorelease];
	if (path == nil) {
		return nil;
	}
	components = [path componentsSeparatedByString:@"."];
	for (i = 0; i < [components count]; i++) {
		specifier = [[[NSPropertySpecifier alloc] initWithContainerSpecifier:specifier
										key:[components objectAtIndex:i]]
			     autorelease];
	}
	return specifier;
}

@end

/* ---- THE CONCRETE KINDS ---------------------------------------------------------------------------------------- */

@implementation NSPropertySpecifier
@end

@implementation NSIndexSpecifier

/* THE OVERRIDE A SUBCLASS OWES THE BASE'S DESIGNATED DOOR (`initWithContainerClassDescription:containerSpecifier:key:`):
 * a class that marks a designated initializer of its own has to say what the inherited one means here. It is a
 * CONVENIENCE override — it routes to THIS class's designated door — which is why it adds no mark of its own:
 * no index yet, and NSNotFound is this family's spelling of that. */
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
                              containerSpecifier:(NSScriptObjectSpecifier *)container
                                             key:(NSString *)property
{
	return [self initWithContainerClassDescription:classDescription
	                          containerSpecifier:container
	                                         key:property
	                                        index:NSNotFound];
}

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
					  index:(NSInteger)index
{
	self = [super initWithContainerClassDescription:classDescription containerSpecifier:container key:property];
	if (self != nil) {
		_index = index;
	}
	return self;
}

- (NSInteger)index { return _index; }
- (void)setIndex:(NSInteger)index { _index = index; }

/* A NEGATIVE INDEX COUNTS FROM THE END, which is Apple's spelling for "the last one". */
- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	NSInteger index = _index < 0 ? count + _index : _index;

	(void)container;
	if (index < 0 || index >= count) {
		return [NSArray array];
	}
	return [NSArray arrayWithObject:[NSNumber numberWithInteger:index]];
}

@end

@implementation NSNameSpecifier

/* THE OVERRIDE A SUBCLASS OWES THE BASE'S DESIGNATED DOOR (`initWithContainerClassDescription:containerSpecifier:key:`):
 * a class that marks a designated initializer of its own has to say what the inherited one means here. It is a
 * CONVENIENCE override — it routes to THIS class's designated door — which is why it adds no mark of its own:
 * no name yet, and nil is the same "not present" the components use. */
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
                              containerSpecifier:(NSScriptObjectSpecifier *)container
                                             key:(NSString *)property
{
	return [self initWithContainerClassDescription:classDescription
	                          containerSpecifier:container
	                                         key:property
	                                        name:nil];
}

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
					   name:(NSString *)name
{
	self = [super initWithContainerClassDescription:classDescription containerSpecifier:container key:property];
	if (self != nil) {
		_name = [name copy];
	}
	return self;
}

- (void)dealloc { [_name release]; [super dealloc]; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)value { [_name release]; _name = [value copy]; }

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	NSMutableArray *indices = [NSMutableArray array];
	id value = [_key length] > 0 ? [container valueForKey:_key] : container;
	NSArray *items = [value isKindOfClass:[NSSet class]] ? [value allObjects] : value;
	NSInteger i;

	for (i = 0; i < count && [items isKindOfClass:[NSArray class]] && i < (NSInteger)[items count]; i++) {
		id item = [items objectAtIndex:(NSUInteger)i];
		id name = [item valueForKey:@"name"];

		if (name == nil) {
			name = [item description];
		}
		if ([name isEqual:_name]) {
			[indices addObject:[NSNumber numberWithInteger:i]];
		}
	}
	return indices;
}

@end

@implementation NSUniqueIDSpecifier

/* THE OVERRIDE A SUBCLASS OWES THE BASE'S DESIGNATED DOOR (`initWithContainerClassDescription:containerSpecifier:key:`):
 * a class that marks a designated initializer of its own has to say what the inherited one means here. It is a
 * CONVENIENCE override — it routes to THIS class's designated door — which is why it adds no mark of its own:
 * no unique ID yet, and nil says so. */
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
                              containerSpecifier:(NSScriptObjectSpecifier *)container
                                             key:(NSString *)property
{
	return [self initWithContainerClassDescription:classDescription
	                          containerSpecifier:container
	                                         key:property
	                                        uniqueID:nil];
}

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
				       uniqueID:(id)uniqueID
{
	self = [super initWithContainerClassDescription:classDescription containerSpecifier:container key:property];
	if (self != nil) {
		_uniqueID = [uniqueID retain];
	}
	return self;
}

- (void)dealloc { [_uniqueID release]; [super dealloc]; }
- (id)uniqueID { return _uniqueID; }
- (void)setUniqueID:(id)value { [value retain]; [_uniqueID release]; _uniqueID = value; }

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	NSMutableArray *indices = [NSMutableArray array];
	id value = [_key length] > 0 ? [container valueForKey:_key] : container;
	NSArray *items = [value isKindOfClass:[NSSet class]] ? [value allObjects] : value;
	NSInteger i;

	for (i = 0; i < count && [items isKindOfClass:[NSArray class]] && i < (NSInteger)[items count]; i++) {
		id item = [items objectAtIndex:(NSUInteger)i];
		id identifier = [item valueForKey:@"uniqueID"];

		if (identifier == nil) {
			identifier = [item valueForKey:@"id"];
		}
		if ([identifier isEqual:_uniqueID]) {
			[indices addObject:[NSNumber numberWithInteger:i]];
		}
	}
	return indices;
}

@end

@implementation NSRangeSpecifier

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
				 startSpecifier:(NSScriptObjectSpecifier *)startSpecifier
				   endSpecifier:(NSScriptObjectSpecifier *)endSpecifier
{
	self = [super initWithContainerClassDescription:classDescription containerSpecifier:container key:property];
	if (self != nil) {
		_startSpecifier = [startSpecifier retain];
		_endSpecifier = [endSpecifier retain];
	}
	return self;
}

- (void)dealloc
{
	[_startSpecifier release];
	[_endSpecifier release];
	[super dealloc];
}

- (NSScriptObjectSpecifier *)startSpecifier { return _startSpecifier; }
- (void)setStartSpecifier:(NSScriptObjectSpecifier *)value
{
	[value retain];
	[_startSpecifier release];
	_startSpecifier = value;
}
- (NSScriptObjectSpecifier *)endSpecifier { return _endSpecifier; }
- (void)setEndSpecifier:(NSScriptObjectSpecifier *)value
{
	[value retain];
	[_endSpecifier release];
	_endSpecifier = value;
}

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	NSArray *start = [_startSpecifier indicesOfObjectsByEvaluatingWithContainer:container count:count];
	NSArray *end = [_endSpecifier indicesOfObjectsByEvaluatingWithContainer:container count:count];
	NSInteger first = [start count] > 0 ? [[start objectAtIndex:0] integerValue] : 0;
	NSInteger last = [end count] > 0 ? [[end objectAtIndex:0] integerValue] : count - 1;
	NSMutableArray *indices = [NSMutableArray array];
	NSInteger i;

	if (last < first) {
		NSInteger swap = last;

		last = first;
		first = swap;
	}
	for (i = first; i <= last && i < count; i++) {
		if (i >= 0) {
			[indices addObject:[NSNumber numberWithInteger:i]];
		}
	}
	return indices;
}


/* THE OVERRIDE A SUBCLASS OWES THE BASE'S DESIGNATED DOOR: a CONVENIENCE one that routes to this class's own
 * designated door, with neither bound set — the range door is the only way to state one. */
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
                              containerSpecifier:(NSScriptObjectSpecifier *)container
                                             key:(NSString *)property
{
	return [self initWithContainerClassDescription:classDescription
	                          containerSpecifier:container
	                                         key:property
	                              startSpecifier:nil
	                                endSpecifier:nil];
}
@end

@implementation NSRelativeSpecifier

/* THE OVERRIDE A SUBCLASS OWES THE BASE'S DESIGNATED DOOR (`initWithContainerClassDescription:containerSpecifier:key:`):
 * a class that marks a designated initializer of its own has to say what the inherited one means here. It is a
 * CONVENIENCE override — it routes to THIS class's designated door — which is why it adds no mark of its own:
 * no position and no base yet — NSRelativeAfter is the enum's zero. */
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
                              containerSpecifier:(NSScriptObjectSpecifier *)container
                                             key:(NSString *)property
{
	return [self initWithContainerClassDescription:classDescription
	                          containerSpecifier:container
	                                         key:property
	                                        relativePosition:NSRelativeAfter baseSpecifier:nil];
}

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
			       relativePosition:(NSRelativePosition)relPos
				  baseSpecifier:(NSScriptObjectSpecifier *)baseSpecifier
{
	self = [super initWithContainerClassDescription:classDescription containerSpecifier:container key:property];
	if (self != nil) {
		_relativePosition = relPos;
		_baseSpecifier = [baseSpecifier retain];
	}
	return self;
}

- (void)dealloc { [_baseSpecifier release]; [super dealloc]; }
- (NSRelativePosition)relativePosition { return _relativePosition; }
- (void)setRelativePosition:(NSRelativePosition)position { _relativePosition = position; }
- (NSScriptObjectSpecifier *)baseSpecifier { return _baseSpecifier; }
- (void)setBaseSpecifier:(NSScriptObjectSpecifier *)value
{
	[value retain];
	[_baseSpecifier release];
	_baseSpecifier = value;
}

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	NSArray *base = [_baseSpecifier indicesOfObjectsByEvaluatingWithContainer:container count:count];
	NSInteger index;
	NSInteger i;

	if ([base count] == 0) {
		/* NO BASE SPECIFIER MEANS "RELATIVE TO THE CONTAINER ITSELF": before is the first element, after the last. */
		i = (_relativePosition == NSRelativeBefore) ? 0 : count - 1;
	} else {
		index = [[base objectAtIndex:0] integerValue];
		i = (_relativePosition == NSRelativeBefore) ? index - 1 : index + 1;
	}
	return (i >= 0 && i < count) ? [NSArray arrayWithObject:[NSNumber numberWithInteger:i]] : [NSArray array];
}

@end

@implementation NSMiddleSpecifier

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	(void)container;
	return count > 0 ? [NSArray arrayWithObject:[NSNumber numberWithInteger:count / 2]] : [NSArray array];
}

@end

@implementation NSRandomSpecifier

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	(void)container;
	return count > 0 ? [NSArray arrayWithObject:[NSNumber numberWithInteger:arc4random_uniform((uint32_t)count)]]
			 : [NSArray array];
}

@end

@implementation NSWhoseSpecifier

/* THE OVERRIDE A SUBCLASS OWES THE BASE'S DESIGNATED DOOR (`initWithContainerClassDescription:containerSpecifier:key:`):
 * a class that marks a designated initializer of its own has to say what the inherited one means here. It is a
 * CONVENIENCE override — it routes to THIS class's designated door — which is why it adds no mark of its own:
 * no test yet. */
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
                              containerSpecifier:(NSScriptObjectSpecifier *)container
                                             key:(NSString *)property
{
	return [self initWithContainerClassDescription:classDescription
	                          containerSpecifier:container
	                                         key:property
	                                        test:nil];
}

- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDescription
			       containerSpecifier:(NSScriptObjectSpecifier *)container
					    key:(NSString *)property
					   test:(NSScriptWhoseTest *)test
{
	self = [super initWithContainerClassDescription:classDescription containerSpecifier:container key:property];
	if (self != nil) {
		_test = [test retain];
	}
	return self;
}

- (void)dealloc { [_test release]; [super dealloc]; }
- (NSScriptWhoseTest *)test { return _test; }
- (void)setTest:(NSScriptWhoseTest *)value { [value retain]; [_test release]; _test = value; }
- (NSWhoseSubelementIdentifier)startSubelementIdentifier { return _startSubelementIdentifier; }
- (void)setStartSubelementIdentifier:(NSWhoseSubelementIdentifier)value { _startSubelementIdentifier = value; }
- (NSInteger)startSubelementIndex { return _startSubelementIndex; }
- (void)setStartSubelementIndex:(NSInteger)value { _startSubelementIndex = value; }
- (NSWhoseSubelementIdentifier)endSubelementIdentifier { return _endSubelementIdentifier; }
- (void)setEndSubelementIdentifier:(NSWhoseSubelementIdentifier)value { _endSubelementIdentifier = value; }
- (NSInteger)endSubelementIndex { return _endSubelementIndex; }
- (void)setEndSubelementIndex:(NSInteger)value { _endSubelementIndex = value; }

- (NSArray *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger)count
{
	NSMutableArray *indices = [NSMutableArray array];
	id value = [_key length] > 0 ? [container valueForKey:_key] : container;
	NSArray *items = [value isKindOfClass:[NSSet class]] ? [value allObjects] : value;
	NSScriptExecutionContext *context = [NSScriptExecutionContext sharedScriptExecutionContext];
	id saved = [context objectBeingTested];
	NSInteger i;

	for (i = 0; i < count && [items isKindOfClass:[NSArray class]] && i < (NSInteger)[items count]; i++) {
		[context setObjectBeingTested:[items objectAtIndex:(NSUInteger)i]];
		if ([_test isTrue]) {
			[indices addObject:[NSNumber numberWithInteger:i]];
		}
	}
	[context setObjectBeingTested:saved];
	return indices;
}

@end

/* ---- INSERTION POSITIONS --------------------------------------------------------------------------------------- */

@implementation NSPositionalSpecifier

- (instancetype)initWithPosition:(NSPositioning)position objectSpecifier:(NSScriptObjectSpecifier *)specifier
{
	self = [super init];
	if (self != nil) {
		_position = position;
		_objectSpecifier = [specifier retain];
	}
	return self;
}

- (void)dealloc
{
	[_objectSpecifier release];
	[_insertionClassDescription release];
	[_insertionContainer release];
	[_insertionKey release];
	[super dealloc];
}

- (NSPositioning)position { return _position; }
- (NSScriptObjectSpecifier *)objectSpecifier { return _objectSpecifier; }
- (NSScriptClassDescription *)insertionClassDescription { return _insertionClassDescription; }
- (void)setInsertionClassDescription:(NSScriptClassDescription *)description
{
	[description retain];
	[_insertionClassDescription release];
	_insertionClassDescription = description;
}
- (id)insertionContainer { return _insertionContainer; }
- (NSString *)insertionKey { return _insertionKey; }
- (NSInteger)insertionIndex { return _insertionIndex; }
- (BOOL)insertionReplaces { return _insertionReplaces; }

/* THE POSITION IS RESOLVED AGAINST THE CONTAINER'S COLLECTION. `before`/`after` are the element specifier's index
 * shifted by one; beginning and end are the two edges; replace names the element itself and says so. */
- (void)evaluate
{
	id container = [_objectSpecifier containerSpecifier] != nil
		? [[_objectSpecifier containerSpecifier] objectsByEvaluatingSpecifier]
		: [[NSScriptExecutionContext sharedScriptExecutionContext] topLevelObject];
	id collection;
	NSInteger count = 0;
	NSArray *indices;

	if ([container isKindOfClass:[NSArray class]] && [container count] == 1 &&
	    ![[_objectSpecifier containerSpecifier] isKindOfClass:[NSPropertySpecifier class]]) {
		container = [container objectAtIndex:0];
	}
	_insertionContainer = [container retain];
	_insertionKey = [[_objectSpecifier key] copy];
	collection = [_objectSpecifier key] != nil ? [container valueForKey:[_objectSpecifier key]] : nil;
	if ([collection isKindOfClass:[NSArray class]]) {
		count = (NSInteger)[(NSArray *)collection count];
	}
	indices = [_objectSpecifier indicesOfObjectsByEvaluatingWithContainer:container count:count];
	switch (_position) {
	case NSPositionBeginning:
		_insertionIndex = 0;
		break;
	case NSPositionEnd:
		_insertionIndex = count;
		break;
	case NSPositionReplace:
		_insertionIndex = [indices count] > 0 ? [[indices objectAtIndex:0] integerValue] : count;
		_insertionReplaces = YES;
		break;
	case NSPositionBefore:
		_insertionIndex = [indices count] > 0 ? [[indices objectAtIndex:0] integerValue] : 0;
		break;
	case NSPositionAfter:
		_insertionIndex = ([indices count] > 0 ? [[indices objectAtIndex:0] integerValue] : count - 1) + 1;
		break;
	}
}

@end

/* ---- THE CONTEXT AND THE COERCER ------------------------------------------------------------------------------- */

static NSScriptExecutionContext *fn_script_context = nil;

@implementation NSScriptExecutionContext

+ (NSScriptExecutionContext *)sharedScriptExecutionContext
{
	if (fn_script_context == nil) {
		fn_script_context = [[NSScriptExecutionContext alloc] init];
	}
	return fn_script_context;
}

- (id)topLevelObject { return _topLevelObject; }
- (void)setTopLevelObject:(id)object { [object retain]; [_topLevelObject release]; _topLevelObject = object; }
- (id)objectBeingTested { return _objectBeingTested; }
- (void)setObjectBeingTested:(id)object
{
	[object retain];
	[_objectBeingTested release];
	_objectBeingTested = object;
}
- (id)rangeContainerObject { return _rangeContainerObject; }
- (void)setRangeContainerObject:(id)object
{
	[object retain];
	[_rangeContainerObject release];
	_rangeContainerObject = object;
}

@end

static NSScriptCoercionHandler *fn_coercion_handler = nil;

@implementation NSScriptCoercionHandler

+ (NSScriptCoercionHandler *)sharedCoercionHandler
{
	if (fn_coercion_handler == nil) {
		fn_coercion_handler = [[NSScriptCoercionHandler alloc] init];
	}
	return fn_coercion_handler;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_coercers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc { [_coercers release]; [super dealloc]; }

- (NSString *)fnKeyFrom:(Class)fromClass to:(Class)toClass
{
	return [NSString stringWithFormat:@"%@->%@", NSStringFromClass(fromClass), NSStringFromClass(toClass)];
}

- (void)registerCoercer:(id)coercer
	       selector:(SEL)selector
	 toConvertFromClass:(Class)fromClass
		     toClass:(Class)toClass
{
	NSArray *entry = [NSArray arrayWithObjects:coercer,
			  [NSString stringWithUTF8String:sel_getName(selector)], nil];

	[_coercers setObject:entry forKey:[self fnKeyFrom:fromClass to:toClass]];
}

- (id)coerceValue:(id)value toClass:(Class)toClass
{
	NSArray *entry;
	Class fromClass;

	if (value == nil) {
		return nil;
	}
	if (toClass == Nil || [value isKindOfClass:toClass]) {
		return value;
	}
	fromClass = [value class];
	entry = [_coercers objectForKey:[self fnKeyFrom:fromClass to:toClass]];
	if (entry != nil) {
		id coercer = [entry objectAtIndex:0];
		SEL selector = sel_registerName([[entry objectAtIndex:1] UTF8String]);

		return [coercer performSelector:selector withObject:value];
	}
	return nil;
}

@end

/* ---- THE NSObject DOORS ---------------------------------------------------------------------------------------- */

static char fn_scripting_properties_key;

@implementation NSObject (NSScriptObjectSpecifiers)

- (NSScriptObjectSpecifier *)objectSpecifier
{
	return nil;		/* the default: an object is not automatically addressable by a script */
}

- (NSArray *)indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *)specifier
{
	(void)specifier;
	return nil;
}

- (id)valueAtIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key
{
	id collection = [self valueForKey:key];

	if ([collection isKindOfClass:[NSArray class]] && index < [collection count]) {
		return [collection objectAtIndex:index];
	}
	if ([collection isKindOfClass:[NSSet class]]) {
		NSArray *all = [collection allObjects];

		return index < [all count] ? [all objectAtIndex:index] : nil;
	}
	return nil;
}

- (void)insertValue:(id)value atIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key
{
	[[self mutableArrayValueForKey:key] insertObject:value atIndex:index];
}

- (void)removeValueAtIndex:(NSUInteger)index fromPropertyWithKey:(NSString *)key
{
	[[self mutableArrayValueForKey:key] removeObjectAtIndex:index];
}

- (void)replaceValueAtIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key withValue:(id)value
{
	[[self mutableArrayValueForKey:key] replaceObjectAtIndex:index withObject:value];
}

- (void)insertValue:(id)value inPropertyWithKey:(NSString *)key
{
	[[self mutableArrayValueForKey:key] addObject:value];
}

- (id)valueWithName:(NSString *)name inPropertyWithKey:(NSString *)key
{
	id collection = [self valueForKey:key];
	NSArray *items = [collection isKindOfClass:[NSSet class]] ? [collection allObjects] : collection;
	NSUInteger i;

	for (i = 0; [items isKindOfClass:[NSArray class]] && i < [items count]; i++) {
		id item = [items objectAtIndex:i];
		id itemName = [item valueForKey:@"name"];

		if (itemName == nil) {
			itemName = [item description];
		}
		if ([itemName isEqual:name]) {
			return item;
		}
	}
	return nil;
}

- (id)valueWithUniqueID:(id)uniqueID inPropertyWithKey:(NSString *)key
{
	id collection = [self valueForKey:key];
	NSArray *items = [collection isKindOfClass:[NSSet class]] ? [collection allObjects] : collection;
	NSUInteger i;

	for (i = 0; [items isKindOfClass:[NSArray class]] && i < [items count]; i++) {
		id item = [items objectAtIndex:i];
		id identifier = [item valueForKey:@"uniqueID"];

		if (identifier == nil) {
			identifier = [item valueForKey:@"id"];
		}
		if ([identifier isEqual:uniqueID]) {
			return item;
		}
	}
	return nil;
}

- (id)scriptingValueForSpecifier:(NSScriptObjectSpecifier *)specifier
{
	return [specifier objectsByEvaluatingSpecifier];
}

@end

@implementation NSObject (NSObjectScripting)

- (NSDictionary *)scriptingProperties
{
	return objc_getAssociatedObject(self, &fn_scripting_properties_key);
}

- (void)setScriptingProperties:(NSDictionary *)properties
{
	objc_setAssociatedObject(self, &fn_scripting_properties_key,
				 properties != nil ? [[properties copy] autorelease] : nil,
				 OBJC_ASSOCIATION_RETAIN);
}

- (id)copyScriptingValue:(id)value forKey:(NSString *)key withProperties:(NSDictionary *)properties
{
	id copy = [value copy];

	if (properties != nil) {
		[copy setValuesForKeysWithDictionary:properties];
	}
	[self setValue:copy forKey:key];
	return [copy autorelease];
}

- (id)newScriptingObjectOfClass:(Class)objectClass
		  forValueForKey:(NSString *)key
	       withContentsValue:(id)contentsValue
		      properties:(NSDictionary *)properties
{
	id object = [[objectClass alloc] init];

	if (contentsValue != nil) {
		[object setValue:contentsValue forKey:@"contents"];
	}
	if (properties != nil) {
		[object setValuesForKeysWithDictionary:properties];
	}
	[self insertValue:object inPropertyWithKey:key];
	return [object autorelease];
}

- (id)coerceValue:(id)value forKey:(NSString *)key
{
	id current = [self valueForKey:key];

	if (current == nil) {
		return value;
	}
	return [[NSScriptCoercionHandler sharedCoercionHandler] coerceValue:value toClass:[current class]];
}

@end
