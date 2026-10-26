/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptCoercionHandler.h — the process-wide coercer registry (W7), in Apple's own file.
 *
 * A coercer is (selector, from-class, to-class): `-coerceValue:toClass:` walks the registrations and answers nil when
 * nothing can perform the conversion. The class is real; the specifier evaluation is its only caller in this tree.
 */
#ifndef FOUNDATION_NSSCRIPTCOERCIONHANDLER_H
#define FOUNDATION_NSSCRIPTCOERCIONHANDLER_H

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTCOERCIONHANDLER_H */
