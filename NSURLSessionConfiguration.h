/*
 * NSURLSessionConfiguration.h
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * `NSURLSessionConfiguration` — THE OPTIONS A SESSION IS MADE WITH. W3a of FOUNDATION-10.11-PLAN.md: the first of the
 * seven-class URLSession family, and the one the other six take as an argument.
 *
 * IT IS A VALUE OBJECT, AND THAT IS THE WHOLE CONTRACT. Apple's documentation says two things that decide how this is
 * written: a session COPIES the configuration it is given (so the caller may keep editing its own), and the three
 * factory methods differ only in their DEFAULTS. There is no transport in this file — the class stores what a
 * transfer will later read, and its test pins the defaults rather than a transfer.
 *
 * THE THREE FACES, AND WHAT EACH ONE CHANGES:
 *
 *   +defaultSessionConfiguration     the shared cookie store, credential store and URL cache; persistent as those
 *                                    stores are.
 *   +ephemeralSessionConfiguration   PRIVATE, in-memory stores: a cookie store, a credential store and a URL cache
 *                                    with zero disk capacity. Nothing survives the session, which is the promise.
 *   +backgroundSessionConfiguration… an IDENTIFIER and the launch-event switch. THE TRANSFER IS REFUSED ELSEWHERE:
 *                                    this tree has no background-transfer daemon, so the configuration exists (a
 *                                    caller can build and inspect it) and `+[NSURLSession sessionWithConfiguration:]`
 *                                    answers nil by name when it is handed one (§4.1 of the plan).
 *
 * TWO TREE-LOCAL FACTS, STATED RATHER THAN LET TO BE DISCOVERED:
 *
 *   1. `SSLProtocol` IS DECLARED HERE, because this tree has no Security framework and Apple's property type lives in
 *      <Security/SecureTransport.h>. The constants' VALUES are SecureTransport's (10.11's header was read for them),
 *      not invented: a caller comparing against `kTLSProtocol12` reads the same number it would on the Mac. TLS is not
 *      performed by this library (libcurl does it, configured by its own rules), so these properties are recorded
 *      policy that this tree states and does not apply — and the header says so rather than implying a handshake.
 *   2. `connectionProxyDictionary` and `HTTPAdditionalHeaders` DEFAULT TO AN EMPTY DICTIONARY, not nil, which is
 *      Apple's documented default and the reason a caller can read them without a nil check. The nil cases are the
 *      stores (a nil cookie store means "no cookies"), which is Apple's meaning for those three properties.
 */

#ifndef FOUNDATION_NSURLSESSIONCONFIGURATION_H
#define FOUNDATION_NSURLSESSIONCONFIGURATION_H

#import <Foundation/NSObject.h>
#import <Foundation/NSURLRequest.h>	/* NSURLRequestCachePolicy and NSURLRequestNetworkServiceType */
#import <Foundation/NSHTTPCookie.h>	/* NSHTTPCookieAcceptPolicy */

@class NSArray;
@class NSDictionary;
@class NSHTTPCookieStorage;
@class NSURLCache;
@class NSURLCredentialStorage;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

/* SECURITY'S `SSLProtocol`, DECLARED HERE FOR WANT OF A SECURITY FRAMEWORK. The enum TAG and the constants' VALUES
 * are SecureTransport's (macOS 10.11's <Security/SecureTransport.h>: 0, 2, 4, 7, 8, 9 and the four legacy spellings
 * 1, 3, 5, 6), so code that compares or archives a value reads the number Apple's header gives it. What this tree
 * does NOT have is the TLS implementation: libcurl performs the handshake with its own configuration, so the two
 * properties below are RECORDED POLICY rather than applied settings. */
typedef NS_ENUM(int, SSLProtocol) {
	kSSLProtocolUnknown = 0,
	kSSLProtocol3 = 2,
	kTLSProtocol1 = 4,
	kTLSProtocol11 = 7,
	kTLSProtocol12 = 8,
	kDTLSProtocol1 = 9,
	kSSLProtocol2 = 1,		/* deprecated on iOS, kept for the numbers' sake */
	kSSLProtocol3Only = 3,
	kTLSProtocol1Only = 5,
	kSSLProtocolAll = 6
};

NS_CLASS_AVAILABLE_MAC(NSURLSESSION_AVAILABLE)
@interface NSURLSessionConfiguration : NSObject <NSCopying>
{
@private
	NSString *_identifier;
	NSURLRequestCachePolicy _requestCachePolicy;
	NSTimeInterval _timeoutIntervalForRequest;
	NSTimeInterval _timeoutIntervalForResource;
	NSURLRequestNetworkServiceType _networkServiceType;
	BOOL _allowsCellularAccess;
	BOOL _discretionary;
	NSString *_sharedContainerIdentifier;
	BOOL _sessionSendsLaunchEvents;
	NSDictionary *_connectionProxyDictionary;
	SSLProtocol _TLSMinimumSupportedProtocol;
	SSLProtocol _TLSMaximumSupportedProtocol;
	BOOL _HTTPShouldUsePipelining;
	BOOL _HTTPShouldSetCookies;
	NSHTTPCookieAcceptPolicy _HTTPCookieAcceptPolicy;
	NSDictionary *_HTTPAdditionalHeaders;
	NSInteger _HTTPMaximumConnectionsPerHost;
	NSHTTPCookieStorage *_HTTPCookieStorage;
	NSURLCredentialStorage *_URLCredentialStorage;
	NSURLCache *_URLCache;
	BOOL _shouldUseExtendedBackgroundIdleMode;
	NSArray *_protocolClasses;
}

/* THE THREE FACES. `default` and `ephemeral` differ exactly where the header above says; `background` adds the
 * identifier and is otherwise `default`'s shape. */
+ (NSURLSessionConfiguration *)defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration;
+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier NS_AVAILABLE_MAC(10_10);

/* The deprecated spelling, kept because the 10.11 reference declares it and a ported caller may name it. */
+ (NSURLSessionConfiguration *)backgroundSessionConfiguration:(NSString *)identifier
	NS_DEPRECATED_MAC(NSURLSESSION_AVAILABLE, 10_10, "use +backgroundSessionConfigurationWithIdentifier:");

/* READONLY: a configuration's identifier is fixed by the factory that made it (nil for the other two). */
@property (nullable, readonly, copy) NSString *identifier;

@property (readonly) NSURLRequestCachePolicy requestCachePolicy;
@property (readonly) NSTimeInterval timeoutIntervalForRequest;
@property (readonly) NSTimeInterval timeoutIntervalForResource;
@property (readonly) NSURLRequestNetworkServiceType networkServiceType;
@property (readonly) BOOL allowsCellularAccess;
@property (readonly, getter=isDiscretionary) BOOL discretionary NS_AVAILABLE_MAC(10_10);
@property (nullable, readonly, copy) NSString *sharedContainerIdentifier NS_AVAILABLE_MAC(10_10);
@property (readonly) BOOL sessionSendsLaunchEvents;
@property (nullable, readonly, copy) NSDictionary *connectionProxyDictionary;
@property (readonly) SSLProtocol TLSMinimumSupportedProtocol;
@property (readonly) SSLProtocol TLSMaximumSupportedProtocol;
@property (readonly) BOOL HTTPShouldUsePipelining;
@property (readonly) BOOL HTTPShouldSetCookies;
@property (readonly) NSHTTPCookieAcceptPolicy HTTPCookieAcceptPolicy;
@property (nullable, readonly, copy) NSDictionary *HTTPAdditionalHeaders;
@property (readonly) NSInteger HTTPMaximumConnectionsPerHost;
/* NIL IS MEANINGFUL ON THESE THREE: no cookies, no credential store, no caching. It is not the same as "the default
 * one", which is why they are nullable rather than assumed. */
@property (nullable, readonly, retain) NSHTTPCookieStorage *HTTPCookieStorage;
@property (nullable, readonly, retain) NSURLCredentialStorage *URLCredentialStorage;
@property (nullable, readonly, retain) NSURLCache *URLCache;
@property (readonly) BOOL shouldUseExtendedBackgroundIdleMode NS_AVAILABLE_MAC(10_11);
/* "An optional array of Class objects which subclass NSURLProtocol", consulted before the process-wide registry. */
@property (nullable, readonly, copy) NSArray *protocolClasses;

/* THE SETTERS. Declared as methods rather than as readwrite properties, which is this tree's shape for a class whose
 * accessors have bodies worth reading: the copy semantics are the contract (a mutable dictionary handed in is copied,
 * so a later edit by the caller does not reach the session). */
- (void)setRequestCachePolicy:(NSURLRequestCachePolicy)requestCachePolicy;
- (void)setTimeoutIntervalForRequest:(NSTimeInterval)timeoutIntervalForRequest;
- (void)setTimeoutIntervalForResource:(NSTimeInterval)timeoutIntervalForResource;
- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)networkServiceType;
- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess;
- (void)setDiscretionary:(BOOL)discretionary NS_AVAILABLE_MAC(10_10);
- (void)setSharedContainerIdentifier:(nullable NSString *)sharedContainerIdentifier NS_AVAILABLE_MAC(10_10);
- (void)setSessionSendsLaunchEvents:(BOOL)sessionSendsLaunchEvents;
- (void)setConnectionProxyDictionary:(nullable NSDictionary *)connectionProxyDictionary;
- (void)setTLSMinimumSupportedProtocol:(SSLProtocol)TLSMinimumSupportedProtocol;
- (void)setTLSMaximumSupportedProtocol:(SSLProtocol)TLSMaximumSupportedProtocol;
- (void)setHTTPShouldUsePipelining:(BOOL)HTTPShouldUsePipelining;
- (void)setHTTPShouldSetCookies:(BOOL)HTTPShouldSetCookies;
- (void)setHTTPCookieAcceptPolicy:(NSHTTPCookieAcceptPolicy)HTTPCookieAcceptPolicy;
- (void)setHTTPAdditionalHeaders:(nullable NSDictionary *)HTTPAdditionalHeaders;
- (void)setHTTPMaximumConnectionsPerHost:(NSInteger)HTTPMaximumConnectionsPerHost;
- (void)setHTTPCookieStorage:(nullable NSHTTPCookieStorage *)HTTPCookieStorage;
- (void)setURLCredentialStorage:(nullable NSURLCredentialStorage *)URLCredentialStorage;
- (void)setURLCache:(nullable NSURLCache *)URLCache;
- (void)setShouldUseExtendedBackgroundIdleMode:(BOOL)shouldUseExtendedBackgroundIdleMode NS_AVAILABLE_MAC(10_11);
- (void)setProtocolClasses:(nullable NSArray *)protocolClasses;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSURLSESSIONCONFIGURATION_H */
