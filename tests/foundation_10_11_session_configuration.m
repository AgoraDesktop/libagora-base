/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_session_configuration.m — THE OPTIONS OBJECT'S DEFAULTS, ITS THREE FACES, AND ITS COPY (10.9/10.10/10.11).
 *
 * `NSURLSessionConfiguration` has no transport, so the measurable contract IS the defaults table, the differences
 * between the three factories, and the copy semantics a session depends on. Each of those is asserted here, including
 * the three cases where NIL is a meaning ("no cookies", "no credential store", "no cache") rather than an absence.
 *
 * The SSLProtocol values are pinned too: they are Security framework facts this tree declares for want of that
 * framework, and a value that drifted would be a compatibility bug no compiler would report.
 */

#import <Foundation/Foundation.h>
/* THE FAMILY IS NOT IN THE UMBRELLA YET (W7 re-admits it), so the class is named by its own header. */
#import <Foundation/NSURLSessionConfiguration.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSURLSessionConfiguration *def = [NSURLSessionConfiguration defaultSessionConfiguration];
	NSURLSessionConfiguration *eph = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSessionConfiguration *bg = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.example.bg"];
	NSURLSessionConfiguration *old = [NSURLSessionConfiguration backgroundSessionConfiguration:@"com.example.old"];

	/* ---- the defaults table (Apple's published values) ---- */
	check(def != nil, "a default configuration is made");
	check([def requestCachePolicy] == NSURLRequestUseProtocolCachePolicy, "cache policy defaults to the protocol policy");
	check([def timeoutIntervalForRequest] == 60.0, "request timeout defaults to 60 seconds");
	check([def timeoutIntervalForResource] == 7.0 * 24.0 * 60.0 * 60.0, "resource timeout defaults to 7 days");
	check([def networkServiceType] == NSURLNetworkServiceTypeDefault, "network service type defaults to default");
	check([def allowsCellularAccess], "cellular access defaults on");
	check(![def isDiscretionary], "discretionary defaults off");
	check([def sessionSendsLaunchEvents], "launch events default on");
	check([def connectionProxyDictionary] != nil && [[def connectionProxyDictionary] count] == 0,
	      "the proxy dictionary defaults to an EMPTY dictionary, not nil");
	check([def TLSMinimumSupportedProtocol] == kSSLProtocolUnknown, "TLS minimum defaults to 'unknown, use default'");
	check([def TLSMaximumSupportedProtocol] == kSSLProtocolUnknown, "TLS maximum defaults to 'unknown, use default'");
	check(![def HTTPShouldUsePipelining], "pipelining defaults off");
	check([def HTTPShouldSetCookies], "setting cookies defaults on");
	check([def HTTPCookieAcceptPolicy] == NSHTTPCookieAcceptPolicyAlways, "cookie acceptance defaults to always");
	check([def HTTPAdditionalHeaders] != nil && [[def HTTPAdditionalHeaders] count] == 0,
	      "additional headers default to an EMPTY dictionary, not nil");
	check([def HTTPMaximumConnectionsPerHost] == 6, "six connections per host is the default");
	check([def HTTPCookieStorage] == [NSHTTPCookieStorage sharedHTTPCookieStorage], "the default cookie storage is the shared one");
	check([def URLCredentialStorage] == [NSURLCredentialStorage sharedCredentialStorage],
	      "the default credential storage is the shared one");
	check([def URLCache] == [NSURLCache sharedURLCache], "the default cache is the shared one");
	check([def identifier] == nil, "a default configuration has no identifier");
	check([def sharedContainerIdentifier] == nil, "and no shared container");
	check([def protocolClasses] == nil, "and no protocol list of its own");
	check(![def shouldUseExtendedBackgroundIdleMode], "extended background idle mode defaults off");

	/* ---- the ephemeral face: PRIVATE, IN-MEMORY STORES ---- */
	check(eph != nil, "an ephemeral configuration is made");
	check([eph HTTPCookieStorage] != nil && [eph HTTPCookieStorage] != [NSHTTPCookieStorage sharedHTTPCookieStorage],
	      "an ephemeral session has a cookie store of its own");
	check([eph URLCredentialStorage] != nil && [eph URLCredentialStorage] != [NSURLCredentialStorage sharedCredentialStorage],
	      "an ephemeral session has a credential store of its own");
	check([eph URLCache] != nil && [eph URLCache] != [NSURLCache sharedURLCache],
	      "an ephemeral session has a cache of its own");
	check([[eph URLCache] diskCapacity] == 0, "and that cache has NO disk capacity");
	check([[eph URLCache] memoryCapacity] > 0, "while keeping a memory capacity");
	check([eph HTTPCookieStorage] != [def HTTPCookieStorage], "the two faces do not share a cookie store");
	check([eph identifier] == nil && [eph timeoutIntervalForRequest] == [def timeoutIntervalForRequest],
	      "ephemeral differs from default only where the stores differ");

	/* ---- the background face: an identifier, everything else default's shape ---- */
	check(bg != nil, "a background configuration is made");
	check([[bg identifier] isEqualToString:@"com.example.bg"], "and carries the identifier it was made with");
	check([bg HTTPCookieStorage] == [def HTTPCookieStorage], "a background configuration uses the shared stores");
	check([[old identifier] isEqualToString:@"com.example.old"], "the deprecated spelling builds the same configuration");

	/* ---- the setters, and copy semantics ---- */
	[def setRequestCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	check([def requestCachePolicy] == NSURLRequestReloadIgnoringLocalCacheData, "the cache policy setter reads back");
	[def setTimeoutIntervalForRequest:12.5];
	[def setTimeoutIntervalForResource:99.0];
	check([def timeoutIntervalForRequest] == 12.5 && [def timeoutIntervalForResource] == 99.0, "both timeouts set and read back");
	[def setAllowsCellularAccess:NO];
	[def setDiscretionary:YES];
	check(![def allowsCellularAccess] && [def isDiscretionary], "the two switches set and read back");
	[def setHTTPMaximumConnectionsPerHost:2];
	[def setHTTPShouldUsePipelining:YES];
	[def setTLSMinimumSupportedProtocol:kTLSProtocol12];
	check([def HTTPMaximumConnectionsPerHost] == 2 && [def HTTPShouldUsePipelining] &&
	      [def TLSMinimumSupportedProtocol] == kTLSProtocol12, "the numeric doors set and read back");
	[def setHTTPCookieStorage:nil];
	check([def HTTPCookieStorage] == nil, "a nil cookie store is accepted and means 'no cookies'");

	{
		NSMutableDictionary *headers = [[[NSMutableDictionary alloc] init] autorelease];
		NSMutableArray *classes = [[[NSMutableArray alloc] init] autorelease];
		NSURLSessionConfiguration *copied;

		[headers setObject:@"agora" forKey:@"X-Probe"];
		[classes addObject:[NSURLProtocol class]];
		[def setHTTPAdditionalHeaders:headers];
		[headers setObject:@"changed" forKey:@"X-Probe"];
		check([[[def HTTPAdditionalHeaders] objectForKey:@"X-Probe"] isEqualToString:@"agora"],
		      "the headers dictionary was COPIED, so a later edit does not reach the configuration");

		[def setProtocolClasses:classes];
		[classes removeAllObjects];
		check([[def protocolClasses] count] == 1, "the protocol list was copied too");

		copied = [[def copy] autorelease];
		check(copied != nil && copied != def, "a configuration copies to a distinct object");
		check([copied requestCachePolicy] == [def requestCachePolicy] &&
		      [copied timeoutIntervalForRequest] == [def timeoutIntervalForRequest] &&
		      [copied HTTPMaximumConnectionsPerHost] == [def HTTPMaximumConnectionsPerHost],
		      "the copy carries every scalar");
		/* An immutable value's copy may BE the value (NSDictionary -copy is a retain), so the fact to check is
		 * equality plus independence-from-the-caller, not a distinct pointer. */
		check([[copied HTTPAdditionalHeaders] isEqual:[def HTTPAdditionalHeaders]],
		      "and the same (copied, immutable) header dictionary");
		[def setRequestCachePolicy:NSURLRequestReturnCacheDataElseLoad];
		check([copied requestCachePolicy] == NSURLRequestReloadIgnoringLocalCacheData,
		      "editing the original after the copy leaves the copy alone");
		[def setHTTPAdditionalHeaders:nil];
		check([copied HTTPAdditionalHeaders] != nil, "clearing the original's headers afterwards leaves the copy's intact");
	}

	/* ---- the SSLProtocol values are SecureTransport's, not invented ---- */
	check(kSSLProtocolUnknown == 0 && kSSLProtocol2 == 1 && kSSLProtocol3 == 2 && kSSLProtocol3Only == 3 &&
	      kTLSProtocol1 == 4 && kTLSProtocol1Only == 5 && kSSLProtocolAll == 6 && kTLSProtocol11 == 7 &&
	      kTLSProtocol12 == 8 && kDTLSProtocol1 == 9, "the SSLProtocol constants carry Apple's numbers");

	printf("foundation_10_11_session_configuration: %d of %d cases passed, %d failed\n",
	       g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
