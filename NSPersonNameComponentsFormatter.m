/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPersonNameComponentsFormatter.m — one table, four styles, and a renderer that publishes its own boundaries.
 *
 * WHERE THE LOCALE LIVES. In one static table and one function: FNFamilyNameFirst reads the LANGUAGE subtag of
 * `[NSLocale currentLocale]` and answers whether this tree has a written order for it. That is the whole of the
 * locale handling, it is FOUNDATION-10.11-PLAN.md §4.14, and it is stated in the header so a caller can see what the
 * promise is rather than infer it from output. There is no CLDR here and nothing that pretends to be one.
 *
 * WHY THE RENDERER BUILDS RUNS. `-annotatedStringFromPersonNameComponents:` is not a second renderer: it is the same
 * renderer recording the range of every component and of every separator as it appends, so the annotated form cannot
 * disagree with the plain one about what the text is. One pass, two results.
 */

#import <Foundation/NSPersonNameComponentsFormatter.h>
#import <Foundation/NSPersonNameComponents.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSException.h>

#include <ctype.h>
#include <string.h>

/* THE KEYS ARE THE ATTRIBUTE'S VALUES, and the value is the key's own name: Apple documents the constant names and not
 * their strings, and a string this library chose cannot collide with a caller's own attribute. */
NSString *const NSPersonNameComponentKey = @"NSPersonNameComponent";
NSString *const NSPersonNameComponentPrefix = @"NSPersonNameComponentPrefix";
NSString *const NSPersonNameComponentGivenName = @"NSPersonNameComponentGivenName";
NSString *const NSPersonNameComponentMiddleName = @"NSPersonNameComponentMiddleName";
NSString *const NSPersonNameComponentFamilyName = @"NSPersonNameComponentFamilyName";
NSString *const NSPersonNameComponentSuffix = @"NSPersonNameComponentSuffix";
NSString *const NSPersonNameComponentNickname = @"NSPersonNameComponentNickname";
NSString *const NSPersonNameComponentDelimiter = @"NSPersonNameComponentDelimiter";

/* ---- the written table (§4.14) --------------------------------------------------------------------- */

/* THE FIVE LANGUAGES WHOSE USUAL FULL NAME PUTS THE FAMILY NAME FIRST. Anything else is given-name-first, which is the
 * default the header names. Sorted, so a reader can see it is a list and not an accident. */
static const char *const FNFamilyFirstLanguages[] = { "hu", "ja", "ko", "vi", "zh" };

static BOOL FNFamilyNameFirst(void)
{
	NSString *code = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
	const char *utf8;
	size_t k;

	if (code == nil) {
		return NO;
	}
	utf8 = [code UTF8String];
	if (utf8 == NULL) {
		return NO;
	}
	for (k = 0; k < sizeof(FNFamilyFirstLanguages) / sizeof(FNFamilyFirstLanguages[0]); k++) {
		const char *want = FNFamilyFirstLanguages[k];
		/* A SUBTAG MATCH, NOT A PREFIX MATCH: `hu` must not claim `hun`, so the third character has to be the end of
		 * the code or a separator. The language code `-objectForKey:` returns is already the first subtag, and the
		 * separators are accepted because a caller may pass an identifier-shaped value straight through. */
		if (tolower((unsigned char)utf8[0]) == want[0] && tolower((unsigned char)utf8[1]) == want[1] &&
		    (utf8[2] == '\0' || utf8[2] == '-' || utf8[2] == '_')) {
			return YES;
		}
	}
	return NO;
}

static BOOL FNStyleIsImplemented(NSInteger style)
{
	return style >= (NSInteger)NSPersonNameComponentsFormatterStyleDefault &&
	       style <= (NSInteger)NSPersonNameComponentsFormatterStyleLong;
}

/* ---- one renderer, two results --------------------------------------------------------------------- */

/* ONE PIECE AND ITS SEPARATOR. An absent or empty component writes NOTHING — no padding, no doubled space — which is the
 * same rule NSPersonNameComponents states with nil instead of a blank string. The separator's range is recorded because
 * a caller laying a name out needs to know where the boundaries are, and the space is a boundary too. */
static void FNAppendPiece(NSMutableString *out, NSMutableArray *runs, NSString *text, NSString *key)
{
	NSRange range;

	if (text == nil || [text length] == 0) {
		return;
	}
	if ([out length] > 0) {
		range = NSMakeRange([out length], 1);
		[out appendString:@" "];
		[runs addObject:[NSArray arrayWithObjects:NSPersonNameComponentDelimiter,
		                                          [NSValue valueWithRange:range], nil]];
	}
	range = NSMakeRange([out length], [text length]);
	[out appendString:text];
	[runs addObject:[NSArray arrayWithObjects:key, [NSValue valueWithRange:range], nil]];
}

static void FNRender(NSPersonNameComponents *name, NSPersonNameComponentsFormatterStyle style,
                     NSMutableString *out, NSMutableArray *runs)
{
	BOOL familyFirst;

	if (name == nil) {
		return;
	}
	familyFirst = FNFamilyNameFirst();

	switch (style) {
	case NSPersonNameComponentsFormatterStyleShort: {
		/* THE LADDER IS DOCUMENTED, not discovered: a given name, else the family name, else the nickname. */
		NSString *text = [name givenName];
		NSString *key = NSPersonNameComponentGivenName;

		if (text == nil || [text length] == 0) {
			text = [name familyName];
			key = NSPersonNameComponentFamilyName;
		}
		if (text == nil || [text length] == 0) {
			text = [name nickname];
			key = NSPersonNameComponentNickname;
		}
		FNAppendPiece(out, runs, text, key);
		return;
	}
	case NSPersonNameComponentsFormatterStyleMedium:
		if (familyFirst) {
			FNAppendPiece(out, runs, [name familyName], NSPersonNameComponentFamilyName);
			FNAppendPiece(out, runs, [name givenName], NSPersonNameComponentGivenName);
		} else {
			FNAppendPiece(out, runs, [name givenName], NSPersonNameComponentGivenName);
			FNAppendPiece(out, runs, [name familyName], NSPersonNameComponentFamilyName);
		}
		return;
	case NSPersonNameComponentsFormatterStyleLong:
	case NSPersonNameComponentsFormatterStyleDefault:
		/* THE HONORIFIC AND THE GENERATIONAL SUFFIX KEEP THEIR PLACES in both orders; only the name group moves. */
		FNAppendPiece(out, runs, [name namePrefix], NSPersonNameComponentPrefix);
		if (familyFirst) {
			FNAppendPiece(out, runs, [name familyName], NSPersonNameComponentFamilyName);
			FNAppendPiece(out, runs, [name givenName], NSPersonNameComponentGivenName);
			FNAppendPiece(out, runs, [name middleName], NSPersonNameComponentMiddleName);
		} else {
			FNAppendPiece(out, runs, [name givenName], NSPersonNameComponentGivenName);
			FNAppendPiece(out, runs, [name middleName], NSPersonNameComponentMiddleName);
			FNAppendPiece(out, runs, [name familyName], NSPersonNameComponentFamilyName);
		}
		FNAppendPiece(out, runs, [name nameSuffix], NSPersonNameComponentSuffix);
		return;
	}
	/* UNREACHABLE THROUGH THE PUBLIC DOORS (`-setStyle:` refuses first), and it refuses here too rather than writing a
	 * name in an order nobody asked for — the rule §4.14 states. */
	[NSException raise:NSInvalidArgumentException
	            format:@"NSPersonNameComponentsFormatter: style %ld is not implemented; this class knows Default, "
	                   @"Short, Medium and Long", (long)style];
}

/* THE PHONETIC SWAP, WITH A TOTAL FALLBACK: the representation is used when `phonetic` asks for it AND it carries at
 * least one component; otherwise the object's own components are written. A phonetic object that sets nothing would
 * otherwise render an empty string, which is the kind of silent nothing this library refuses. */
static NSPersonNameComponents *FNPhoneticOrSelf(NSPersonNameComponents *name, BOOL phonetic)
{
	NSPersonNameComponents *spoken;

	if (!phonetic) {
		return name;
	}
	spoken = [name phoneticRepresentation];
	if (spoken == nil) {
		return name;
	}
	if ([spoken namePrefix] == nil && [spoken givenName] == nil && [spoken middleName] == nil &&
	    [spoken familyName] == nil && [spoken nameSuffix] == nil && [spoken nickname] == nil) {
		return name;
	}
	return spoken;
}

@implementation NSPersonNameComponentsFormatter

- (id)init
{
	self = [super init];
	if (self != nil) {
		_style = NSPersonNameComponentsFormatterStyleDefault;
		_phonetic = NO;
	}
	return self;
}

- (NSPersonNameComponentsFormatterStyle)style { return _style; }

- (void)setStyle:(NSPersonNameComponentsFormatterStyle)style
{
	/* REFUSED AT THE SETTER, so `-style` never answers a value this class cannot render and the refusal names the value
	 * the caller asked for. */
	if (!FNStyleIsImplemented((NSInteger)style)) {
		[NSException raise:NSInvalidArgumentException
		            format:@"NSPersonNameComponentsFormatter: style %ld is not implemented; this class knows Default, "
		                   @"Short, Medium and Long (Abbreviated is 10.12)", (long)style];
	}
	_style = style;
}

- (BOOL)isPhonetic { return _phonetic; }
- (void)setPhonetic:(BOOL)phonetic { _phonetic = (phonetic ? YES : NO); }

- (NSString *)stringFromPersonNameComponents:(NSPersonNameComponents *)components
{
	NSMutableString *out = [[NSMutableString alloc] init];
	NSMutableArray *runs = [[NSMutableArray alloc] init];

	FNRender(FNPhoneticOrSelf(components, _phonetic), _style, out, runs);
	[runs release];
	return [out autorelease];
}

- (NSAttributedString *)annotatedStringFromPersonNameComponents:(NSPersonNameComponents *)components
{
	NSMutableString *out = [[NSMutableString alloc] init];
	NSMutableArray *runs = [[NSMutableArray alloc] init];
	NSMutableAttributedString *text;
	NSUInteger k;

	FNRender(FNPhoneticOrSelf(components, _phonetic), _style, out, runs);
	text = [[NSMutableAttributedString alloc] initWithString:out];
	for (k = 0; k < [runs count]; k++) {
		NSArray *run = [runs objectAtIndex:k];
		[text addAttribute:NSPersonNameComponentKey
		             value:[run objectAtIndex:0]
		             range:[[run objectAtIndex:1] rangeValue]];
	}
	[out release];
	[runs release];
	return [text autorelease];
}

+ (NSString *)localizedStringFromPersonNameComponents:(NSPersonNameComponents *)components
                                                style:(NSPersonNameComponentsFormatterStyle)nameFormatStyle
                                              options:(NSPersonNameComponentsFormatterOptions)nameOptions
{
	NSPersonNameComponentsFormatter *formatter = [[[self alloc] init] autorelease];

	/* THE SETTER IS THE REFUSAL, so the one-shot form and an instance cannot disagree about which styles exist. */
	[formatter setStyle:nameFormatStyle];
	[formatter setPhonetic:((nameOptions & NSPersonNameComponentsFormatterPhonetic) != 0)];
	return [formatter stringFromPersonNameComponents:components];
}

/* NSFORMATTER'S TWO DOORS, ANSWERED FOR THIS CLASS. The base RAISES from both; a formatter that can render a name
 * overrides the formatting half, and the parsing half is a NO because this class does not read names back. */
- (NSString *)stringForObjectValue:(id)object
{
	if (![object isKindOfClass:[NSPersonNameComponents class]]) {
		return nil;
	}
	return [self stringFromPersonNameComponents:object];
}

- (BOOL)getObjectValue:(out id *)object forString:(NSString *)string errorDescription:(out NSString **)error
{
	(void)string;
	if (object != NULL) { *object = nil; }
	if (error != NULL) { *error = nil; }
	return NO;
}

@end
