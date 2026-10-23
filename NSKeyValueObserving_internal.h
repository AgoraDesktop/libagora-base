/*
 * NSKeyValueObserving_internal.h — the seam between KVC's writers and KVO's automatic notification.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **WHY THIS IS NOT IN THE PUBLIC HEADER.** `-setValue:forKey:` is KVC's door and the notification is KVO's; the two
 * live in different files, and KVC must know whether the setter it is about to call will ALREADY announce the change.
 * That question is implementation detail — a caller has no business asking it — so it is a C function here rather
 * than a category method on `NSObject` that would become part of every class's surface.
 *
 * **THE ANSWER IS "THIS OBJECT'S CLASS CARRIES AN AUTOMATIC SETTER FOR THIS KEY".** When it does, the setter's wrapper
 * performs the will/did pair and KVC must NOT perform a second one; when it does not (an unsupported setter type, no
 * setter at all, or a dotted key path), KVC is the only announcer and wraps the write itself.
 */
#ifndef FOUNDATION_NSKEYVALUEOBSERVING_INTERNAL_H
#define FOUNDATION_NSKEYVALUEOBSERVING_INTERNAL_H

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

/* YES when `object`'s class answers the setter for `key` with KVO's wrapper — that is, when the write will notify
 * by itself. A simple key only; a dotted key path always answers NO because this tier does not decompose one for
 * automatic notification. */
BOOL fn_kvo_auto_notifies(id object, NSString *key);

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSKEYVALUEOBSERVING_INTERNAL_H */
