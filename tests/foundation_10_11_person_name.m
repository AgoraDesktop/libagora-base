/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_person_name.m — THE POLICY IS THE CLASS, SO THE POLICY IS WHAT IS MEASURED.
 *
 * FOUNDATION-10.11-PLAN.md §4.14 says there is no CLDR here: one written table of languages puts the family name first
 * and every other language gets given-name-first. A probe that only rendered "Ada Lovelace" would pass while saying
 * nothing, so this one pins the parts a caller can observe: the four styles and which components each writes, the
 * absence rule (no padding, an empty string is absent), the ORDER under four language codes, the phonetic fallback, the
 * annotated string's boundaries, and the two refusals.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static void checkString(NSString *got, NSString *want, const char *what)
{
	int ok = (got == want) || [got isEqualToString:want];

	if (ok) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s (got \"%s\", wanted \"%s\")\n", what,
	        (got == nil) ? "(nil)" : [got UTF8String], (want == nil) ? "(nil)" : [want UTF8String]);
}

/* The language the ORDER tests run under. `+currentLocale` reads LC_ALL, then LANG, afresh on every call, so setting
 * the variable is the whole of the locale override — no cache to invalidate. */
static void useLanguage(const char *identifier)
{
	setenv("LC_ALL", identifier, 1);
}

/* "key@location:length|…" — the annotated string's runs, in order, so one assertion covers the boundaries, the order
 * and the fact that the separators are marked. */
static NSString *runList(NSAttributedString *text)
{
	NSMutableString *out = [[NSMutableString alloc] init];
	NSUInteger i = 0, n = [text length];

	while (i < n) {
		NSRange effective = NSMakeRange(0, 0);
		NSString *value = [text attribute:NSPersonNameComponentKey atIndex:i effectiveRange:&effective];

		if (effective.length == 0) {
			[out appendString:@"BROKEN"];
			break;
		}
		if ([out length] > 0) { [out appendString:@"|"]; }
		[out appendFormat:@"%@@%lu:%lu", value, (unsigned long)effective.location,
		 (unsigned long)effective.length];
		i = NSMaxRange(effective);
	}
	return out;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSPersonNameComponents *name = [[[NSPersonNameComponents alloc] init] autorelease];
	NSPersonNameComponents *partial = [[[NSPersonNameComponents alloc] init] autorelease];
	NSPersonNameComponents *spoken = [[[NSPersonNameComponents alloc] init] autorelease];
	NSPersonNameComponents *voiced = [[[NSPersonNameComponents alloc] init] autorelease];
	NSPersonNameComponents *empty = [[[NSPersonNameComponents alloc] init] autorelease];
	NSPersonNameComponentsFormatter *formatter = [[[NSPersonNameComponentsFormatter alloc] init] autorelease];
	NSAttributedString *annotated;

	useLanguage("en_US.UTF-8");

	[name setNamePrefix:@"Dr."];
	[name setGivenName:@"Ada"];
	[name setMiddleName:@"Augusta"];
	[name setFamilyName:@"Lovelace"];
	[name setNameSuffix:@"Jr."];

	[partial setGivenName:@"Ada"];
	[partial setFamilyName:@"Lovelace"];

	/* THE STYLES CHOOSE WHICH COMPONENTS, and Default and Long write the same ones. */
	checkString([formatter stringFromPersonNameComponents:name], @"Dr. Ada Augusta Lovelace Jr.",
	            "default style writes every formal component");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleLong];
	checkString([formatter stringFromPersonNameComponents:name], @"Dr. Ada Augusta Lovelace Jr.",
	            "long style is the same set of components");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleMedium];
	checkString([formatter stringFromPersonNameComponents:name], @"Ada Lovelace",
	            "medium style is given + family, with no honorific, middle name or suffix");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleShort];
	checkString([formatter stringFromPersonNameComponents:name], @"Ada", "short style is the given name");
	checkString([formatter stringFromPersonNameComponents:partial], @"Ada", "and stays the given name");
	checkString([formatter stringFromPersonNameComponents:empty], @"", "an empty name writes the empty string");
	checkString([formatter stringFromPersonNameComponents:nil], @"", "and nil writes the empty string");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleDefault];
	checkString([formatter stringFromPersonNameComponents:partial], @"Ada Lovelace",
	            "the absence rule: no padding where a middle name is not present");

	/* AN EMPTY STRING IS ABSENT, which is the same rule NSPersonNameComponents states with nil. */
	[partial setMiddleName:@""];
	checkString([formatter stringFromPersonNameComponents:partial], @"Ada Lovelace",
	            "an empty component is not a component");
	[partial setMiddleName:nil];

	/* SHORT'S LADDER: given, else family, else nickname. */
	{
		NSPersonNameComponents *familyOnly = [[[NSPersonNameComponents alloc] init] autorelease];
		NSPersonNameComponents *nicknameOnly = [[[NSPersonNameComponents alloc] init] autorelease];

		[familyOnly setFamilyName:@"Lovelace"];
		[nicknameOnly setNickname:@"Ada"];
		[formatter setStyle:NSPersonNameComponentsFormatterStyleShort];
		checkString([formatter stringFromPersonNameComponents:familyOnly], @"Lovelace",
		            "short falls back to the family name");
		checkString([formatter stringFromPersonNameComponents:nicknameOnly], @"Ada",
		            "and then to the nickname");
		[formatter setStyle:NSPersonNameComponentsFormatterStyleDefault];
		checkString([formatter stringFromPersonNameComponents:nicknameOnly], @"",
		            "but a nickname is not part of a formal name");
	}

	/* THE ORDER TABLE (§4.14): five languages family-first, everything else given-first, and the honorific and suffix
	 * keep their places in both. */
	useLanguage("ja_JP.UTF-8");
	checkString([formatter stringFromPersonNameComponents:name], @"Dr. Lovelace Ada Augusta Jr.",
	            "ja puts the family name first and keeps the honorific first");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleMedium];
	checkString([formatter stringFromPersonNameComponents:name], @"Lovelace Ada", "medium follows the same order");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleShort];
	checkString([formatter stringFromPersonNameComponents:name], @"Ada",
	            "short is one component, so the order cannot change it");
	[formatter setStyle:NSPersonNameComponentsFormatterStyleDefault];

	useLanguage("zh_Hans_CN");
	checkString([formatter stringFromPersonNameComponents:name], @"Dr. Lovelace Ada Augusta Jr.",
	            "a script subtag does not stop the language subtag deciding the order");
	useLanguage("vi_VN");
	checkString([formatter stringFromPersonNameComponents:name], @"Dr. Lovelace Ada Augusta Jr.", "vi as well");
	useLanguage("de_DE");
	checkString([formatter stringFromPersonNameComponents:name], @"Dr. Ada Augusta Lovelace Jr.",
	            "and a language outside the table takes the documented default");
	useLanguage("en_US.UTF-8");

	/* THE PHONETIC REPRESENTATION, and its total fallback. */
	[voiced setGivenName:@"えいだ"];
	[voiced setFamilyName:@"らぶれす"];
	[spoken setGivenName:@"Ada"];
	[spoken setFamilyName:@"Lovelace"];
	[spoken setPhoneticRepresentation:voiced];
	[formatter setPhonetic:YES];
	check([formatter isPhonetic], "the switch reads back");
	checkString([formatter stringFromPersonNameComponents:spoken], @"えいだ らぶれす",
	            "phonetic renders the representation");
	[formatter setPhonetic:NO];
	checkString([formatter stringFromPersonNameComponents:spoken], @"Ada Lovelace",
	            "and the same object renders its own components when the switch is off");

	{
		NSPersonNameComponents *hollow = [[[NSPersonNameComponents alloc] init] autorelease];
		NSPersonNameComponents *holder = [[[NSPersonNameComponents alloc] init] autorelease];

		[holder setGivenName:@"Ada"];
		[holder setFamilyName:@"Lovelace"];
		[holder setPhoneticRepresentation:hollow];
		[formatter setPhonetic:YES];
		checkString([formatter stringFromPersonNameComponents:holder], @"Ada Lovelace",
		            "an empty phonetic representation falls back to the components, not to nothing");
		[formatter setPhonetic:NO];
	}

	/* THE ONE-SHOT FORM agrees with the instance form, and its options bit is the phonetic switch. */
	checkString([NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:spoken
	                                                                              style:NSPersonNameComponentsFormatterStyleMedium
	                                                                            options:0],
	            @"Ada Lovelace", "the class method renders");
	checkString([NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:spoken
	                                                                              style:NSPersonNameComponentsFormatterStyleMedium
	                                                                            options:NSPersonNameComponentsFormatterPhonetic],
	            @"えいだ らぶれす", "and honours the phonetic option");

	/* THE ANNOTATED FORM PUBLISHES THE BOUNDARIES IT USED, separators included, and covers every character. */
	annotated = [formatter annotatedStringFromPersonNameComponents:partial];
	checkString([annotated string], @"Ada Lovelace", "the annotated string is the same text");
	checkString(runList(annotated),
	            @"NSPersonNameComponentGivenName@0:3|NSPersonNameComponentDelimiter@3:1|"
	            @"NSPersonNameComponentFamilyName@4:8",
	            "with a keyed run per component and a marked separator");
	{
		NSUInteger covered = 0;
		NSUInteger i = 0;
		while (i < [annotated length]) {
			NSRange effective = NSMakeRange(0, 0);
			(void)[annotated attribute:NSPersonNameComponentKey atIndex:i effectiveRange:&effective];
			covered += effective.length;
			i = NSMaxRange(effective);
		}
		check(covered == [annotated length], "and every character is inside one run");
	}
	check([[[formatter annotatedStringFromPersonNameComponents:nil] string] isEqualToString:@""],
	      "nil annotates to the empty string");
	useLanguage("ja_JP.UTF-8");
	annotated = [formatter annotatedStringFromPersonNameComponents:partial];
	checkString(runList(annotated),
	            @"NSPersonNameComponentFamilyName@0:8|NSPersonNameComponentDelimiter@8:1|"
	            @"NSPersonNameComponentGivenName@9:3",
	            "and the runs follow the order the table chose");
	useLanguage("en_US.UTF-8");

	/* THE TWO REFUSALS. An unimplemented style is refused BY NAME, and the parsing door says NO. */
	{
		BOOL raised = NO;
		@try {
			[formatter setStyle:(NSPersonNameComponentsFormatterStyle)4];	/* Abbreviated: 10.12 */
		} @catch (NSException *e) {
			raised = [[e name] isEqualToString:NSInvalidArgumentException] &&
			         [[e reason] rangeOfString:@"style 4"].location != NSNotFound;
		}
		check(raised, "an unimplemented style is refused, naming the value");
		check([formatter style] == NSPersonNameComponentsFormatterStyleDefault,
		      "and the style it had is unchanged");
		raised = NO;
		@try {
			(void)[NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:name
			                                                                        style:(NSPersonNameComponentsFormatterStyle)4
			                                                                      options:0];
		} @catch (NSException *e) {
			raised = [[e reason] rangeOfString:@"style 4"].location != NSNotFound;
		}
		check(raised, "and the one-shot form refuses the same value the same way");

		{
			id object = @"not cleared";
			NSString *error = @"not cleared";
			BOOL ok = [formatter getObjectValue:&object forString:@"Ada Lovelace" errorDescription:&error];
			check(ok == NO, "getObjectValue:forString:errorDescription: answers NO");
			check(object == nil, "leaves the object nil");
			check(error == nil, "and invents no error description");
			ok = [formatter getObjectValue:NULL forString:@"" errorDescription:NULL];
			check(ok == NO, "and tolerates NULL out-parameters");
		}
	}

	/* NSFORMATTER'S CONTRACT: the formatting door works, and anything that is not a name is not formattable. */
	checkString([formatter stringForObjectValue:name], @"Dr. Ada Augusta Lovelace Jr.",
	            "-stringForObjectValue: renders a components object");
	check([formatter stringForObjectValue:@"Ada"] == nil, "and answers nil for anything else");
	checkString([formatter editingStringForObjectValue:name], @"Dr. Ada Augusta Lovelace Jr.",
	            "the inherited editing string follows the override");

	printf("foundation_10_11_person_name: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
