/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSExtensionRequestHandling.h — what an extension's principal object implements (10.10), in Apple's own file.
 *
 * The protocol is declared for the SHAPE: an extension's principal class conforms to it and the host sends it
 * `-beginRequestWithExtensionContext:`. Nothing in this system launches such an extension, so the declaration is the
 * whole contract — and a client building an extension bundle compiles against the same name Apple's SDK publishes.
 */
#ifndef FOUNDATION_NSEXTENSIONREQUESTHANDLING_H
#define FOUNDATION_NSEXTENSIONREQUESTHANDLING_H

#import <Foundation/NSObject.h>
#import <Foundation/NSExtensionContext.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NSExtensionRequestHandling <NSObject>
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSEXTENSIONREQUESTHANDLING_H */
