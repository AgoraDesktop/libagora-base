/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSURLComponents.m — the three things the public class adds to the internal parser.
 *
 * The percent codec is written here rather than shared with `FNURLComponents.m`, and the duplication is deliberate:
 * the internal codec is `static` and belongs to a parser that runs on every URL this library builds, while this one
 * runs only when a caller reads or writes `queryItems`. Sharing them would mean making an internal helper public to
 * two classes, which is a wider seam than the six lines it saves — and it would put a `query`-specific allow-list in
 * the path of every scheme, host and path this tree encodes.
 *
 * **THE QUERY COMPONENT'S UNRESERVED SET IS RFC 3986'S.** A name or value is encoded with everything except
 * unreserved characters left alone; `&`, `=` and `+` MUST be encoded inside a pair or the pair would not survive the
 * round trip. `+` is NOT a space here: Apple's `queryItems` is percent-decoding only, and turning `+` into a space
 * would make `?a=1+1` read back as `1 1`, which is form encoding and not this class.
 */

#import <Foundation/NSURLComponents.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

#include <stdlib.h>
#include <string.h>

/* RETAINED RAW, RENDERED DECODED: `_user` and friends hold the percent-encoded octets, so an encoded setter is a copy
 * and a decoded one is an encode. The ivars are the superclass's and protected, which is why this class can be a
 * declaration over the parser rather than a copy of it. */

static int fn_uc_hex(int c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static NSString *fn_uc_decode(NSString *text)
{
	const char *bytes = [text UTF8String];
	size_t length, i, out = 0;
	char *buffer;
	NSString *decoded;

	if (bytes == NULL) {
		return text;
	}
	length = strlen(bytes);
	buffer = malloc(length + 1);
	if (buffer == NULL) {
		return text;
	}
	for (i = 0; i < length; i++) {
		if (bytes[i] == '%' && i + 2 < length && fn_uc_hex(bytes[i + 1]) >= 0 && fn_uc_hex(bytes[i + 2]) >= 0) {
			buffer[out++] = (char)((fn_uc_hex(bytes[i + 1]) << 4) | fn_uc_hex(bytes[i + 2]));
			i += 2;
		} else {
			buffer[out++] = bytes[i];
		}
	}
	buffer[out] = '\0';
	decoded = [NSString stringWithUTF8String:buffer];
	free(buffer);
	/* INVALID UTF-8 IS RETURNED AS GIVEN rather than dropped: a caller who handed in a broken escape asked for the
	 * text back, and a nil here would silently empty a query. */
	return decoded != nil ? decoded : text;
}

static int fn_uc_isUnreserved(int c)
{
	if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
		return 1;
	}
	return c == '-' || c == '.' || c == '_' || c == '~';
}

static NSString *fn_uc_encode_keeping(NSString *text, const char *keep)
{
	const char *bytes = [text UTF8String];
	size_t length, i, out = 0;
	char *buffer;
	NSString *encoded;
	static const char *hex = "0123456789ABCDEF";

	if (bytes == NULL) {
		return text;
	}
	length = strlen(bytes);
	buffer = malloc(length * 3 + 1);
	if (buffer == NULL) {
		return text;
	}
	for (i = 0; i < length; i++) {
		int c = (unsigned char)bytes[i];

		if (fn_uc_isUnreserved(c) || (keep != NULL && strchr(keep, c) != NULL)) {
			buffer[out++] = (char)c;
		} else {
			buffer[out++] = '%';
			buffer[out++] = hex[(c >> 4) & 0xF];
			buffer[out++] = hex[c & 0xF];
		}
	}
	buffer[out] = '\0';
	encoded = [NSString stringWithUTF8String:buffer];
	free(buffer);
	return encoded != nil ? encoded : text;
}

/* **A COMPONENT'S OWN ALLOW-LIST, BECAUSE ENCODING EVERYTHING IS NOT ENCODING CORRECTLY.** The first version encoded
 * `/` inside a path, so `-setPath:@"/a b"` rendered `%2Fa%20b` — a single path segment with a literal slash in its
 * name. RFC 3986 gives each component its own set: a path keeps `/`, `:` and `@`; a query also keeps `?`; a user or
 * password keeps the sub-delims; a fragment keeps `/` and `?`. The pair encoder below keeps NOTHING beyond unreserved,
 * because `&` and `=` inside a query ITEM would not survive the split it is about to be joined for. */
static NSString *fn_uc_encode(NSString *text)
{
	return fn_uc_encode_keeping(text, NULL);
}

static NSString *fn_uc_encodePath(NSString *text)
{
	return fn_uc_encode_keeping(text, "/:@!$&'()*+,;=");
}

static NSString *fn_uc_encodeUser(NSString *text)
{
	return fn_uc_encode_keeping(text, "!$&'()*+,;=");
}

static NSString *fn_uc_encodeQuery(NSString *text)
{
	return fn_uc_encode_keeping(text, "/?:@!$&'()*+,;=");
}

static NSString *fn_uc_encodeFragment(NSString *text)
{
	return fn_uc_encode_keeping(text, "/?:@!$&'()*+,;=");
}

@implementation NSURLComponents

- (instancetype)init
{
	/* EVERY COMPONENT UNDEFINED, which is `[super init]` with nothing set: the inheritance is the point. */
	return [super init];
}

- (nullable NSURL *)URLRelativeToURL:(nullable NSURL *)baseURL
{
	NSString *text = [self string];

	if (text == nil) {
		return nil;
	}
	return [NSURL URLWithString:text relativeToURL:baseURL];
}

/* **THE PLAIN SETTERS ENCODE, AND THE INTERNAL TYPE'S DID NOT.** `FNURLComponents` receives raw text from the parser
 * and renders it decoded, so its `-setPath:` stores what it is given — correct for a parser, wrong for Apple's
 * contract, where `-setPath:@"/a b"` is a path with a space in it and `-string` must show `%20`. Every plain setter
 * therefore encodes here; the `percentEncoded…` setters below store as given, which is the pair a caller needs to
 * choose between. */
- (void)setUser:(nullable NSString *)user { [super setUser:fn_uc_encodeUser(user)]; }
- (void)setPassword:(nullable NSString *)password { [super setPassword:fn_uc_encodeUser(password)]; }
- (void)setPath:(nullable NSString *)path { [super setPath:fn_uc_encodePath(path)]; }
- (void)setQuery:(nullable NSString *)query { [super setQuery:fn_uc_encodeQuery(query)]; }
- (void)setFragment:(nullable NSString *)fragment { [super setFragment:fn_uc_encodeFragment(fragment)]; }

- (void)setPercentEncodedUser:(nullable NSString *)user
{
	NSString *old = _user;
	_user = [user copy];
	[old release];
}

- (void)setPercentEncodedPassword:(nullable NSString *)password
{
	NSString *old = _password;
	_password = [password copy];
	[old release];
}

- (void)setPercentEncodedHost:(nullable NSString *)host
{
	NSString *old = _host;
	_host = [host copy];
	[old release];
}

- (void)setPercentEncodedPath:(nullable NSString *)path
{
	NSString *old = _path;
	_path = [path copy];
	[old release];
}

- (void)setPercentEncodedQuery:(nullable NSString *)query
{
	NSString *old = _query;
	_query = [query copy];
	[old release];
}

- (void)setPercentEncodedFragment:(nullable NSString *)fragment
{
	NSString *old = _fragment;
	_fragment = [fragment copy];
	[old release];
}

/* THE QUERY, SPLIT. An empty query (`?`) has no pairs; a trailing `&` or a `=` with nothing after it is the empty
 * string, which is a real value and not a missing one. */
- (nullable NSArray<NSURLQueryItem *> *)queryItems
{
	NSMutableArray *items;
	NSString *raw = [self percentEncodedQuery];
	NSArray *parts;
	NSUInteger i;

	if (raw == nil) {
		return nil;
	}
	items = [NSMutableArray array];
	parts = [raw componentsSeparatedByString:@"&"];
	for (i = 0; i < [parts count]; i++) {
		NSString *part = [parts objectAtIndex:i];
		NSRange equals;
		NSString *name;
		NSString *value = nil;

		if ([part length] == 0) {
			continue;
		}
		equals = [part rangeOfString:@"="];
		if (equals.location == NSNotFound) {
			name = part;
		} else {
			name = [part substringToIndex:equals.location];
			value = [part substringFromIndex:equals.location + 1];
		}
		[items addObject:[NSURLQueryItem queryItemWithName:fn_uc_decode(name)
		                                            value:(value == nil ? nil : fn_uc_decode(value))]];
	}
	return [NSArray arrayWithArray:items];
}

- (void)setQueryItems:(nullable NSArray<NSURLQueryItem *> *)items
{
	NSMutableString *joined;
	NSUInteger i;

	if (items == nil) {
		[self setPercentEncodedQuery:nil];
		return;
	}
	joined = [NSMutableString string];
	for (i = 0; i < [items count]; i++) {
		NSURLQueryItem *item = [items objectAtIndex:i];

		if (i > 0) {
			[joined appendString:@"&"];
		}
		[joined appendString:fn_uc_encode([item name])];
		if ([item value] != nil) {
			[joined appendString:@"="];
			[joined appendString:fn_uc_encode([item value])];
		}
	}
	[self setPercentEncodedQuery:joined];
}

@end
