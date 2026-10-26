/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptCommand.m — execution, the nine standard commands, and the suite registries.
 */
#import <Foundation/NSScriptCommand.h>
#import <Foundation/NSScriptCommandDescription.h>
#import <Foundation/NSScriptSuiteRegistry.h>
#import <Foundation/NSScriptStandardSuiteCommands.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSNull.h>
#include <objc/runtime.h>

static NSString *const FNCurrentCommandStackKey = @"NSScriptCommandStack";

@implementation NSScriptCommand

- (instancetype)initWithCommandDescription:(NSScriptCommandDescription *)commandDescription
{
	self = [super init];
	if (self != nil) {
		_commandDescription = [commandDescription retain];
		_arguments = [[NSDictionary alloc] init];
	}
	return self;
}

/* THE CODER PAIR. The description is read FIRST and handed to the designated initializer, which is what makes this a
 * convenience door rather than a second funnel. Everything else a command carries is an object or an integer, so the
 * archive is the state itself.
 *
 * THE STANDARD SUITE'S KEY SPECIFIER travels with the command rather than through a coder door per subclass: the four
 * commands that have one answer `-keySpecifier`, so the base asks and writes it when the receiver has one, and reads it
 * back through `-setKeySpecifier:` the same way. That keeps ONE coder pair on the class Apple declares it on, and it
 * archives the whole command rather than the base's half of it. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [self initWithCommandDescription:[coder decodeObjectForKey:@"NSCommandDescription"]];
	if (self != nil) {
		_directParameter = [[coder decodeObjectForKey:@"NSDirectParameter"] retain];
		_receiversSpecifier = [[coder decodeObjectForKey:@"NSReceiversSpecifier"] retain];
		_arguments = [[coder decodeObjectForKey:@"NSArguments"] copy];
		_scriptErrorNumber = [coder decodeIntegerForKey:@"NSScriptErrorNumber"];
		_scriptErrorString = [[coder decodeObjectForKey:@"NSScriptErrorString"] copy];
		_scriptErrorExpectedTypeDescriptor =
			[[coder decodeObjectForKey:@"NSScriptErrorExpectedTypeDescriptor"] retain];
		_scriptErrorOffendingObjectDescriptor =
			[[coder decodeObjectForKey:@"NSScriptErrorOffendingObjectDescriptor"] retain];
		if ([self respondsToSelector:@selector(setKeySpecifier:)]) {
			id specifier = [coder decodeObjectForKey:@"NSKeySpecifier"];

			[self performSelector:@selector(setKeySpecifier:) withObject:specifier];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_commandDescription forKey:@"NSCommandDescription"];
	[coder encodeObject:_directParameter forKey:@"NSDirectParameter"];
	[coder encodeObject:_receiversSpecifier forKey:@"NSReceiversSpecifier"];
	[coder encodeObject:_arguments forKey:@"NSArguments"];
	[coder encodeInteger:_scriptErrorNumber forKey:@"NSScriptErrorNumber"];
	[coder encodeObject:_scriptErrorString forKey:@"NSScriptErrorString"];
	[coder encodeObject:_scriptErrorExpectedTypeDescriptor forKey:@"NSScriptErrorExpectedTypeDescriptor"];
	[coder encodeObject:_scriptErrorOffendingObjectDescriptor forKey:@"NSScriptErrorOffendingObjectDescriptor"];
	if ([self respondsToSelector:@selector(keySpecifier)]) {
		[coder encodeObject:[self performSelector:@selector(keySpecifier)] forKey:@"NSKeySpecifier"];
	}
}

- (void)dealloc
{
	[_commandDescription release];
	[_directParameter release];
	[_receiversSpecifier release];
	[_arguments release];
	[_appleEvent release];
	[_scriptErrorExpectedTypeDescriptor release];
	[_scriptErrorOffendingObjectDescriptor release];
	[_scriptErrorString release];
	[super dealloc];
}

+ (NSScriptCommand *)currentCommand
{
	NSMutableArray *stack = [[NSThread currentThread] threadDictionary][FNCurrentCommandStackKey];

	return [stack count] > 0 ? [stack lastObject] : nil;
}

- (NSScriptCommandDescription *)commandDescription { return _commandDescription; }
- (NSAppleEventDescriptor *)appleEvent { return _appleEvent; }
- (NSScriptObjectSpecifier *)receiversSpecifier { return _receiversSpecifier; }
- (void)setReceiversSpecifier:(NSScriptObjectSpecifier *)specifier
{
	[specifier retain];
	[_receiversSpecifier release];
	_receiversSpecifier = specifier;
}
- (id)directParameter { return _directParameter; }
- (void)setDirectParameter:(id)parameter
{
	[parameter retain];
	[_directParameter release];
	_directParameter = parameter;
}
- (NSDictionary *)arguments { return _arguments; }
- (void)setArguments:(NSDictionary *)arguments
{
	NSDictionary *copy = arguments != nil ? [arguments copy] : [[NSDictionary alloc] init];

	[_arguments release];
	_arguments = copy;
}

- (id)evaluatedReceivers
{
	id receivers = [_receiversSpecifier objectsByEvaluatingSpecifier];

	return receivers != nil ? receivers : _directParameter;
}

- (NSDictionary *)evaluatedArguments
{
	NSMutableDictionary *evaluated = [NSMutableDictionary dictionary];
	NSEnumerator *keys = [_arguments keyEnumerator];
	NSString *key;

	while ((key = [keys nextObject]) != nil) {
		id value = [_arguments objectForKey:key];

		if ([value isKindOfClass:[NSScriptObjectSpecifier class]]) {
			value = [value objectsByEvaluatingSpecifier];
		}
		[evaluated setObject:(value != nil ? value : [NSNull null]) forKey:key];
	}
	return evaluated;
}

- (BOOL)isWellFormed
{
	/* A COMMAND WITH NO DESCRIPTION HAS NO ARGUMENT SCHEMA, so nothing can be checked against it and the only honest
	 * answer is YES for a directly-built command and NO for one whose description is missing from a decoded event. */
	return _commandDescription != nil || _directParameter != nil || _receiversSpecifier != nil;
}

- (id)executeCommand
{
	NSMutableArray *stack;
	id result;

	stack = [[NSThread currentThread] threadDictionary][FNCurrentCommandStackKey];
	if (stack == nil) {
		stack = [NSMutableArray array];
		[[[NSThread currentThread] threadDictionary] setObject:stack forKey:FNCurrentCommandStackKey];
	}
	[stack addObject:self];
	result = [self performDefaultImplementation];
	[stack removeObjectIdenticalTo:self];
	return result;
}

- (id)performDefaultImplementation
{
	return nil;		/* a command class that overrides nothing has no default effect */
}

- (NSInteger)scriptErrorNumber { return _scriptErrorNumber; }
- (void)setScriptErrorNumber:(NSInteger)number { _scriptErrorNumber = number; }
- (NSString *)scriptErrorString { return _scriptErrorString; }
- (void)setScriptErrorString:(NSString *)string { [_scriptErrorString release]; _scriptErrorString = [string copy]; }
- (NSAppleEventDescriptor *)scriptErrorExpectedTypeDescriptor { return _scriptErrorExpectedTypeDescriptor; }
- (void)setScriptErrorExpectedTypeDescriptor:(NSAppleEventDescriptor *)descriptor
{
	[descriptor retain];
	[_scriptErrorExpectedTypeDescriptor release];
	_scriptErrorExpectedTypeDescriptor = descriptor;
}
- (id)scriptErrorOffendingObjectDescriptor { return _scriptErrorOffendingObjectDescriptor; }
- (void)setScriptErrorOffendingObjectDescriptor:(id)descriptor
{
	[descriptor retain];
	[_scriptErrorOffendingObjectDescriptor release];
	_scriptErrorOffendingObjectDescriptor = descriptor;
}

/* SUSPENSION NEEDS A TRANSPORT TO SUSPEND ON. Without an AppleEvent there is no asynchronous reply to suspend, so the
 * request is refused rather than accepted and silently never resumed. */
- (BOOL)suspendExecution
{
	_scriptErrorNumber = 1;
	_scriptErrorString = [@"NSScriptCommand: execution cannot be suspended without an AppleEvent transport" copy];
	return NO;
}

- (void)resumeExecutionWithResult:(id)result
{
	(void)result;
}

@end

/* ---- THE STANDARD SUITE'S COMMANDS ----------------------------------------------------------------------------- */

static NSArray *fn_receivers(NSScriptCommand *command)
{
	id receivers = [command evaluatedReceivers];

	if (receivers == nil) {
		return [NSArray array];
	}
	return [receivers isKindOfClass:[NSArray class]] ? receivers : [NSArray arrayWithObject:receivers];
}

#define FN_KEY_SPECIFIER(CLASS) \
	- (NSScriptObjectSpecifier *)keySpecifier { return _keySpecifier; } \
	- (void)setKeySpecifier:(NSScriptObjectSpecifier *)specifier \
	{ \
		[specifier retain]; \
		[_keySpecifier release]; \
		_keySpecifier = specifier; \
	}

@implementation NSSetCommand
FN_KEY_SPECIFIER(NSSetCommand)

/* SET WRITES THE DIRECT PARAMETER THROUGH THE KEY SPECIFIER ON EVERY RECEIVER. `setValue:forKey:` is the KVC door, so
 * a receiver that validates or announces sees the write. */
- (id)performDefaultImplementation
{
	NSArray *receivers = fn_receivers(self);
	NSString *key = [_keySpecifier key];
	NSUInteger i;

	for (i = 0; i < [receivers count]; i++) {
		id receiver = [receivers objectAtIndex:i];

		if (key != nil) {
			[receiver setValue:[self directParameter] forKey:key];
		} else {
			[[_keySpecifier containerSpecifier] setValue:[self directParameter]
							     forKey:[_keySpecifier key]];
		}
	}
	return nil;
}
@end

@implementation NSDeleteCommand
FN_KEY_SPECIFIER(NSDeleteCommand)

/* REMOVAL NEEDS THE CONTAINER, which the key specifier carries: the container's mutable array for the key is where the
 * receiver is removed from. A receiver whose container is not a mutable collection is reported as an error rather than
 * quietly left in place. */
- (id)performDefaultImplementation
{
	NSArray *receivers = fn_receivers(self);
	id container = [[_keySpecifier containerSpecifier] objectsByEvaluatingSpecifier];
	NSString *key = [_keySpecifier key];
	NSUInteger i;

	if (container == nil || key == nil) {
		_scriptErrorNumber = 1;
		_scriptErrorString = [@"NSDeleteCommand: the receiver has no container to delete from" copy];
		return nil;
	}
	for (i = 0; i < [receivers count]; i++) {
		[[container mutableArrayValueForKey:key] removeObject:[receivers objectAtIndex:i]];
	}
	return nil;
}
@end

@implementation NSCloneCommand
FN_KEY_SPECIFIER(NSCloneCommand)

- (id)performDefaultImplementation
{
	NSArray *receivers = fn_receivers(self);
	NSMutableArray *copies = [NSMutableArray arrayWithCapacity:[receivers count]];
	NSUInteger i;

	for (i = 0; i < [receivers count]; i++) {
		id copy = [[receivers objectAtIndex:i] copy];

		if (copy != nil) {
			[copies addObject:copy];
			[copy release];
		}
	}
	return copies;
}
@end

@implementation NSMoveCommand
FN_KEY_SPECIFIER(NSMoveCommand)

- (id)performDefaultImplementation
{
	_scriptErrorNumber = 1;
	_scriptErrorString = [@"NSMoveCommand: moving an object needs a document model this library does not have" copy];
	return nil;
}
@end

@implementation NSCountCommand

- (id)performDefaultImplementation
{
	return [NSNumber numberWithUnsignedInteger:[fn_receivers(self) count]];
}
@end

@implementation NSExistsCommand

- (id)performDefaultImplementation
{
	return [NSNumber numberWithBool:[fn_receivers(self) count] > 0];
}
@end

@implementation NSGetCommand

- (id)performDefaultImplementation
{
	NSArray *receivers = fn_receivers(self);

	return [receivers count] == 1 ? [receivers objectAtIndex:0] : receivers;
}
@end

@implementation NSCreateCommand

- (NSScriptClassDescription *)createClassDescription { return _createClassDescription; }
- (NSDictionary *)resolvedKeyDictionary { return _resolvedKeyDictionary; }

/* THE CLASS COMES FROM THE DIRECT PARAMETER, which is the class name a script names. The properties are the evaluated
 * arguments; the new object is inserted through the receiver specifier when one was given. */
- (id)performDefaultImplementation
{
	NSString *className = [self directParameter];
	Class cls = [className isKindOfClass:[NSString class]] ? NSClassFromString(className) : Nil;
	id object;

	if (cls == Nil) {
		_scriptErrorNumber = 1;
		_scriptErrorString = [@"NSCreateCommand: the direct parameter does not name a class" copy];
		return nil;
	}
	_createClassDescription = [NSScriptClassDescription classDescriptionForClass:cls];
	_resolvedKeyDictionary = [[self evaluatedArguments] copy];
	object = [[cls alloc] init];
	[object setValuesForKeysWithDictionary:_resolvedKeyDictionary];
	if (_receiversSpecifier != nil) {
		id container = [[_receiversSpecifier containerSpecifier] objectsByEvaluatingSpecifier];
		NSString *key = [_receiversSpecifier key];

		if (container != nil && key != nil) {
			[[container mutableArrayValueForKey:key] addObject:object];
		}
	}
	return [object autorelease];
}
@end

@implementation NSCloseCommand

- (NSSaveOptions)saveOptions
{
	id value = [_arguments objectForKey:@"SaveOptions"];

	return value != nil ? (NSSaveOptions)[value unsignedIntegerValue] : NSSaveOptionsAsk;
}

- (id)performDefaultImplementation
{
	/* CLOSING A DOCUMENT IS THE APPLICATION'S BUSINESS; the standard command's default is to report what it was asked
	 * to do, which is the only thing this library can know. */
	return [NSNumber numberWithUnsignedInteger:[self saveOptions]];
}
@end

@implementation NSQuitCommand

- (NSSaveOptions)saveOptions
{
	id value = [_arguments objectForKey:@"SaveOptions"];

	return value != nil ? (NSSaveOptions)[value unsignedIntegerValue] : NSSaveOptionsAsk;
}

- (id)performDefaultImplementation
{
	return [NSNumber numberWithUnsignedInteger:[self saveOptions]];
}
@end

/* ---- DESCRIPTIONS AND THE REGISTRY ----------------------------------------------------------------------------- */

@implementation NSScriptCommandDescription

- (instancetype)initWithSuiteName:(NSString *)suiteName
		       commandName:(NSString *)commandName
			dictionary:(NSDictionary *)commandDeclaration
{
	self = [super init];
	if (self != nil) {
		[self fnAdoptSuiteName:suiteName commandName:commandName declaration:commandDeclaration];
	}
	return self;
}

/* THE DESCRIPTION'S CODER PAIR: the three strings it is made of, written and read back through the designated door so
 * the declaration's own checks (a suite name, a command name) hold for a decoded one too. */
/* A DESIGNATED INITIALIZER MAY NOT CHAIN TO ANOTHER ONE ON SELF, so the storage is a plain method both doors call -
 * the house's own idiom (NSAppleScript's -fnAdoptSource: states it the same way). */
- (void)fnAdoptSuiteName:(NSString *)suiteName
	     commandName:(NSString *)commandName
	      declaration:(NSDictionary *)declaration
{
	_suiteName = [suiteName copy];
	_commandName = [commandName copy];
	_declaration = [declaration copy];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	NSString *suiteName = [coder decodeObjectForKey:@"NSSuiteName"];
	NSString *commandName = [coder decodeObjectForKey:@"NSCommandName"];
	NSDictionary *declaration = [coder decodeObjectForKey:@"NSCommandDeclaration"];

	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (suiteName == nil || commandName == nil) {
		[self release];
		return nil;
	}
	[self fnAdoptSuiteName:suiteName commandName:commandName declaration:declaration];
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_suiteName forKey:@"NSSuiteName"];
	[coder encodeObject:_commandName forKey:@"NSCommandName"];
	[coder encodeObject:_declaration forKey:@"NSCommandDeclaration"];
}

- (void)dealloc
{
	[_suiteName release];
	[_commandName release];
	[_declaration release];
	[super dealloc];
}

- (NSString *)suiteName { return _suiteName; }
- (NSString *)commandName { return _commandName; }
- (NSString *)commandClassName
{
	id value = [_declaration objectForKey:@"CommandClass"];

	return [value isKindOfClass:[NSString class]] ? value : _commandName;
}
- (FourCharCode)appleEventClassCode
{
	NSString *text = [_declaration objectForKey:@"AppleEventClassCode"];

	return [text isKindOfClass:[NSString class]] ? (FourCharCode)([text length] >= 4 ? 1 : 0) : 0;
}
- (FourCharCode)appleEventCode
{
	NSString *text = [_declaration objectForKey:@"AppleEventCode"];

	return [text isKindOfClass:[NSString class]] ? (FourCharCode)1 : 0;
}
- (FourCharCode)appleEventCodeForReturnType
{
	NSString *text = [_declaration objectForKey:@"AppleEventCodeForReturnType"];

	return [text isKindOfClass:[NSString class]] ? (FourCharCode)1 : 0;
}
- (NSArray *)argumentNames
{
	NSDictionary *arguments = [_declaration objectForKey:@"Arguments"];

	return [arguments isKindOfClass:[NSDictionary class]] ? [arguments allKeys] : [NSArray array];
}
- (NSString *)typeForArgumentWithName:(NSString *)argumentName
{
	NSDictionary *arguments = [_declaration objectForKey:@"Arguments"];
	NSDictionary *entry = [arguments objectForKey:argumentName];

	return [entry objectForKey:@"Type"];
}
- (FourCharCode)appleEventCodeForArgumentWithName:(NSString *)argumentName
{
	NSDictionary *arguments = [_declaration objectForKey:@"Arguments"];
	NSDictionary *entry = [arguments objectForKey:argumentName];

	return [entry objectForKey:@"AppleEventCode"] != nil ? (FourCharCode)1 : 0;
}
- (BOOL)isOptionalArgumentWithName:(NSString *)argumentName
{
	NSDictionary *arguments = [_declaration objectForKey:@"Arguments"];
	NSDictionary *entry = [arguments objectForKey:argumentName];

	return [[entry objectForKey:@"Optional"] boolValue];
}
- (NSString *)returnType
{
	id value = [_declaration objectForKey:@"ReturnType"];

	return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSScriptCommand *)createCommandInstance
{
	return [self createCommandInstanceWithZone:NULL];
}

- (NSScriptCommand *)createCommandInstanceWithZone:(NSZone *)zone
{
	Class cls = NSClassFromString([self commandClassName]);

	if (cls == Nil || ![cls isSubclassOfClass:[NSScriptCommand class]]) {
		return nil;
	}
	return [[[cls allocWithZone:zone] initWithCommandDescription:self] autorelease];
}

@end

static NSScriptSuiteRegistry *fn_script_suite_registry = nil;

@implementation NSScriptSuiteRegistry

+ (NSScriptSuiteRegistry *)sharedScriptSuiteRegistry
{
	if (fn_script_suite_registry == nil) {
		fn_script_suite_registry = [[NSScriptSuiteRegistry alloc] init];
	}
	return fn_script_suite_registry;
}

+ (void)setSharedScriptSuiteRegistry:(NSScriptSuiteRegistry *)registry
{
	[registry retain];
	[fn_script_suite_registry release];
	fn_script_suite_registry = registry;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_classDescriptions = [[NSMutableDictionary alloc] init];
		_commandDescriptions = [[NSMutableDictionary alloc] init];
		_suites = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_classDescriptions release];
	[_commandDescriptions release];
	[_suites release];
	[super dealloc];
}

- (NSArray *)suiteNames { return [_suites allKeys]; }

- (NSString *)suiteForAppleEventCode:(FourCharCode)code
{
	NSEnumerator *keys = [_suites keyEnumerator];
	NSString *key;

	while ((key = [keys nextObject]) != nil) {
		NSDictionary *suite = [_suites objectForKey:key];
		id value = [suite objectForKey:@"AppleEventCode"];

		if (value != nil && (FourCharCode)[value unsignedIntegerValue] == code) {
			return key;
		}
	}
	return nil;
}

- (NSArray *)classDescriptionsInSuite:(NSString *)suiteName
{
	NSDictionary *suite = [_suites objectForKey:suiteName];

	return [suite objectForKey:@"ClassDescriptions"];
}

- (NSArray *)commandDescriptionsInSuite:(NSString *)suiteName
{
	NSDictionary *suite = [_suites objectForKey:suiteName];

	return [suite objectForKey:@"CommandDescriptions"];
}

- (NSScriptClassDescription *)classDescriptionWithAppleEventCode:(FourCharCode)code
{
	NSEnumerator *values = [_classDescriptions objectEnumerator];
	NSScriptClassDescription *description;

	while ((description = [values nextObject]) != nil) {
		if ([description appleEventCode] == code) {
			return description;
		}
	}
	return nil;
}

- (NSScriptCommandDescription *)commandDescriptionWithAppleEventClass:(FourCharCode)eventClass
						      andAppleEventCode:(FourCharCode)eventCode
{
	NSEnumerator *values = [_commandDescriptions objectEnumerator];
	NSScriptCommandDescription *description;

	while ((description = [values nextObject]) != nil) {
		if ([description appleEventClassCode] == eventClass && [description appleEventCode] == eventCode) {
			return description;
		}
	}
	return nil;
}

- (void)registerClassDescription:(NSScriptClassDescription *)description
{
	if (description == nil) {
		return;
	}
	[_classDescriptions setObject:description forKey:[description className]];
	[NSClassDescription registerClassDescription:description
					    forClass:NSClassFromString([description className])];
}

- (void)registerCommandDescription:(NSScriptCommandDescription *)description
{
	if (description == nil) {
		return;
	}
	[_commandDescriptions setObject:description forKey:[description commandName]];
}

- (void)loadSuitesFromBundle:(id)bundle
{
	(void)bundle;		/* no .scriptSuite resources are shipped with this library */
}

/* A SUITE DICTIONARY IS THE .scriptSuite SHAPE: ClassDescriptions and CommandDescriptions are name -> declaration. */
- (void)loadSuiteWithDictionary:(NSDictionary *)suiteDeclaration fromBundle:(id)bundle
{
	NSString *suiteName = [suiteDeclaration objectForKey:@"SuiteName"];
	NSDictionary *classes;
	NSDictionary *commands;
	NSEnumerator *keys;
	NSString *name;

	(void)bundle;
	if (![suiteName isKindOfClass:[NSString class]]) {
		return;
	}
	classes = [suiteDeclaration objectForKey:@"ClassDescriptions"];
	commands = [suiteDeclaration objectForKey:@"CommandDescriptions"];
	keys = [classes keyEnumerator];
	while ((name = [keys nextObject]) != nil) {
		NSScriptClassDescription *description =
			[[NSScriptClassDescription alloc] initWithSuiteName:suiteName
								 className:name
								dictionary:[classes objectForKey:name]];

		[self registerClassDescription:description];
		[description release];
	}
	keys = [commands keyEnumerator];
	while ((name = [keys nextObject]) != nil) {
		NSScriptCommandDescription *description =
			[[NSScriptCommandDescription alloc] initWithSuiteName:suiteName
								 commandName:name
								  dictionary:[commands objectForKey:name]];

		[self registerCommandDescription:description];
		[description release];
	}
	[_suites setObject:suiteDeclaration forKey:suiteName];
}

- (FourCharCode)appleEventCodeForSuite:(NSString *)suiteName
{
	NSDictionary *suite = [_suites objectForKey:suiteName];
	id value = [suite objectForKey:@"AppleEventCode"];

	return [value isKindOfClass:[NSNumber class]] ? (FourCharCode)[value unsignedLongValue] : 0;
}

- (id)aeteResource:(NSString *)name
{
	(void)name;
	return nil;		/* the aete resource is an AppleEvents artifact, and this library has no transport */
}

- (id)bundleForSuite:(NSString *)suiteName
{
	(void)suiteName;
	return nil;
}

@end
