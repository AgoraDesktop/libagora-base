/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * FNCondition.h — the name three files use for NSCondition.
 *
 * §63.170 renamed the condition to `FNCondition` when `NSCondition` (10.5) was cut against a 10.2 baseline. The
 * 10.6 census restored the public class in `NSCondition.h`, and this subclass keeps NSOperation's and NSTask's ivars
 * compiling unchanged: an `FNCondition` IS an `NSCondition`, with the same pthread pair behind it.
 */
#ifndef FOUNDATION_FNCONDITION_H
#define FOUNDATION_FNCONDITION_H

#import <Foundation/NSCondition.h>

NS_ASSUME_NONNULL_BEGIN

@interface FNCondition : NSCondition
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_FNCONDITION_H */
