/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#include <objc/runtime.h>

static FourCharCode fn_code_from_string(NSString *text)
{
	const char *bytes;
	FourCharCode code = 0;
	int i;

	if (text == nil) {
		return 0;
	}
	bytes = [text UTF8String];
	for (i = 0; i < 4; i++) {
		code = (code << 8) | (FourCharCode)(unsigned char)(bytes[i] != '\0' ? bytes[i] : ' ');
	}
	return code;
}

static NSDictionary *fn_entry(NSDictionary *declaration, NSString *section, NSString *key)
{
	NSDictionary *group = [declaration objectForKey:section];

	if (![group isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	return [group objectForKey:key];
}

static NSArray *fn_keys_in(NSDictionary *declaration, NSString *section)
{
	NSDictionary *group = [declaration objectForKey:section];

	return [group isKindOfClass:[NSDictionary class]] ? [group allKeys] : [NSArray array];
}

@implementation NSScriptClassDescription

- (instancetype)initWithSuiteName:(NSString *)suiteName
			 className:(NSString *)className
			dictionary:(NSDictionary *)classDeclaration
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_suiteName = [suiteName copy];
	_className = [className copy];
	_declaration = [classDeclaration copy];
	[NSScriptClassDescription registerClassDescription:self forClass:NSClassFromString(className)];
	return self;
}

- (void)dealloc
{
	[_suiteName release];
	[_className release];
	[_declaration release];
	[super dealloc];
}

- (NSString *)suiteName { return _suiteName; }
- (NSString *)className { return _className; }

- (FourCharCode)appleEventCode
{
	NSString *text = [_declaration objectForKey:@"AppleEventCode"];

	if ([text isKindOfClass:[NSString class]]) {
		return fn_code_from_string(text);
	}
	/* THE CLASS CODE IS THE IMPLEMENTATION CLASS'S FIRST FOUR CHARACTERS UPPERCASED, which is the convention a suite
	 * without an explicit code follows. */
	{
		NSString *name = [self implementationClassName];
		NSUInteger length;

		if (name == nil) {
			return 0;
		}
		length = [name length] < 4 ? [name length] : 4;
		return fn_code_from_string([[name substringToIndex:length] uppercaseString]);
	}
}

+ (NSScriptClassDescription *)classDescriptionForClass:(Class)aClass
{
	NSClassDescription *description = [super classDescriptionForClass:aClass];

	return [description isKindOfClass:[NSScriptClassDescription class]]
		? (NSScriptClassDescription *)description : nil;
}

- (NSScriptClassDescription *)superclassDescription
{
	NSString *name = [_declaration objectForKey:@"Superclass"];
	Class superclass = NSClassFromString(_className);
	Class parent;

	if ([name isKindOfClass:[NSString class]]) {
		Class declared = NSClassFromString(name);

		return declared != Nil ? [NSScriptClassDescription classDescriptionForClass:declared] : nil;
	}
	parent = superclass != Nil ? class_getSuperclass(superclass) : Nil;
	if (parent == Nil || parent == [NSObject class]) {
		return nil;
	}
	{
		NSScriptClassDescription *description =
			[[[NSScriptClassDescription alloc] initWithSuiteName:_suiteName
								   className:NSStringFromClass(parent)
								  dictionary:nil] autorelease];

		return description;
	}
}

- (BOOL)hasPropertyForKey:(NSString *)key
{
	return fn_entry(_declaration, @"Attributes", key) != nil ||
	       fn_entry(_declaration, @"ToOneRelationships", key) != nil ||
	       fn_entry(_declaration, @"ToManyRelationships", key) != nil;
}

- (BOOL)hasReadablePropertyForKey:(NSString *)key
{
	return [self hasPropertyForKey:key];
}

- (BOOL)hasWritablePropertyForKey:(NSString *)key
{
	return [self hasPropertyForKey:key] && ![self isReadOnlyKey:key];
}

- (BOOL)isReadOnlyKey:(NSString *)key
{
	NSDictionary *entry = fn_entry(_declaration, @"Attributes", key);

	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToOneRelationships", key);
	}
	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToManyRelationships", key);
	}
	return [[entry objectForKey:@"ReadOnly"] boolValue];
}

- (BOOL)hasOrderedToManyRelationshipForKey:(NSString *)key
{
	NSDictionary *entry = fn_entry(_declaration, @"ToManyRelationships", key);

	return [[entry objectForKey:@"Ordered"] boolValue];
}

- (BOOL)isLocationRequiredToCreateForKey:(NSString *)key
{
	NSDictionary *entry = fn_entry(_declaration, @"ToManyRelationships", key);

	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToOneRelationships", key);
	}
	return [[entry objectForKey:@"LocationRequiredToCreate"] boolValue];
}

- (NSString *)typeForKey:(NSString *)key
{
	NSDictionary *entry = fn_entry(_declaration, @"Attributes", key);

	return [entry objectForKey:@"Type"];
}

- (NSString *)defaultSubcontainerAttributeKey
{
	id value = [_declaration objectForKey:@"DefaultSubcontainerAttribute"];

	return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSString *)implementationClassName
{
	id value = [_declaration objectForKey:@"ImplementationClassName"];

	return [value isKindOfClass:[NSString class]] ? value : _className;
}

- (NSArray *)attributeKeys { return fn_keys_in(_declaration, @"Attributes"); }
- (NSArray *)toOneRelationshipKeys { return fn_keys_in(_declaration, @"ToOneRelationships"); }
- (NSArray *)toManyRelationshipKeys { return fn_keys_in(_declaration, @"ToManyRelationships"); }

- (NSString *)inverseForRelationshipKey:(NSString *)relationshipKey
{
	NSDictionary *entry = fn_entry(_declaration, @"ToOneRelationships", relationshipKey);

	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToManyRelationships", relationshipKey);
	}
	return [entry objectForKey:@"Inverse"];
}

- (NSScriptClassDescription *)classDescriptionForKey:(NSString *)key
{
	NSDictionary *entry = fn_entry(_declaration, @"Attributes", key);

	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToOneRelationships", key);
	}
	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToManyRelationships", key);
	}
	{
		id className = [entry objectForKey:@"Class"];
		Class cls;

		if (![className isKindOfClass:[NSString class]]) {
			return nil;
		}
		cls = NSClassFromString(className);
		return cls != Nil ? [NSScriptClassDescription classDescriptionForClass:cls] : nil;
	}
}

- (FourCharCode)appleEventCodeForKey:(NSString *)key
{
	NSDictionary *entry = fn_entry(_declaration, @"Attributes", key);

	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToOneRelationships", key);
	}
	if (entry == nil) {
		entry = fn_entry(_declaration, @"ToManyRelationships", key);
	}
	return fn_code_from_string([entry objectForKey:@"AppleEventCode"]);
}

- (NSString *)keyWithAppleEventCode:(FourCharCode)code
{
	NSArray *sections = [NSArray arrayWithObjects:@"Attributes", @"ToOneRelationships",
			      @"ToManyRelationships", nil];
	NSUInteger i, j;

	for (i = 0; i < [sections count]; i++) {
		NSArray *keys = fn_keys_in(_declaration, [sections objectAtIndex:i]);

		for (j = 0; j < [keys count]; j++) {
			if ([self appleEventCodeForKey:[keys objectAtIndex:j]] == code) {
				return [keys objectAtIndex:j];
			}
		}
	}
	return nil;
}

- (BOOL)matchesAppleEventCode:(FourCharCode)code
{
	return [self appleEventCode] == code;
}

- (NSString *)selectorForCommand:(NSString *)commandName
{
	NSArray *names = [NSArray arrayWithObjects:commandName,
			  [NSString stringWithFormat:@"%@:", commandName], nil];
	NSUInteger i;

	for (i = 0; i < [names count]; i++) {
		NSString *candidate = [names objectAtIndex:i];

		if (NSSelectorFromString(candidate) != NULL && [NSClassFromString([self implementationClassName])
							       instancesRespondToSelector:NSSelectorFromString(candidate)]) {
			return candidate;
		}
	}
	return nil;
}

- (BOOL)supportsCommand:(NSString *)commandName
{
	return [self selectorForCommand:commandName] != nil;
}

@end

@implementation NSObject (NSScriptClassDescription)

- (FourCharCode)classCode
{
	NSScriptClassDescription *description =
		[NSScriptClassDescription classDescriptionForClass:[self class]];

	return description != nil ? [description appleEventCode] : 0;
}

- (NSString *)className
{
	return NSStringFromClass([self class]);
}

@end
