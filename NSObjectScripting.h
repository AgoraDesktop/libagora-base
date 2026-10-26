/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSObjectScripting.h — what a scriptable object answers about its own scripting (W7), in Apple's own file.
 *
 * `-scriptingValueForSpecifier:`, `-scriptingProperties` and the two object-creation doors. Apple's category name is
 * `NSObjectScripting` and this header is its home; NSScriptKeyValueCoding.h has the manipulation doors, which are a
 * different category on the same class.
 */
#ifndef FOUNDATION_NSOBJECTSCRIPTING_H
#define FOUNDATION_NSOBJECTSCRIPTING_H

#import <Foundation/NSObject.h>
#import <Foundation/NSScriptObjectSpecifiers.h>	/* NSScriptObjectSpecifier, the type these doors take */

@class NSString;
@class NSDictionary;

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (NSObjectScripting)

- (nullable id)scriptingValueForSpecifier:(NSScriptObjectSpecifier *)specifier NS_AVAILABLE_MAC(10_5);

@property (nullable, copy) NSDictionary *scriptingProperties;

- (nullable id)copyScriptingValue:(id)value forKey:(NSString *)key withProperties:(nullable NSDictionary *)properties NS_AVAILABLE_MAC(10_5);
- (nullable id)newScriptingObjectOfClass:(Class)objectClass
			  forValueForKey:(NSString *)key
		       withContentsValue:(nullable id)contentsValue
			      properties:(nullable NSDictionary *)properties NS_AVAILABLE_MAC(10_5);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSOBJECTSCRIPTING_H */
