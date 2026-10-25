/*
 * NSMachBootstrapServer.h
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * `NSMachBootstrapServer` (§62.54) — Apple's door to the MACH BOOTSTRAP namespace, which does not exist here.
 * What does exist is the shared registry from NSPortNameServer.h, so `-servicePortWithName:` is a registry lookup
 * and `-portForName:` is the inherited one. The substitution is the same one `NSMachPort.h` states: no port
 * rights, no namespace, one process-local table.
 */

#ifndef FOUNDATION_NSMACHBOOTSTRAPSERVER_H
#define FOUNDATION_NSMACHBOOTSTRAPSERVER_H

#import <Foundation/NSPortNameServer.h>

@class NSPort, NSString;

NS_ASSUME_NONNULL_BEGIN

@interface NSMachBootstrapServer : NSPortNameServer

+ (NSMachBootstrapServer *)sharedInstance;

/* Apple's door for asking for a registered service by name; here it is `-portForName:`. */
- (nullable NSPort *)servicePortWithName:(NSString *)name NS_AVAILABLE_MAC(10_5);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSMACHBOOTSTRAPSERVER_H */
