/*
 * NSURLCredential.h
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * A credential: what a caller offers in answer to a challenge.
 *
 * V1 IS THE PASSWORD KIND AND THE DOORS ARE ALL PRESENT. The identity and trust kinds name a `SecIdentityRef`, a
 * `SecTrustRef` or a certificate chain, and this system has no certificate stack to give any of them a meaning, so
 * those doors EXIST AND REFUSE BY NAME: they raise with the missing subsystem stated. That is the difference
 * between an API surface a caller can compile against and one that silently lacks a name — and it is the plan's
 * declaration tier, which this header now meets.
 *
 * IT IS A VALUE, AND IT KEEPS A SECRET — which is why two of its rules are about not leaking one:
 * `-hasPassword` answers WHETHER there is one without producing it, and `-description` never prints it.
 */

#ifndef _FNX_FOUNDATION_NSURLCREDENTIAL_H
#define _FNX_FOUNDATION_NSURLCREDENTIAL_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * The persistence cases are Apple's names; their values are ours, with `None` at 0 so that an
 * uninitialised or absent choice is the NOT-STORED one rather than the permanent one.
 *
 * THREE CASES, NOT FOUR: `NSURLCredentialPersistenceSynchronizable` is refused with the rest of the
 * synchronisation surface (§48.1) — it exists for iCloud, which this system does not have and this plan has
 * never proposed. A caller who passes that number gets a value this library does not recognise, which is
 * the honest outcome for a name that is deliberately absent.
 */
typedef NS_ENUM(NSUInteger, NSURLCredentialPersistence) {
	NSURLCredentialPersistenceNone = 0,
	NSURLCredentialPersistenceForSession = 1,
	NSURLCredentialPersistencePermanent = 2
};

/* NSCopying, because a credential is handed around and stored; Cocoa's copy door is implemented. */
@interface NSURLCredential : NSObject <NSCopying>
{
	NSString *_user;
	NSString *_password;
	NSURLCredentialPersistence _persistence;
}

+ (instancetype)credentialWithUser:(nullable NSString *)user
			  password:(nullable NSString *)password
		       persistence:(NSURLCredentialPersistence)persistence;

- (instancetype)initWithUser:(nullable NSString *)user
		    password:(nullable NSString *)password
		 persistence:(NSURLCredentialPersistence)persistence;

@property (readonly, copy, nullable) NSString *user;
@property (readonly, copy, nullable) NSString *password;
/* ASK WHETHER A SECRET EXISTS WITHOUT ASKING FOR IT - the property a caller should reach for first. */
@property (readonly) BOOL hasPassword;
@property (readonly) NSURLCredentialPersistence persistence;

/*
 * THE IDENTITY AND TRUST KINDS. Their parameter and answer types are `void *` rather than `SecIdentityRef` /
 * `SecTrustRef` because this library does not ship the Security framework's headers, and inventing a typedef that
 * collides with Apple's would be worse than naming the platform's opaque handle by what it is. Every door raises
 * `NSInvalidArgumentException` naming the absent subsystem; none of them pretends to hold a certificate.
 */
+ (instancetype)credentialWithIdentity:(void *)identity
			  certificates:(nullable NSArray *)certArray
			   persistence:(NSURLCredentialPersistence)persistence;
- (instancetype)initWithIdentity:(void *)identity
		    certificates:(nullable NSArray *)certArray
		     persistence:(NSURLCredentialPersistence)persistence;
+ (instancetype)credentialForTrust:(void *)trust;
- (instancetype)initWithTrust:(void *)trust;
- (nullable void *)identity;
- (nullable NSArray *)certificates;

@end

NS_ASSUME_NONNULL_END

#endif /* _FNX_FOUNDATION_NSURLCREDENTIAL_H */
