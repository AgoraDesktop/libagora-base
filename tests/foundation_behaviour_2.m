/*
 * foundation_behaviour_2 — the third wave of the behavioural pass.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. The first two waves cover the value types and the machinery around them. This one covers the
 * CALENDAR (where a wrong answer is a wrong date, not a wrong ordering), the formatters, the defaults store's
 * domains, XML parsing and serialisation, value transformers, HTTP cookies, locales and time-zone transitions.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int g_fail;

static void
check(int condition, const char *what)
{
	if (!condition) {
		printf("FAIL: %s\n", what);
		g_fail = 1;
	} else {
		printf("ok: %s\n", what);
	}
}

@interface XMLProbe : NSObject <NSXMLParserDelegate>
{
@public
	NSMutableArray *elements;
	NSMutableString *text;
	int ended;
}
@end

@implementation XMLProbe
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		elements = [[NSMutableArray alloc] init];
		text = [[NSMutableString alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[elements release];
	[text release];
	[super dealloc];
}
- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)elementName
      namespaceURI:(NSString *)namespaceURI
     qualifiedName:(NSString *)qualifiedName
	attributes:(NSDictionary *)attributes
{
	(void)parser; (void)namespaceURI; (void)qualifiedName;
	[elements addObject:[NSString stringWithFormat:@"<%@ %@>", elementName, attributes]];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	(void)parser;
	[text appendString:string];
}
- (void)parser:(NSXMLParser *)parser
      didEndElement:(NSString *)elementName
       namespaceURI:(NSString *)namespaceURI
      qualifiedName:(NSString *)qualifiedName
{
	(void)parser; (void)elementName; (void)namespaceURI; (void)qualifiedName;
	ended++;
}
@end

@interface UpperTransformer : NSValueTransformer
@end

@implementation UpperTransformer
+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value { return [(NSString *)value uppercaseString]; }
- (id)reverseTransformedValue:(id)value { return [(NSString *)value lowercaseString]; }
@end

int
main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	char configRoot[] = "/tmp/agora-defaults-XXXXXX";

	/* THE DEFAULTS STORE'S ROOT IS THE INSTALLATION'S CONFIGURATION TREE (FNX_CONFIG_ROOT), not the process's HOME:
	 * point it at a scratch directory so the probe cannot write to the real install. */
	if (mkdtemp(configRoot) != NULL) {
		setenv("FNX_CONFIG_ROOT", configRoot, 1);
	}

	/* ============================== CALENDAR ================================================== */

	{
		NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		NSDateComponents *components = [[NSDateComponents alloc] init];
		NSDate *date;
		NSDateComponents *back;

		[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[components setYear:2024];
		[components setMonth:2];
		[components setDay:29];
		[components setHour:12];
		[components setMinute:34];
		[components setSecond:56];
		check([components isValidDateInCalendar:calendar], "2024-02-29 is a valid date in the Gregorian calendar");
		date = [calendar dateFromComponents:components];
		check(date != nil, "the calendar builds a date from components");
		back = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
					    NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
				   fromDate:date];
		check([back year] == 2024 && [back month] == 2 && [back day] == 29 &&
		      [back hour] == 12 && [back minute] == 34 && [back second] == 56,
		      "the components round-trip through the calendar");

		[components setYear:2023];
		[components setMonth:2];
		[components setDay:29];
		check(![components isValidDateInCalendar:calendar], "2023-02-29 is not a valid date");
		[components release];
	}
	{
		/* DAY ARITHMETIC ACROSS A DST TRANSITION: 2024-03-10 01:30 in New York plus one day is 2024-03-11
		 * 01:30 LOCAL, even though only 23 wall-clock hours elapsed. */
		NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		NSTimeZone *zone = [NSTimeZone timeZoneWithName:@"America/New_York"];
		NSDate *start;
		NSDate *next;
		NSDateComponents *parts;
		NSDateComponents *delta = [[NSDateComponents alloc] init];

		[calendar setTimeZone:zone];
		parts = [[NSDateComponents alloc] init];
		[parts setYear:2024];
		[parts setMonth:3];
		[parts setDay:10];
		[parts setHour:1];
		[parts setMinute:30];
		start = [calendar dateFromComponents:parts];
		[parts release];
		[delta setDay:1];
		next = [calendar dateByAddingComponents:delta toDate:start options:0];
		check(next != nil && [next timeIntervalSinceDate:start] == 23 * 3600,
		      "adding one day across a spring-forward transition is 23 hours of elapsed time");
		{
			NSDateComponents *nextParts = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute
								 fromDate:next];

			check([nextParts hour] == 1 && [nextParts minute] == 30,
			      "the added day keeps the local wall-clock hour");
		}
		[delta release];
	}
	{
		NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		NSDateComponents *parts = [[NSDateComponents alloc] init];
		NSDate *date;

		[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[parts setYear:2024];
		[parts setMonth:2];
		[parts setDay:15];
		date = [calendar dateFromComponents:parts];
		check([calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:date].length == 29,
		      "February 2024 has 29 days");
		check([calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitYear forDate:date] == 46,
		      "2024-02-15 is the 46th day of the year");
		check([calendar startOfDayForDate:date] != nil, "-startOfDayForDate:");
		[parts release];
	}

	/* ============================== FORMATTERS ================================================ */

	{
		NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
		NSNumber *number = [NSNumber numberWithDouble:1234.5678];
		NSString *text;

		[formatter setNumberStyle:NSNumberFormatterDecimalStyle];
		[formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
		[formatter setMinimumFractionDigits:2];
		[formatter setMaximumFractionDigits:2];
		text = [formatter stringFromNumber:number];
		check(text != nil && [text rangeOfString:@"1"].location != NSNotFound,
		      "-stringFromNumber: renders a decimal");
		check([[formatter numberFromString:text] doubleValue] > 1234.5,
		      "-numberFromString: reads its own output");
		[formatter setUsesGroupingSeparator:YES];
		check([[formatter stringFromNumber:[NSNumber numberWithInt:1234567]]
		       rangeOfString:@","].location != NSNotFound, "a grouping separator is used when asked");
		[formatter release];
	}
	{
		NSDateComponentsFormatter *formatter = [[NSDateComponentsFormatter alloc] init];

		[formatter setAllowedUnits:NSCalendarUnitHour | NSCalendarUnitMinute];
		[formatter setUnitsStyle:NSDateComponentsFormatterUnitsStylePositional];
		check([[formatter stringFromTimeInterval:3661.0] rangeOfString:@"1"].location != NSNotFound,
		      "-stringFromTimeInterval: renders a duration");
		[formatter release];
	}

	/* ============================== USER DEFAULTS DOMAINS ==================================== */

	{
		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"AgoraBehaviourProbe"];
		NSDictionary *volatileDomain = [NSDictionary dictionaryWithObjectsAndKeys:
						@"volatile", @"probeKey", nil];
		NSDictionary *stableDomain = [NSDictionary dictionaryWithObjectsAndKeys:
					      @"stable", @"otherKey", nil];

		[defaults setVolatileDomain:volatileDomain forName:@"AgoraVolatileProbe"];
		check([[[defaults volatileDomainForName:@"AgoraVolatileProbe"] objectForKey:@"probeKey"]
		       isEqualToString:@"volatile"], "a volatile domain round-trips");
		check([[defaults volatileDomainNames] containsObject:@"AgoraVolatileProbe"],
		      "-volatileDomainNames names the domain");

		[defaults setPersistentDomain:stableDomain forName:@"AgoraPersistentProbe"];
		check([[[defaults persistentDomainForName:@"AgoraPersistentProbe"] objectForKey:@"otherKey"]
		       isEqualToString:@"stable"], "a persistent domain round-trips");
		[defaults removePersistentDomainForName:@"AgoraPersistentProbe"];
		check([[defaults persistentDomainForName:@"AgoraPersistentProbe"] count] == 0,
		      "-removePersistentDomainForName: removes it");

		[defaults registerDefaults:[NSDictionary dictionaryWithObject:@"fallback" forKey:@"registeredKey"]];
		check([[defaults objectForKey:@"registeredKey"] isEqualToString:@"fallback"],
		      "-registerDefaults: supplies a fallback");
		[defaults setObject:@"explicit" forKey:@"registeredKey"];
		check([[defaults objectForKey:@"registeredKey"] isEqualToString:@"explicit"],
		      "an explicit value wins over a registered default");
		[defaults removeObjectForKey:@"registeredKey"];
		check([[defaults objectForKey:@"registeredKey"] isEqualToString:@"fallback"],
		      "removing the explicit value restores the registered default");
		[defaults removeVolatileDomainForName:@"AgoraVolatileProbe"];
		[defaults release];
	}

	/* ============================== XML ======================================================= */

	{
		const char *xml = "<root a=\"1\"><child>text</child><empty/></root>";
		NSData *data = [NSData dataWithBytes:xml length:strlen(xml)];
		NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
		XMLProbe *probe = [[XMLProbe alloc] init];
		int parsed;

		[parser setDelegate:probe];
		parsed = [parser parse];
		check(parsed && [parser parserError] == nil, "the XML parser accepts a well-formed document");
		check([probe->elements count] == 3, "the delegate is told about every element");
		check([probe->text isEqualToString:@"text"], "the delegate receives the character data");
		check([parser lineNumber] > 0, "-lineNumber is reported");
		[probe release];
		[parser release];
	}
	{
		const char *xml = "<root><child></root>";
		NSXMLParser *parser = [[NSXMLParser alloc] initWithData:
					[NSData dataWithBytes:xml length:strlen(xml)]];
		check(![parser parse] && [parser parserError] != nil,
		      "the XML parser refuses a malformed document with an error");
		[parser release];
	}
	{
		NSError *error = nil;
		NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:
					   @"<root id=\"7\"><child>hello</child></root>"
								   options:0 error:&error];
		NSXMLElement *root = [document rootElement];
		NSArray *children = nil;
		NSData *serialised = nil;

		check(document != nil && error == nil, "an NSXMLDocument parses a string");
		check([[root name] isEqualToString:@"root"], "-rootElement names the root");
		children = [root elementsForName:@"child"];
		check([children count] == 1, "-elementsForName:");
		check([[[children objectAtIndex:0] stringValue] isEqualToString:@"hello"],
		      "-stringValue of an element");
		check([[[root attributeForName:@"id"] stringValue] isEqualToString:@"7"],
		      "-attributeForName:");
		serialised = [document XMLData];
		check(serialised != nil && [serialised length] > 0, "-XMLData serialises the document");
		check([[NSString alloc] initWithData:serialised encoding:NSUTF8StringEncoding] != nil,
		      "the serialised document is UTF-8 text");
		[document release];

		error = nil;
		document = [[NSXMLDocument alloc] initWithXMLString:@"<root>" options:0 error:&error];
		check(document == nil && error != nil, "malformed XML answers nil and an error");
	}
	{
		/* NAMESPACES, ATTRIBUTES AND A ROUND TRIP THROUGH SERIALISATION. */
		NSError *error = nil;
		NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:
					   @"<a:root xmlns:a=\"urn:probe\"><a:child x=\"1\">t</a:child></a:root>"
								   options:NSXMLNodePreserveNamespaceOrder
								      error:&error];
		NSData *serialised = document != nil ? [document XMLData] : nil;

		check(document != nil && error == nil, "a namespaced document parses");
		check(serialised != nil, "a namespaced document serialises");
		/* THIS TREE KEEPS AN xmlns DECLARATION AS A NAMESPACE CHILD (NSXMLDocument.m states the choice), so the
		 * root has TWO children — the namespace and the element — while -namespaces reports the declaration. */
		check([[document rootElement] childCount] == 2, "-childCount counts the namespace child this tree keeps");
		check([[[document rootElement] namespaces] count] == 1, "-namespaces reports the declaration");
		check([[[document rootElement] elementsForName:@"a:child"] count] == 1,
		      "-elementsForName: finds a prefixed element");
		[document release];
	}

	/* ============================== VALUE TRANSFORMERS ======================================== */

	{
		UpperTransformer *transformer = [[UpperTransformer alloc] init];

		[NSValueTransformer setValueTransformer:transformer forName:@"AgoraUpperTransformer"];
		check([NSValueTransformer valueTransformerForName:@"AgoraUpperTransformer"] == transformer,
		      "a transformer is registered by name");
		check([[[NSValueTransformer valueTransformerForName:@"AgoraUpperTransformer"]
			transformedValue:@"abc"] isEqualToString:@"ABC"], "-transformedValue:");
		check([[[NSValueTransformer valueTransformerForName:@"AgoraUpperTransformer"]
			reverseTransformedValue:@"ABC"] isEqualToString:@"abc"], "-reverseTransformedValue:");
		[NSValueTransformer setValueTransformer:nil forName:@"AgoraUpperTransformer"];
		check([NSValueTransformer valueTransformerForName:@"AgoraUpperTransformer"] == nil,
		      "registering nil removes the transformer");
		[transformer release];
	}

	/* ============================== HTTP COOKIES ============================================== */

	{
		NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:
					    @"name", NSHTTPCookieName,
					    @"value", NSHTTPCookieValue,
					    @".example.com", NSHTTPCookieDomain,
					    @"/path", NSHTTPCookiePath,
					    nil];
		NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:properties];
		NSArray *cookies = [NSArray arrayWithObject:cookie];
		NSDictionary *fields;

		check(cookie != nil, "+cookieWithProperties:");
		check([[cookie name] isEqualToString:@"name"] && [[cookie value] isEqualToString:@"value"],
		      "a cookie answers its name and value");
		check([[cookie domain] isEqualToString:@".example.com"], "a cookie answers its domain");
		fields = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
		check(fields != nil && [fields objectForKey:@"Cookie"] != nil,
		      "-requestHeaderFieldsWithCookies: produces a Cookie header");
		{
			NSArray *back = [NSHTTPCookie cookiesWithResponseHeaderFields:
					 [NSDictionary dictionaryWithObject:@"name=value; Path=/; Domain=.example.com"
								     forKey:@"Set-Cookie"]
								     forURL:[NSURL URLWithString:@"https://www.example.com/"]];
			check([back count] == 1 && [[[back objectAtIndex:0] name] isEqualToString:@"name"],
			      "-cookiesWithResponseHeaderFields:forURL:");
		}
	}

	/* ============================== LOCALES AND TIME ZONES ==================================== */

	{
		NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

		check([[locale localeIdentifier] isEqualToString:@"en_US_POSIX"], "-localeIdentifier");
		check([[locale languageCode] isEqualToString:@"en"], "-languageCode");
		check([[locale countryCode] isEqualToString:@"US"], "-countryCode");
		check([[[locale objectForKey:NSLocaleIdentifier] description] length] > 0,
		      "-objectForKey: answers the identifier key");
	}
	{
		NSTimeZone *zone = [NSTimeZone timeZoneWithName:@"America/New_York"];
		NSDate *winter = [NSDate dateWithTimeIntervalSince1970:1700000000.0];	/* November */
		NSDate *summer = [NSDate dateWithTimeIntervalSince1970:1720000000.0];	/* July */

		check(zone != nil, "+timeZoneWithName:");
		check([[zone name] isEqualToString:@"America/New_York"], "-name");
		check([zone secondsFromGMTForDate:winter] == -5 * 3600, "EST is five hours behind UTC");
		check([zone secondsFromGMTForDate:summer] == -4 * 3600, "EDT is four hours behind UTC");
		check(![zone isDaylightSavingTimeForDate:winter] && [zone isDaylightSavingTimeForDate:summer],
		      "-isDaylightSavingTimeForDate:");
	}

	[pool drain];
	printf(g_fail ? "foundation_behaviour_2: FAIL\n" : "foundation_behaviour_2: all checks passed\n");
	return g_fail;
}
