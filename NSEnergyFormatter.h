/*
 * NSEnergyFormatter.h
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * `NSEnergyFormatter` (§62.50), the third of Apple's formatter trio. See NSLengthFormatter.h for the value scheme
 * (§11.6.1 D2) and the locale stance.
 *
 * THIS ONE'S FLAG IS NOT METRIC VERSUS IMPERIAL, because energy has no imperial units: `forFoodEnergyUse` asks for
 * the CALORIE family — which is what a food label uses — where the default is the joule family.
 */

#ifndef FOUNDATION_NSENERGYFORMATTER_H
#define FOUNDATION_NSENERGYFORMATTER_H

#import <Foundation/NSFormatter.h>
#import <Foundation/NSString.h>

@class NSNumberFormatter;

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	NSEnergyFormatterUnitJoule	= 1,
	NSEnergyFormatterUnitKilojoule	= 2,
	NSEnergyFormatterUnitCalorie	= 3,
	NSEnergyFormatterUnitKilocalorie	= 4
} NSEnergyFormatterUnit;

NS_SWIFT_NAME(EnergyFormatter)
NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSEnergyFormatter : NSFormatter
{
	NSNumberFormatter *_numberFormatter;
	BOOL _forFoodEnergyUse;
	NSFormattingUnitStyle _unitStyle;	/* default Medium: 0 is NOT a style (see NSFormatter.h) */
}

- (nullable NSNumberFormatter *)numberFormatter;
- (void)setNumberFormatter:(nullable NSNumberFormatter *)numberFormatter;
- (BOOL)isForFoodEnergyUse;
- (void)setForFoodEnergyUse:(BOOL)use;

/* THE UNIT STYLE (10.10). Short and medium render the SI symbol; long renders the unit's name, pluralised
 * unless the value is exactly one. Apple's default is medium, and it is set in -init because a zeroed ivar
 * is not a style — the enum's values are 1/2/3 (see NSFormatter.h). */
- (NSFormattingUnitStyle)unitStyle;
- (void)setUnitStyle:(NSFormattingUnitStyle)style;

- (NSString *)stringFromValue:(double)value unit:(NSEnergyFormatterUnit)unit;
- (NSString *)stringFromJoules:(double)number;
- (NSString *)unitStringFromValue:(double)value unit:(NSEnergyFormatterUnit)unit;
- (NSString *)unitStringFromJoules:(double)number usedUnit:(nullable NSEnergyFormatterUnit *)unitp;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSENERGYFORMATTER_H */
