/*
 * NSEnergyFormatter.m
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The same shape again (see NSLengthFormatter.m): a table, a base unit, one chooser, and one flag that chooses the
 * FAMILY — which for this quantity is joule versus calorie rather than metric versus imperial, because energy has
 * no imperial units.
 */

#import <Foundation/NSEnergyFormatter.h>
#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSNumber.h>
#include <stdio.h>

typedef struct {
	NSEnergyFormatterUnit unit;
	const char *symbol;
	const char *longOne;		/* the unit's NAME, singular */
	const char *longMany;		/* and plural, for the long style */
	double perJoule;		/* how many of this unit one joule holds */
	BOOL food;			/* the calorie family, which `forFoodEnergyUse` asks for */
} FNEnergyUnitInfo;

static const FNEnergyUnitInfo fn_ef_units[] = {
	{ NSEnergyFormatterUnitJoule,		"J", "joule", "joules",	1.0,				NO },
	{ NSEnergyFormatterUnitKilojoule,	"kJ", "kilojoule", "kilojoules",	0.001,				NO },
	{ NSEnergyFormatterUnitCalorie,		"cal", "calorie", "calories",	0.2390057361376673,		YES },
	{ NSEnergyFormatterUnitKilocalorie,	"kcal", "kilocalorie", "kilocalories",	0.0002390057361376673,		YES }
};

#define FN_EF_UNIT_COUNT	(sizeof(fn_ef_units) / sizeof(fn_ef_units[0]))

static const FNEnergyUnitInfo *fn_ef_find(NSEnergyFormatterUnit unit)
{
	NSUInteger i;

	for (i = 0; i < FN_EF_UNIT_COUNT; i++) {
		if (fn_ef_units[i].unit == unit) {
			return &fn_ef_units[i];
		}
	}
	return NULL;
}

static double fn_ef_fromJoules(double joules, NSEnergyFormatterUnit unit)
{
	const FNEnergyUnitInfo *info = fn_ef_find(unit);

	return info == NULL ? joules : joules * info->perJoule;
}

static double fn_ef_toJoules(double value, NSEnergyFormatterUnit unit)
{
	const FNEnergyUnitInfo *info = fn_ef_find(unit);

	return info == NULL ? value : value / info->perJoule;
}

static void fn_ef_natural(BOOL food, double joules, NSEnergyFormatterUnit *outUnit, double *outValue)
{
	NSUInteger i;
	NSEnergyFormatterUnit chosen = 0;
	BOOL haveChosen = NO;

	for (i = 0; i < FN_EF_UNIT_COUNT; i++) {
		if (fn_ef_units[i].food != food) {
			continue;
		}
		if (!haveChosen || fn_ef_fromJoules(joules, fn_ef_units[i].unit) >= 1.0) {
			chosen = fn_ef_units[i].unit;
		}
		haveChosen = YES;
	}
	if (!haveChosen) {
		chosen = NSEnergyFormatterUnitJoule;
	}
	*outUnit = chosen;
	*outValue = fn_ef_fromJoules(joules, chosen);
}

@implementation NSEnergyFormatter

- (id)init
{
	self = [super init];
	if (self != nil) {
		_numberFormatter = nil;
		_forFoodEnergyUse = NO;
		_unitStyle = NSFormattingUnitStyleMedium;
	}
	return self;
}

- (NSNumberFormatter *)numberFormatter { return _numberFormatter; }

- (void)setNumberFormatter:(NSNumberFormatter *)numberFormatter
{
	NSNumberFormatter *old = _numberFormatter;

	_numberFormatter = [numberFormatter retain];
	[old release];
}

- (BOOL)isForFoodEnergyUse { return _forFoodEnergyUse; }
- (void)setForFoodEnergyUse:(BOOL)use { _forFoodEnergyUse = use; }

/* THE UNIT STYLE (10.10). Short and medium render the SI symbol; long renders the unit's name, pluralised unless the
 * value is exactly one. Apple defaults to medium, and -init says so explicitly because the enum's values are 1/2/3
 * (NSFormatter.h): a zeroed ivar is not a style. */
- (NSFormattingUnitStyle)unitStyle { return _unitStyle; }
- (void)setUnitStyle:(NSFormattingUnitStyle)style { _unitStyle = style; }

- (NSString *)fn_unitName:(const FNEnergyUnitInfo *)info forValue:(double)value
{
	if (info == NULL) {
		return @"";
	}
	if (_unitStyle == NSFormattingUnitStyleLong) {
		const char *name = (value == 1.0) ? info->longOne : info->longMany;
		return [NSString stringWithUTF8String:name];
	}
	return [NSString stringWithUTF8String:info->symbol];
}

- (NSString *)fn_value:(double)value name:(NSString *)name
{
	if (_numberFormatter != nil) {
		return [NSString stringWithFormat:@"%@ %@",
			[_numberFormatter stringFromNumber:[NSNumber numberWithDouble:value]], name];
	}
	return [NSString stringWithFormat:@"%.4g %@", value, name];
}

- (NSString *)stringFromValue:(double)value unit:(NSEnergyFormatterUnit)unit
{
	const FNEnergyUnitInfo *info = fn_ef_find(unit);

	if (info == NULL) {
		return [NSString stringWithFormat:@"%.4g", value];
	}
	return [self fn_value:value name:[self fn_unitName:info forValue:value]];
}

- (NSString *)unitStringFromValue:(double)value unit:(NSEnergyFormatterUnit)unit
{
	const FNEnergyUnitInfo *info = fn_ef_find(unit);

	(void)value;
	return [self fn_unitName:info forValue:value];
}

- (NSString *)unitStringFromJoules:(double)number usedUnit:(NSEnergyFormatterUnit *)unitp
{
	NSEnergyFormatterUnit chosen;
	double value;

	fn_ef_natural(_forFoodEnergyUse, number, &chosen, &value);
	if (unitp != NULL) {
		*unitp = chosen;
	}
	return [self unitStringFromValue:value unit:chosen];
}

- (NSString *)stringFromJoules:(double)number
{
	NSEnergyFormatterUnit chosen;
	double value;

	/* FOOD ENERGY IS KILOCALORIES — the unit a label uses — and the joule family is the default for everything
	 * else. The flag chooses a FAMILY here rather than a measurement system, because energy has no imperial units. */
	if (_forFoodEnergyUse) {
		value = fn_ef_fromJoules(number, NSEnergyFormatterUnitKilocalorie);
		return [self stringFromValue:value unit:NSEnergyFormatterUnitKilocalorie];
	}
	fn_ef_natural(NO, number, &chosen, &value);
	return [self stringFromValue:value unit:chosen];
}

- (void)dealloc
{
	[_numberFormatter release];
	[super dealloc];
}

@end
