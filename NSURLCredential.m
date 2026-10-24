/*
 * NSURLCredential.m
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

#import <Foundation/NSURLCredential.h>

@implementation NSURLCredential

/* THE FOUR REFUSALS AND THE TWO ACCESSORS THAT GO WITH THEM. They are one family: an identity credential is a
 * private key plus a certificate chain, and a trust credential is a decision about a server's chain. With no
 * certificate stack there is nothing to store, so a body that returned a plausible object would be the failure mode
 * this header exists to avoid. */
static void fn_credential_refuse(const char *door)
{
	[NSException raise:NSInvalidArgumentException
		    format:@"NSURLCredential -%s: this system has no Security framework, so no identity, "
			   "certificate or trust can be held", door];
}

+ (instancetype)credentialWithIdentity:(void *)identity
			  certificates:(NSArray *)certArray
			   persistence:(NSURLCredentialPersistence)persistence
{
	(void)identity; (void)certArray; (void)persistence;
	fn_credential_refuse("credentialWithIdentity:certificates:persistence:");
	return nil;
}

- (instancetype)initWithIdentity:(void *)identity
		    certificates:(NSArray *)certArray
		     persistence:(NSURLCredentialPersistence)persistence
{
	(void)identity; (void)certArray; (void)persistence;
	fn_credential_refuse("initWithIdentity:certificates:persistence:");
	return nil;
}

+ (instancetype)credentialForTrust:(void *)trust
{
	(void)trust;
	fn_credential_refuse("credentialForTrust:");
	return nil;
}

- (instancetype)initWithTrust:(void *)trust
{
	(void)trust;
	fn_credential_refuse("initWithTrust:");
	return nil;
}

- (void *)identity
{
	fn_credential_refuse("identity");
	return NULL;
}

- (NSArray *)certificates
{
	fn_credential_refuse("certificates");
	return nil;
}

+ (instancetype)credentialWithUser:(NSString *)user
			  password:(NSString *)password
		       persistence:(NSURLCredentialPersistence)persistence
{
	return [[[self alloc] initWithUser:user password:password persistence:persistence] autorelease];
}

- (instancetype)initWithUser:(NSString *)user
		    password:(NSString *)password
		 persistence:(NSURLCredentialPersistence)persistence
{
	if(!(self = [super init])) {
		return nil;
	}
	_user = [user copy];
	_password = [password copy];
	_persistence = persistence;
	return self;
}

- (void)dealloc
{
	[_user release];
	[_password release];
	[super dealloc];
}

- (NSString *)user { return _user; }
- (NSString *)password { return _password; }
- (NSURLCredentialPersistence)persistence { return _persistence; }

/* TRUE WHEN THERE IS A PASSWORD TO OFFER. In v1 every credential this class can build is a password one, so
 * the honest statement is that this answers YES for exactly the credentials that have a password - and the
 * NO case belongs to the identity kind, which is refused, so it is UNREACHABLE HERE RATHER THAN ABSENT. The
 * property is still shipped because it is part of the surface and because a caller asking it is asking the
 * right question. */
- (BOOL)hasPassword { return (_password != nil) ? YES : NO; }

- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }

/* THE PASSWORD IS NEVER PRINTED, and that is a rule rather than a preference: a credential's description
 * turns up in logs, in a debugger, and in an exception message, and a secret that reaches any of those has
 * leaked. The user is shown because it identifies the credential; the secret is replaced by its presence. */
- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ user=%@ password=%@ persistence=%d>", [self class],
			(_user != nil ? _user : @"(none)"),
			(_password != nil ? @"(set)" : @"(none)"),
			(int)_persistence];
}

@end
