/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptKeyValueCoding.h — the keyed and indexed doors a scriptable object answers (W7), in Apple's own file.
 *
 * These are not KVC: they are the scripting protocol's manipulation doors, which a class overrides to expose a
 * collection (`-valueAtIndex:inPropertyWithKey:` and the insert/remove/replace forms) or a named element. The names and
 * shapes are Apple's; the implementations are NSObject's defaults in NSScriptObjectSpecifiers.m.
 *
 * `NSOperationNotSupportedForKeyException` is declared here because Apple files it under this header's exception names:
 * a KVC implementor raises it to refuse a manipulation deliberately. Nothing in this library raises it.
 */
#ifndef FOUNDATION_NSSCRIPTKEYVALUECODING_H
#define FOUNDATION_NSSCRIPTKEYVALUECODING_H

#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>	/* NSExceptionName, for the name this header declares */

@class NSString;

NS_ASSUME_NONNULL_BEGIN

/* THE EXCEPTION NAME APPLE DECLARES HERE (it lived in NSException.h while this header did not exist). */
extern NSExceptionName const NSOperationNotSupportedForKeyException;

@interface NSObject (NSScriptKeyValueCoding)

- (nullable id)valueAtIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key;
- (void)insertValue:(id)value atIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key;
- (void)removeValueAtIndex:(NSUInteger)index fromPropertyWithKey:(NSString *)key;
- (void)replaceValueAtIndex:(NSUInteger)index inPropertyWithKey:(NSString *)key withValue:(id)value;
- (void)insertValue:(id)value inPropertyWithKey:(NSString *)key;

- (nullable id)valueWithName:(NSString *)name inPropertyWithKey:(NSString *)key;
- (nullable id)valueWithUniqueID:(id)uniqueID inPropertyWithKey:(NSString *)key;

- (nullable id)coerceValue:(id)value forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTKEYVALUECODING_H */
