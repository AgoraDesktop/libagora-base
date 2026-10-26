/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPersonNameComponentsFormatter (10.11) — a name, written the way a person says it.
 *
 * **THE ONLY LOCALE-SPECIFIC FACT IN A NAME'S RENDERING IS THE ORDER OF THE FAMILY AND GIVEN NAMES, AND THIS TREE HAS
 * NO CLDR.** Apple's formatter asks a locale database; this one asks a written table, because the alternative —
 * guessing per locale and calling it a database — is the invented fact COCOA-10.11-SURFACE-PLAN.md forbids. The
 * policy is FOUNDATION-10.11-PLAN.md §4.14 and it is restated here because a caller reads this header, not the plan:
 *
 *   - the order is decided by ONE fact, the LANGUAGE SUBTAG of `[NSLocale currentLocale]`;
 *   - `ja`, `ko`, `vi`, `zh`, `hu` put the family name first, and EVERY OTHER LANGUAGE puts the given name first;
 *   - `namePrefix` and `nameSuffix` are not part of that decision: an honorific precedes a name in both orders and a
 *     generational suffix follows it, so only {given, middle, family} moves;
 *   - the STYLE chooses which components are written, never their order: `Short` is the given name — the family name
 *     when there is none, the nickname when there is neither — `Medium` is given + family, and `Long`/`Default` are
 *     every formal component the object carries. A nickname is not part of a formal name, which is why only `Short`
 *     reaches it.
 *
 * **A COMPONENT IS WRITTEN ONLY WHEN IT IS PRESENT.** Nothing is padded, so a name with no middle name is
 * `Ada Lovelace`, not `Ada  Lovelace`; and an empty string is treated as absent, which is the same rule
 * `NSPersonNameComponents` states for nil.
 *
 * **THE ANNOTATED FORM PUBLISHES THE BOUNDARIES THIS FORMATTER ACTUALLY USED.** `NSPersonNameComponentKey` names each
 * run's component and `NSPersonNameComponentDelimiter` marks each separator, so a caller laying a name out per script
 * gets the split the order table produced rather than re-deriving it. Apple's string VALUES for these keys are
 * undocumented; the value used here is the constant's own name, which is a choice the surface plan allows where Apple
 * publishes no behaviour (§11.6 gate 1) and cannot collide with a caller's own key.
 *
 * **TWO DOORS REFUSE RATHER THAN APPROXIMATE.** An unimplemented `style` raises `NSInvalidArgumentException` NAMING the
 * value: `NSPersonNameComponentsFormatterStyleAbbreviated` is 10.12, outside this reference, and what initials look like
 * in an arbitrary script is not a fact this tree has. `-getObjectValue:forString:errorDescription:` answers NO with a
 * nil object and a nil error description — reading a name BACK out of text needs the same data to know which word is
 * which, and Apple's own class does not parse either, so NO is the documented answer and not a refusal of ours.
 */

#ifndef FOUNDATION_NSPERSONNAMECOMPONENTSFORMATTER_H
#define FOUNDATION_NSPERSONNAMECOMPONENTSFORMATTER_H

#import <Foundation/NSFormatter.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPersonNameComponents.h>

@class NSAttributedString;
@class NSString;

typedef NS_ENUM(NSInteger, NSPersonNameComponentsFormatterStyle) {
	NSPersonNameComponentsFormatterStyleDefault = 0,
	NSPersonNameComponentsFormatterStyleShort,
	NSPersonNameComponentsFormatterStyleMedium,
	NSPersonNameComponentsFormatterStyleLong
};

/* ⚠ ONE BIT, AND IT IS `1 << 1`. The zero bit is unused in Apple's header, and a caller who archives an options value
 * or compares against it is reading the number, so the gap is reproduced rather than tidied away. */
typedef NS_OPTIONS(NSUInteger, NSPersonNameComponentsFormatterOptions) {
	NSPersonNameComponentsFormatterPhonetic = (1UL << 1)
};

/* The attribute `-annotatedStringFromPersonNameComponents:` puts on every run: its value is one of the seven keys
 * below, and a separator between two runs carries `NSPersonNameComponentDelimiter` instead. */
extern NSString * _Nonnull const NSPersonNameComponentKey;
extern NSString * _Nonnull const NSPersonNameComponentPrefix;
extern NSString * _Nonnull const NSPersonNameComponentGivenName;
extern NSString * _Nonnull const NSPersonNameComponentMiddleName;
extern NSString * _Nonnull const NSPersonNameComponentFamilyName;
extern NSString * _Nonnull const NSPersonNameComponentSuffix;
extern NSString * _Nonnull const NSPersonNameComponentNickname;
extern NSString * _Nonnull const NSPersonNameComponentDelimiter;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_11)
@interface NSPersonNameComponentsFormatter : NSFormatter
{
	NSPersonNameComponentsFormatterStyle _style;
	BOOL _phonetic;
}

/* `Default` and `Long` write the same components; the style is kept distinct because Apple's enum is, and because a
 * caller that reads `-style` back expects the value it set. An unimplemented value — 10.12's `Abbreviated` — is
 * REFUSED by `-setStyle:` and by `+localizedStringFromPersonNameComponents:style:options:`, naming the value. */
@property NSPersonNameComponentsFormatterStyle style;

/* When YES, the name is taken from `phoneticRepresentation` if the object has one, and from the components themselves
 * if it does not (or if that representation carries no components at all). The switch is total: `-isPhonetic` is YES
 * only when asking for the phonetic spelling actually changed what would be written. */
@property (getter=isPhonetic) BOOL phonetic;

/* THE RENDER. A nil components object writes the empty string: the door's contract is a string, and a name with no
 * components is a name with no text rather than a failure. */
- (NSString *)stringFromPersonNameComponents:(nullable NSPersonNameComponents *)components;

/* THE SAME RENDER, WITH THE COMPONENT BOUNDARIES PUBLISHED (see the note above). Every character of the result is
 * inside exactly one run, separators included. */
- (NSAttributedString *)annotatedStringFromPersonNameComponents:(nullable NSPersonNameComponents *)components;

/* THE ONE-SHOT FORM. `options` is a bit set; the only bit Apple defines for 10.11 is `…Phonetic`. */
+ (NSString *)localizedStringFromPersonNameComponents:(nullable NSPersonNameComponents *)components
                                                style:(NSPersonNameComponentsFormatterStyle)nameFormatStyle
                                              options:(NSPersonNameComponentsFormatterOptions)nameOptions;

/* NSFORMATTER'S PARSING DOOR, ANSWERED `NO`. See the note above: this class formats and does not parse, and a NO with
 * a nil object and a nil error description is exactly that statement. */
- (BOOL)getObjectValue:(out id _Nullable * _Nullable)object
             forString:(NSString *)string
      errorDescription:(out NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSPERSONNAMECOMPONENTSFORMATTER_H */
