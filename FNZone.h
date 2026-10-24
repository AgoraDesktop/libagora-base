/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * FNZone.h — the seam between NSZone and the object allocator.
 *
 * NSZone.m owns the registry; NSObject.m and the object-allocation functions in
 * NSObject.m are the only callers. Nothing here is part of the public API.
 */

#ifndef FOUNDATION_FNZONE_H
#define FOUNDATION_FNZONE_H

#include <Foundation/NSZone.h>

/* RECORD (OR REPLACE) THE ZONE A POINTER BELONGS TO. `zone` may be NULL, which means the default zone; the
 * default zone is not stored (every unrecorded object is in it already), so this is a no-op for it. */
void fn_zone_assign_pointer(void *pointer, NSZone * _Nullable zone);

/* FORGET A POINTER. Cheap when no custom-zone allocation has ever been made, which is the common case. */
void fn_zone_forget_pointer(void *pointer);

#endif /* FOUNDATION_FNZONE_H */
