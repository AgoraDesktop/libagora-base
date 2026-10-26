/*
 * NSURLSessionConfiguration.m
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The design is in the header; what is here is the defaults table, the three factories, the accessors and the copy.
 *
 * THE DEFAULTS ARE THE CONTRACT, so they are written once in `-init` and the factories adjust only what Apple says
 * they adjust. A caller can therefore read any property without a nil surprise: the object-valued defaults are the
 * SHARED stores (or an empty dictionary), not nil, and nil is reserved for the caller's deliberate "no store".
 *
 * THE COPY IS WHAT MAKES THE SESSION'S COPY SAFE. `NSURLSession` copies the configuration it is handed, so this method
 * must deep-copy every mutable value a caller could still be holding — the two dictionaries and the protocol array —
 * and retain the stores, which are shared objects by design. The identifier is copied because it is a string.
 */

#import <Foundation/NSURLSessionConfiguration.h>
#import <Foundation/NSHTTPCookieStorage.h>
#import <Foundation/NSURLCredentialStorage.h>
#import <Foundation/NSURLCache.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

/* APPLE'S DOCUMENTED VALUES, in one place so the test can name them without a magic number and the defaults cannot
 * drift between the three factories. The 60-second request timeout and the 7-day resource timeout are Apple's
 * published defaults; 6 connections per host is the published default too. */
#define FN_REQUEST_TIMEOUT		60.0
#define FN_RESOURCE_TIMEOUT		(7.0 * 24.0 * 60.0 * 60.0)
#define FN_MAX_CONNECTIONS_PER_HOST	6

/* THE EPHEMERAL CACHE'S MEMORY BUDGET: the shared cache's memory capacity with NO disk half. Apple's promise for an
 * ephemeral configuration is "no persistent storage", not "no memory", so the cache an ephemeral session reads is a
 * real one — it just cannot survive the process. */
#define FN_EPHEMERAL_CACHE_MEMORY	(4 * 1024 * 1024)

@implementation NSURLSessionConfiguration

/* ---- the three faces ---------------------------------------------------- */

- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* THE SCALARS AND THE OBJECTS THAT HAVE A NON-NIL DEFAULT. */
	_requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
	_timeoutIntervalForRequest = FN_REQUEST_TIMEOUT;
	_timeoutIntervalForResource = FN_RESOURCE_TIMEOUT;
	_networkServiceType = NSURLNetworkServiceTypeDefault;
	_allowsCellularAccess = YES;
	_discretionary = NO;
	_sessionSendsLaunchEvents = YES;
	_connectionProxyDictionary = [[NSDictionary alloc] init];
	_TLSMinimumSupportedProtocol = kSSLProtocolUnknown;	/* "use the default", per SecureTransport */
	_TLSMaximumSupportedProtocol = kSSLProtocolUnknown;
	_HTTPShouldUsePipelining = NO;
	_HTTPShouldSetCookies = YES;
	_HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
	_HTTPAdditionalHeaders = [[NSDictionary alloc] init];
	_HTTPMaximumConnectionsPerHost = FN_MAX_CONNECTIONS_PER_HOST;
	_HTTPCookieStorage = [[NSHTTPCookieStorage sharedHTTPCookieStorage] retain];
	_URLCredentialStorage = [[NSURLCredentialStorage sharedCredentialStorage] retain];
	_URLCache = [[NSURLCache sharedURLCache] retain];
	_shouldUseExtendedBackgroundIdleMode = NO;
	_protocolClasses = nil;
	return self;
}

+ (NSURLSessionConfiguration *)defaultSessionConfiguration
{
	/* AUTORELEASED, as a factory not named alloc/new/copy must be under manual ownership. */
	return [[[self alloc] init] autorelease];
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration
{
	NSURLSessionConfiguration *configuration = [[self alloc] init];
	NSURLCache *cache;

	if (configuration == nil) {
		return nil;
	}
	/* PRIVATE STORES, AND THE POINT IS THAT THEY ARE REACHABLE BY NOBODY ELSE. A private cookie store and a private
	 * credential store are the class's own in-memory instances (both classes support `-init` here); the cache keeps
	 * its memory half and loses its disk half. */
	[configuration->_HTTPCookieStorage release];
	configuration->_HTTPCookieStorage = [[NSHTTPCookieStorage alloc] init];
	[configuration->_URLCredentialStorage release];
	configuration->_URLCredentialStorage = [[NSURLCredentialStorage alloc] init];
	cache = [[NSURLCache alloc] initWithMemoryCapacity:FN_EPHEMERAL_CACHE_MEMORY
					      diskCapacity:0
					      directoryURL:nil];
	[configuration->_URLCache release];
	configuration->_URLCache = cache;
	return [configuration autorelease];
}

+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier
{
	NSURLSessionConfiguration *configuration = [[self alloc] init];

	if (configuration == nil) {
		return nil;
	}
	configuration->_identifier = [identifier copy];
	return [configuration autorelease];
}

+ (NSURLSessionConfiguration *)backgroundSessionConfiguration:(NSString *)identifier
{
	/* THE DEPRECATED SPELLING IS THE SAME CONFIGURATION, not a second shape. */
	return [self backgroundSessionConfigurationWithIdentifier:identifier];
}

- (void)dealloc
{
	[_identifier release];
	[_sharedContainerIdentifier release];
	[_connectionProxyDictionary release];
	[_HTTPAdditionalHeaders release];
	[_HTTPCookieStorage release];
	[_URLCredentialStorage release];
	[_URLCache release];
	[_protocolClasses release];
	[super dealloc];
}

/* ---- the copy ----------------------------------------------------------- */

- (id)copyWithZone:(NSZone *)zone
{
	NSURLSessionConfiguration *copy = [[[self class] allocWithZone:zone] init];

	if (copy == nil) {
		return nil;
	}
	copy->_identifier = [_identifier copy];
	copy->_requestCachePolicy = _requestCachePolicy;
	copy->_timeoutIntervalForRequest = _timeoutIntervalForRequest;
	copy->_timeoutIntervalForResource = _timeoutIntervalForResource;
	copy->_networkServiceType = _networkServiceType;
	copy->_allowsCellularAccess = _allowsCellularAccess;
	copy->_discretionary = _discretionary;
	copy->_sharedContainerIdentifier = [_sharedContainerIdentifier copy];
	copy->_sessionSendsLaunchEvents = _sessionSendsLaunchEvents;
	copy->_connectionProxyDictionary = [_connectionProxyDictionary copy];
	copy->_TLSMinimumSupportedProtocol = _TLSMinimumSupportedProtocol;
	copy->_TLSMaximumSupportedProtocol = _TLSMaximumSupportedProtocol;
	copy->_HTTPShouldUsePipelining = _HTTPShouldUsePipelining;
	copy->_HTTPShouldSetCookies = _HTTPShouldSetCookies;
	copy->_HTTPCookieAcceptPolicy = _HTTPCookieAcceptPolicy;
	copy->_HTTPAdditionalHeaders = [_HTTPAdditionalHeaders copy];
	copy->_HTTPMaximumConnectionsPerHost = _HTTPMaximumConnectionsPerHost;
	/* THE STORES ARE SHARED OBJECTS: retained, not copied, which is Apple's `retain` on all three properties. */
	[copy->_HTTPCookieStorage release];
	copy->_HTTPCookieStorage = [_HTTPCookieStorage retain];
	[copy->_URLCredentialStorage release];
	copy->_URLCredentialStorage = [_URLCredentialStorage retain];
	[copy->_URLCache release];
	copy->_URLCache = [_URLCache retain];
	copy->_shouldUseExtendedBackgroundIdleMode = _shouldUseExtendedBackgroundIdleMode;
	copy->_protocolClasses = [_protocolClasses copy];
	return copy;
}

/* ---- the getters -------------------------------------------------------- */

- (NSString *)identifier { return _identifier; }
- (NSURLRequestCachePolicy)requestCachePolicy { return _requestCachePolicy; }
- (NSTimeInterval)timeoutIntervalForRequest { return _timeoutIntervalForRequest; }
- (NSTimeInterval)timeoutIntervalForResource { return _timeoutIntervalForResource; }
- (NSURLRequestNetworkServiceType)networkServiceType { return _networkServiceType; }
- (BOOL)allowsCellularAccess { return _allowsCellularAccess; }
- (BOOL)isDiscretionary { return _discretionary; }
- (NSString *)sharedContainerIdentifier { return _sharedContainerIdentifier; }
- (BOOL)sessionSendsLaunchEvents { return _sessionSendsLaunchEvents; }
- (NSDictionary *)connectionProxyDictionary { return _connectionProxyDictionary; }
- (SSLProtocol)TLSMinimumSupportedProtocol { return _TLSMinimumSupportedProtocol; }
- (SSLProtocol)TLSMaximumSupportedProtocol { return _TLSMaximumSupportedProtocol; }
- (BOOL)HTTPShouldUsePipelining { return _HTTPShouldUsePipelining; }
- (BOOL)HTTPShouldSetCookies { return _HTTPShouldSetCookies; }
- (NSHTTPCookieAcceptPolicy)HTTPCookieAcceptPolicy { return _HTTPCookieAcceptPolicy; }
- (NSDictionary *)HTTPAdditionalHeaders { return _HTTPAdditionalHeaders; }
- (NSInteger)HTTPMaximumConnectionsPerHost { return _HTTPMaximumConnectionsPerHost; }
- (NSHTTPCookieStorage *)HTTPCookieStorage { return _HTTPCookieStorage; }
- (NSURLCredentialStorage *)URLCredentialStorage { return _URLCredentialStorage; }
- (NSURLCache *)URLCache { return _URLCache; }
- (BOOL)shouldUseExtendedBackgroundIdleMode { return _shouldUseExtendedBackgroundIdleMode; }
- (NSArray *)protocolClasses { return _protocolClasses; }

/* ---- the setters -------------------------------------------------------- */

- (void)setRequestCachePolicy:(NSURLRequestCachePolicy)requestCachePolicy { _requestCachePolicy = requestCachePolicy; }
- (void)setTimeoutIntervalForRequest:(NSTimeInterval)seconds { _timeoutIntervalForRequest = seconds; }
- (void)setTimeoutIntervalForResource:(NSTimeInterval)seconds { _timeoutIntervalForResource = seconds; }
- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)type { _networkServiceType = type; }
- (void)setAllowsCellularAccess:(BOOL)allows { _allowsCellularAccess = allows; }
- (void)setDiscretionary:(BOOL)discretionary { _discretionary = discretionary; }
- (void)setSessionSendsLaunchEvents:(BOOL)sends { _sessionSendsLaunchEvents = sends; }
- (void)setTLSMinimumSupportedProtocol:(SSLProtocol)protocol { _TLSMinimumSupportedProtocol = protocol; }
- (void)setTLSMaximumSupportedProtocol:(SSLProtocol)protocol { _TLSMaximumSupportedProtocol = protocol; }
- (void)setHTTPShouldUsePipelining:(BOOL)pipelining { _HTTPShouldUsePipelining = pipelining; }
- (void)setHTTPShouldSetCookies:(BOOL)should { _HTTPShouldSetCookies = should; }
- (void)setHTTPCookieAcceptPolicy:(NSHTTPCookieAcceptPolicy)policy { _HTTPCookieAcceptPolicy = policy; }
- (void)setHTTPMaximumConnectionsPerHost:(NSInteger)maximum { _HTTPMaximumConnectionsPerHost = maximum; }
- (void)setShouldUseExtendedBackgroundIdleMode:(BOOL)extended { _shouldUseExtendedBackgroundIdleMode = extended; }

- (void)setSharedContainerIdentifier:(NSString *)identifier
{
	NSString *copied = [identifier copy];

	[_sharedContainerIdentifier release];
	_sharedContainerIdentifier = copied;
}

- (void)setConnectionProxyDictionary:(NSDictionary *)dictionary
{
	NSDictionary *copied = [dictionary copy];

	[_connectionProxyDictionary release];
	_connectionProxyDictionary = copied;
}

- (void)setHTTPAdditionalHeaders:(NSDictionary *)headers
{
	NSDictionary *copied = [headers copy];

	[_HTTPAdditionalHeaders release];
	_HTTPAdditionalHeaders = copied;
}

- (void)setHTTPCookieStorage:(NSHTTPCookieStorage *)storage
{
	[storage retain];
	[_HTTPCookieStorage release];
	_HTTPCookieStorage = storage;
}

- (void)setURLCredentialStorage:(NSURLCredentialStorage *)storage
{
	[storage retain];
	[_URLCredentialStorage release];
	_URLCredentialStorage = storage;
}

- (void)setURLCache:(NSURLCache *)cache
{
	[cache retain];
	[_URLCache release];
	_URLCache = cache;
}

- (void)setProtocolClasses:(NSArray *)classes
{
	NSArray *copied = [classes copy];

	[_protocolClasses release];
	_protocolClasses = copied;
}

@end
