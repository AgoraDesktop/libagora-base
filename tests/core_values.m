/*
 * core_values — the documented behaviour of the value types, collections, persistence codecs and URLs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. The 10.6 census counts a door when a body exists; this probe asks whether the body does the
 * documented thing. It is the behavioural pass over the types an application uses most: strings, arrays, dictionaries,
 * sets, numbers, data, index sets, dates, the JSON and property-list codecs, the two archivers, and NSURL. Each check
 * names the contract it is asserting, so a failure says WHAT is wrong rather than only that something is.
 *
 * IT IS NOT A CONFORMANCE SUITE for Unicode: this library states that it normalises nowhere, and the checks below stay
 * on the side of that boundary (UTF-16 indices, byte-wise folds) instead of charging it for canonical equivalence.
 */

#import <Foundation/Foundation.h>

#include <CoreFoundation/CoreFoundation.h>
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

static int
raises(void (^body)(void))
{
	@try {
		body();
	} @catch (id exception) {
		(void)exception;
		return 1;
	}
	return 0;
}

/* ---- a codable value used by both archivers --------------------------------------------------------------- */

@interface CodableThing : NSObject <NSCoding>
{
@public
	NSString *name;
	NSNumber *size;
	CodableThing *link;
}
@end

@implementation CodableThing

- (void)dealloc
{
	[name release];
	[size release];
	[link release];
	[super dealloc];
}

- (BOOL)isEqual:(id)other
{
	if (![other isKindOfClass:[CodableThing class]]) {
		return NO;
	}
	return [name isEqualToString:((CodableThing *)other)->name] &&
	       [size isEqualToNumber:((CodableThing *)other)->size];
}

- (NSUInteger)hash
{
	return [name hash] ^ [size hash];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:name forKey:@"name"];
	[coder encodeObject:size forKey:@"size"];
	[coder encodeObject:link forKey:@"link"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil) {
		name = [[coder decodeObjectForKey:@"name"] retain];
		size = [[coder decodeObjectForKey:@"size"] retain];
		link = [[coder decodeObjectForKey:@"link"] retain];
	}
	return self;
}

@end

/* The keyed archiver needs keyed doors; the sequential one needs the value doors. Two classes keep the two contracts
 * honest instead of one class pretending to both. */
@interface SequentialThing : NSObject <NSCoding>
{
@public
	NSString *name;
	int number;
}
@end

@implementation SequentialThing

- (void)dealloc
{
	[name release];
	[super dealloc];
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[SequentialThing class]] &&
	       [name isEqualToString:((SequentialThing *)other)->name] &&
	       number == ((SequentialThing *)other)->number;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:name];
	[coder encodeValueOfObjCType:@encode(int) at:&number];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil) {
		name = [[coder decodeObject] retain];
		[coder decodeValueOfObjCType:@encode(int) at:&number];
	}
	return self;
}

@end

int
main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ============================== STRINGS ================================================== */

	{
		NSString *a = @"abc";
		NSMutableString *b = [NSMutableString stringWithString:@"abc"];
		NSString *formatted = [NSString stringWithFormat:@"%@%@", @"a", @"bc"];

		check([a isEqual:b], "a string equals a mutable string with the same characters");
		check([a hash] == [formatted hash], "equal strings hash alike across construction");
		check([a hash] == [b hash], "equal strings hash alike across mutability");
		check([a compare:b] == NSOrderedSame, "-compare: answers Same for equal strings");
		check([[a copy] isKindOfClass:[NSString class]] && ![[a copy] isKindOfClass:[NSMutableString class]],
		      "-copy of an immutable string is immutable");
		check([[[b copy] class] isSubclassOfClass:[NSMutableString class]] == NO,
		      "-copy of a MUTABLE string is immutable");
		check([[[b mutableCopy] class] isSubclassOfClass:[NSMutableString class]],
		      "-mutableCopy of a string is mutable");
	}

	{
		NSString *emoji = @"a\U0001F600b";	/* 'a', one non-BMP scalar, 'b' */

		check([emoji length] == 4, "-length counts UTF-16 units, so a non-BMP scalar is two");
		check([emoji characterAtIndex:1] == 0xD83D, "-characterAtIndex: answers a high surrogate");
		check([emoji characterAtIndex:2] == 0xDE00, "-characterAtIndex: answers a low surrogate");
		check([[emoji substringWithRange:NSMakeRange(1, 2)] isEqualToString:@"\U0001F600"],
		      "-substringWithRange: takes a UTF-16 range");
		check([[emoji substringToIndex:1] isEqualToString:@"a"], "-substringToIndex: is a UTF-16 index");
		check([emoji lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 6,
		      "-lengthOfBytesUsingEncoding: counts UTF-8 bytes");
		check(strcmp([emoji UTF8String], "a\xF0\x9F\x98\x80" "b") == 0, "-UTF8String encodes a non-BMP scalar");
	}

	{
		NSString *text = @"The quick brown fox";

		check([text rangeOfString:@"quick"].location == 4, "-rangeOfString: finds the first occurrence");
		check([text rangeOfString:@"o" options:NSBackwardsSearch].location == 17,
		      "-rangeOfString:options: honours NSBackwardsSearch");
		check([text rangeOfString:@"The" options:NSAnchoredSearch].location == 0,
		      "-rangeOfString:options: honours NSAnchoredSearch");
		check([text rangeOfString:@"the" options:NSCaseInsensitiveSearch].location == 0,
		      "NSCaseInsensitiveSearch folds ASCII case");
		check([@"file10" compare:@"file9" options:NSNumericSearch] == NSOrderedDescending,
		      "NSNumericSearch compares digit runs by value");
		check([@"abc" compare:@"abd"] == NSOrderedAscending, "-compare: orders by code unit");
		check([@"abc" hasPrefix:@""] && [@"abc" hasSuffix:@""], "every string has the empty prefix and suffix");
		check([@"a,b,,c" componentsSeparatedByString:@","].count == 4,
		      "-componentsSeparatedByString: keeps empty components");
		check([[@"abcabc" stringByReplacingOccurrencesOfString:@"a" withString:@"z"] isEqualToString:@"zbczbc"],
		      "-stringByReplacingOccurrencesOfString: replaces every occurrence");
		check([@"abc" stringByPaddingToLength:5 withString:@"-" startingAtIndex:0].length == 5,
		      "-stringByPaddingToLength: reaches the requested length");
	}

	{
		check([@"  -42xyz" integerValue] == -42, "-integerValue skips leading space and stops at junk");
		check([@"3.5e2" doubleValue] == 350.0, "-doubleValue reads an exponent");
		check([@"true" boolValue] && [@"YES" boolValue] && [@"1" boolValue], "-boolValue reads YES/true/1");
		check(![@"no" boolValue] && ![@"false" boolValue] && ![@"" boolValue], "-boolValue reads NO/false/empty");
		check(raises(^{
			volatile unichar ignored = [@"abc" characterAtIndex:3];
			(void)ignored;
		}), "-characterAtIndex: past the end raises");
		check(raises(^{ [@"abc" substringToIndex:4]; }), "-substringToIndex: past the end raises");
	}

	/* ============================== ARRAYS =================================================== */

	{
		NSArray *array = [NSArray arrayWithObjects:@"a", @"b", @"c", nil];
		NSMutableArray *mutable = [NSMutableArray arrayWithArray:array];
		NSArray *equal = [NSArray arrayWithObjects:
				  [NSString stringWithFormat:@"%@", @"a"], @"b", @"c", nil];

		check([array isEqualToArray:equal], "-isEqualToArray: compares elements by value");
		check([array hash] == [equal hash], "equal arrays hash alike");
		check([array indexOfObject:@"b"] == 1, "-indexOfObject: uses -isEqual:");
		check([array containsObject:@"c"], "-containsObject: uses -isEqual:");
		check([array firstObject] != nil && [[array firstObject] isEqual:@"a"], "-firstObject");
		check([array lastObject] != nil && [[array lastObject] isEqual:@"c"], "-lastObject");
		check([[array arrayByAddingObject:@"d"] count] == 4, "-arrayByAddingObject:");
		check([[array subarrayWithRange:NSMakeRange(1, 2)] count] == 2, "-subarrayWithRange:");
		check([array objectsAtIndexes:[NSIndexSet indexSetWithIndex:2]].count == 1,
		      "-objectsAtIndexes:");
		check([array reverseObjectEnumerator].allObjects.count == 3,
		      "-reverseObjectEnumerator walks backwards");
		check([[[array mutableCopy] class] isSubclassOfClass:[NSMutableArray class]],
		      "-mutableCopy of an array is mutable");
		check([[[mutable copy] class] isSubclassOfClass:[NSMutableArray class]] == NO,
		      "-copy of a MUTABLE array is immutable");
		check(raises(^{ [array objectAtIndex:3]; }), "-objectAtIndex: past the end raises");
		check(raises(^{ [array subarrayWithRange:NSMakeRange(2, 2)]; }),
		      "-subarrayWithRange: past the end raises");
		check([[array sortedArrayUsingSelector:@selector(compare:)] isEqualToArray:array],
		      "-sortedArrayUsingSelector: orders by -compare:");
		check([[array sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
			return [(NSString *)y compare:(NSString *)x];
		}] isEqualToArray:[NSArray arrayWithObjects:@"c", @"b", @"a", nil]],
		      "-sortedArrayUsingComparator: honours the block");
		check([array indexOfObjectPassingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)index; (void)stop;
			return [(NSString *)object isEqualToString:@"c"];
		}] == 2, "-indexOfObjectPassingTest:");
	}

	{
		NSMutableArray *mutable = [NSMutableArray arrayWithObjects:@1, @2, @3, nil];
		BOOL raised = raises(^{
			for (id object in mutable) {
				(void)object;
				[mutable addObject:@4];
			}
		});

		check(raised, "mutating an array while enumerating it raises");
	}

	{
		NSMutableArray *array = [NSMutableArray array];

		[array addObject:@"a"];
		[array insertObject:@"b" atIndex:1];
		[array replaceObjectAtIndex:0 withObject:@"c"];
		[array removeObjectAtIndex:0];
		check([array isEqualToArray:[NSArray arrayWithObject:@"b"]],
		      "add/insert/replace/remove keep the array in order");
	}

	/* ============================== DICTIONARIES ============================================= */

	{
		NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
					    @"one", @"1", @"two", @"2", nil];
		NSDictionary *equal = [NSDictionary dictionaryWithObjectsAndKeys:
				       [NSString stringWithFormat:@"%@", @"two"], @"2",
				       @"one", @"1", nil];

		check([dictionary isEqualToDictionary:equal], "-isEqualToDictionary: is key- and value-based");
		check([dictionary hash] == [equal hash], "equal dictionaries hash alike");
		check([[dictionary objectForKey:@"1"] isEqual:@"one"], "-objectForKey:");
		check([[dictionary allKeysForObject:@"two"] count] == 1, "-allKeysForObject:");
		check([[dictionary objectsForKeys:[NSArray arrayWithObjects:@"1", @"missing", nil]
			   notFoundMarker:[NSNull null]] count] == 2,
		      "-objectsForKeys:notFoundMarker: answers one object per key");
		check([[dictionary objectsForKeys:[NSArray arrayWithObjects:@"1", @"missing", nil]
			   notFoundMarker:[NSNull null]] objectAtIndex:1] == (id)[NSNull null],
		      "the not-found marker is the missing key's answer");
		check([[dictionary keyEnumerator].allObjects count] == 2, "-keyEnumerator walks the keys");
		check([[[dictionary mutableCopy] class] isSubclassOfClass:[NSMutableDictionary class]],
		      "-mutableCopy of a dictionary is mutable");
		check([[[dictionary mutableCopy] copy] isEqual:dictionary], "a copied dictionary still equals the original");
		check(raises(^{
			NSMutableDictionary *mutable = [NSMutableDictionary dictionary];
			[mutable setObject:@"x" forKey:(NSString *)nil];
		}), "setting a nil key raises");
	}
	{
		NSMutableDictionary *mutable = [NSMutableDictionary dictionary];
		BOOL raised = raises(^{
			[mutable setObject:@"a" forKey:@"1"];
			[mutable setObject:@"b" forKey:@"2"];
			for (id key in mutable) {
				(void)key;
				[mutable setObject:@"c" forKey:@"3"];
			}
		});

		check(raised, "mutating a dictionary while enumerating it raises");
	}

	/* ============================== SETS ===================================================== */

	{
		NSMutableString *stored = [NSMutableString stringWithString:@"member"];
		NSSet *set = [NSSet setWithObjects:stored, @"other", nil];
		NSString *probe = [NSString stringWithFormat:@"%@", @"member"];
		NSSet *equal = [NSSet setWithObjects:@"other", probe, nil];
		NSSet *subset = [NSSet setWithObject:@"other"];

		check([set isEqualToSet:equal], "-isEqualToSet: compares members by value");
		check([set hash] == [equal hash], "equal sets hash alike");
		check([set member:probe] == stored, "-member: answers the instance STORED in the set");
		check([subset isSubsetOfSet:set], "-isSubsetOfSet:");
		check([set intersectsSet:subset], "-intersectsSet:");
		check([[set setByAddingObject:@"third"] count] == 3, "-setByAddingObject:");
		check([[[set mutableCopy] class] isSubclassOfClass:[NSMutableSet class]],
		      "-mutableCopy of a set is mutable");
		check([[set allObjects] count] == 2, "-allObjects");
	}

	{
		NSCountedSet *counted = [NSCountedSet set];

		[counted addObject:@"x"];
		[counted addObject:@"x"];
		[counted addObject:@"y"];
		check([counted countForObject:@"x"] == 2, "-countForObject: counts duplicates");
		check([counted count] == 2, "-count counts DISTINCT members");
		[counted removeObject:@"x"];
		check([counted countForObject:@"x"] == 1, "-removeObject: decrements, it does not remove");
		check([counted containsObject:@"x"], "a decremented member is still present");
	}

	/* ============================== NUMBERS ================================================== */

	{
		NSNumber *integerOne = [NSNumber numberWithInt:1];
		NSNumber *doubleOne = [NSNumber numberWithDouble:1.0];
		NSNumber *boolOne = [NSNumber numberWithBool:YES];
		long long big = 9007199254740993LL;	/* 2^53 + 1 */
		long long smaller = 9007199254740992LL;

		check([integerOne isEqual:doubleOne], "an int 1 equals a double 1.0");
		check([integerOne hash] == [doubleOne hash], "numbers equal across kinds hash alike");
		check([integerOne isEqual:boolOne], "an int 1 equals a boolean YES");
		check([integerOne compare:doubleOne] == NSOrderedSame, "-compare: agrees with equality");
		check([[NSNumber numberWithLongLong:big] compare:[NSNumber numberWithLongLong:smaller]] ==
		      NSOrderedDescending,
		      "-compare: keeps 64-bit precision above 2^53");
		check(![[NSNumber numberWithLongLong:big] isEqual:[NSNumber numberWithLongLong:smaller]],
		      "-isEqualToNumber: keeps 64-bit precision above 2^53");
		check(strcmp([integerOne objCType], @encode(int)) == 0, "-objCType preserves the creation type");
		check(strcmp([doubleOne objCType], @encode(double)) == 0, "-objCType preserves a double");
		check([[integerOne stringValue] isEqualToString:@"1"], "-stringValue of an int");
		check([[doubleOne stringValue] isEqualToString:@"1"], "-stringValue of a whole double");
		check([boolOne boolValue] && [integerOne boolValue], "-boolValue of YES and 1");
	}

	{
		NSDecimalNumber *tenth = [NSDecimalNumber decimalNumberWithString:@"0.1"];
		NSDecimalNumber *fifth = [NSDecimalNumber decimalNumberWithString:@"0.2"];
		NSDecimalNumber *threeTenths = [NSDecimalNumber decimalNumberWithString:@"0.3"];
		NSDecimalNumber *sum = [tenth decimalNumberByAdding:fifth];

		check([sum isEqualToNumber:threeTenths], "decimal 0.1 + 0.2 is exactly 0.3");
		check([[tenth decimalNumberByMultiplyingBy:fifth] isEqualToNumber:
		       [NSDecimalNumber decimalNumberWithString:@"0.02"]], "decimal multiplication is exact");
		check([[NSDecimalNumber notANumber] isEqualToNumber:[NSDecimalNumber notANumber]] == NO,
		      "NaN is not equal to itself");
	}

	/* ============================== DATA ===================================================== */

	{
		unsigned char bytes[] = { 1, 2, 3, 4, 5 };
		NSData *data = [NSData dataWithBytes:bytes length:sizeof bytes];
		NSData *equal = [NSData dataWithData:data];
		NSData *different = [NSData dataWithBytes:bytes length:4];

		check([data isEqualToData:equal], "-isEqualToData:");
		check([data hash] == [equal hash], "equal data hashes alike");
		check(![data isEqualToData:different], "different lengths are not equal");
		check([[data subdataWithRange:NSMakeRange(1, 3)] length] == 3, "-subdataWithRange:");
		check(raises(^{ [data subdataWithRange:NSMakeRange(4, 2)]; }),
		      "-subdataWithRange: past the end raises");
		check([data rangeOfData:[NSData dataWithBytes:bytes + 2 length:2]
				options:0
				  range:NSMakeRange(0, 5)].location == 2,
		      "-rangeOfData:options:range:");
		check([[[data mutableCopy] class] isSubclassOfClass:[NSMutableData class]],
		      "-mutableCopy of data is mutable");
		check([[data base64EncodedStringWithOptions:0] length] > 0, "-base64EncodedStringWithOptions:");
		check([[NSData dataWithBase64EncodedString:[data base64EncodedStringWithOptions:0]]
		       isEqualToData:data], "base64 round-trips");
	}

	/* ============================== INDEX SETS =============================================== */

	{
		NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];

		[indexes addIndex:1];
		[indexes addIndex:2];
		[indexes addIndex:3];
		[indexes addIndex:10];
		check([indexes count] == 4, "-count counts indexes");
		check([indexes containsIndexesInRange:NSMakeRange(1, 3)], "adjacent indexes form one range");
		check([indexes indexGreaterThanIndex:2] == 3, "-indexGreaterThanIndex:");
		check([indexes indexGreaterThanIndex:3] == 10, "the next range's first index follows");
		check([indexes indexLessThanIndex:10] == 3, "-indexLessThanIndex:");
		check([indexes intersectsIndexesInRange:NSMakeRange(2, 1)],
		      "-intersectsIndexesInRange:");
		[indexes removeIndex:2];
		check(![indexes containsIndex:2], "-removeIndex:");
		{
			__block NSUInteger rangeCount = 0;

			[indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
				(void)range; (void)stop;
				rangeCount++;
			}];
			check(rangeCount == 3, "-enumerateRangesUsingBlock: visits one range per run");
		}
		check([[indexes copy] isEqualToIndexSet:indexes], "a copied index set is equal");
	}

	/* ============================== DATES ==================================================== */

	{
		NSDate *now = [NSDate dateWithTimeIntervalSince1970:1700000000.0];
		NSDate *same = [NSDate dateWithTimeIntervalSince1970:1700000000.0];
		NSDate *later = [NSDate dateWithTimeIntervalSince1970:1700000001.0];
		NSDate *earlier = [NSDate dateWithTimeIntervalSince1970:1699999999.0];

		check([now isEqualToDate:same], "-isEqualToDate:");
		check([now hash] == [same hash], "equal dates hash alike");
		check([now compare:later] == NSOrderedAscending, "-compare: orders dates");
		check([now earlierDate:later] == now, "-earlierDate:");
		check([now laterDate:earlier] == now, "-laterDate:");
		check(fabs([now timeIntervalSince1970] - 1700000000.0) < 0.001, "-timeIntervalSince1970 round-trips");
	}

	/* ============================== JSON ===================================================== */

	{
		NSDictionary *object = [NSDictionary dictionaryWithObjectsAndKeys:
					@"text", @"string",
					[NSNumber numberWithInt:7], @"number",
					[NSNumber numberWithBool:YES], @"flag",
					[NSNull null], @"nothing",
					[NSArray arrayWithObjects:@1, @2, nil], @"list",
					nil];
		NSError *error = nil;
		NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
		id back;

		check(data != nil && error == nil, "a JSON object encodes");
		back = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
		check([back isKindOfClass:[NSDictionary class]], "the encoded JSON decodes to a dictionary");
		check([[back objectForKey:@"string"] isEqualToString:@"text"], "a JSON string round-trips");
		check([[back objectForKey:@"number"] intValue] == 7, "a JSON number round-trips");
		check([[back objectForKey:@"flag"] boolValue], "a JSON boolean round-trips");
		check([back objectForKey:@"nothing"] == [NSNull null], "JSON null becomes NSNull");
		check([[back objectForKey:@"list"] count] == 2, "a JSON array round-trips");

		error = nil;
		check([NSJSONSerialization JSONObjectWithData:[@"\"bare\"" dataUsingEncoding:NSUTF8StringEncoding]
						      options:0 error:&error] == nil && error != nil,
		      "a top-level fragment is refused without NSJSONReadingAllowFragments");
		error = nil;
		check([NSJSONSerialization JSONObjectWithData:[@"\"bare\"" dataUsingEncoding:NSUTF8StringEncoding]
						      options:NSJSONReadingAllowFragments error:&error] != nil,
		      "NSJSONReadingAllowFragments accepts one");
		error = nil;
		check([NSJSONSerialization JSONObjectWithData:[@"{oops" dataUsingEncoding:NSUTF8StringEncoding]
						      options:0 error:&error] == nil && error != nil,
		      "malformed JSON answers nil and an error");
	}

	/* ============================== PROPERTY LISTS =========================================== */

	{
		NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
				       @"value", @"string",
				       [NSNumber numberWithInt:42], @"number",
				       [NSNumber numberWithDouble:1.5], @"real",
				       [NSNumber numberWithDouble:0.0], @"zero",
				       [NSNumber numberWithBool:NO], @"flag",
				       [NSData dataWithBytes:"abc" length:3], @"data",
				       [NSDate dateWithTimeIntervalSince1970:1700000000.0], @"date",
				       [NSArray arrayWithObjects:@1, @2, nil], @"array",
				       nil];
		NSPropertyListFormat format = 0;
		NSError *error = nil;
		NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist
									format:NSPropertyListXMLFormat_v1_0
								       options:0
									 error:&error];
		id back;

		check(xml != nil && error == nil, "a property list writes as XML");
		back = [NSPropertyListSerialization propertyListWithData:xml
								 options:0
								  format:&format
								   error:&error];
		check(format == NSPropertyListXMLFormat_v1_0, "the XML format is reported");
		check([back isEqualToDictionary:plist], "an XML property list round-trips");
		check([[[back objectForKey:@"date"] class] isSubclassOfClass:[NSDate class]],
		      "a property-list date decodes as NSDate");

		/* AND THE BINARY FORMAT, which is Core Foundation's reader and writer rather than a third plist core:
		 * "bplist00" on the wire and the same tree on the other side. */
		error = nil;
		{
			NSData *binary = [NSPropertyListSerialization dataWithPropertyList:plist
										    format:NSPropertyListBinaryFormat_v1_0
										   options:0
										     error:&error];
			NSPropertyListFormat reported = 0;

			check(binary != nil && error == nil, "a property list writes as binary");
			check([binary length] >= 8 && memcmp([binary bytes], "bplist00", 8) == 0,
			      "the binary write carries the bplist magic");
			back = [NSPropertyListSerialization propertyListWithData:binary
									 options:0
									  format:&reported
									   error:&error];
			check(reported == NSPropertyListBinaryFormat_v1_0, "the binary format is reported");
			check([back isEqualToDictionary:plist], "a binary property list round-trips");
			check([[[back objectForKey:@"date"] class] isSubclassOfClass:[NSDate class]],
			      "a binary date decodes as NSDate");
			check([[back objectForKey:@"real"] doubleValue] == 1.5,
			      "a binary real keeps its value");
			check([[back objectForKey:@"zero"] isKindOfClass:[NSNumber class]] &&
			      [[back objectForKey:@"zero"] doubleValue] == 0.0,
			      "a binary real zero is an object and keeps its value");
			check(CFGetTypeID((CFTypeRef)[back objectForKey:@"flag"]) == CFBooleanGetTypeID(),
			      "a binary boolean decodes as a boolean, not a number");
			check([NSPropertyListSerialization propertyList:plist
							     isValidForFormat:NSPropertyListBinaryFormat_v1_0],
			      "+propertyList:isValidForFormat: accepts a writable tree as binary");

			/* THE MUTABILITY OPTION IS THE CALLER'S, and Core Foundation's reader honours it through this
			 * library's mutable classes rather than through a second conversion pass. */
			back = [NSPropertyListSerialization propertyListWithData:binary
									 options:NSPropertyListMutableContainersAndLeaves
									  format:NULL
									   error:&error];
			check([back isKindOfClass:[NSMutableDictionary class]],
			      "NSPropertyListMutableContainersAndLeaves makes the root mutable");
			check([[(NSDictionary *)back objectForKey:@"array"] isKindOfClass:[NSMutableArray class]],
			      "the option makes a nested container mutable");
			check([[(NSDictionary *)back objectForKey:@"string"] isKindOfClass:[NSMutableString class]],
			      "the option makes a leaf string mutable");

			/* A TRUNCATED BINARY PLIST IS AN ERROR, not a half-read tree. */
			error = nil;
			check([NSPropertyListSerialization propertyListWithData:[binary subdataWithRange:NSMakeRange(0, 12)]
								       options:0 format:NULL error:&error] == nil && error != nil,
			      "a truncated binary property list answers nil and an error");
		}
		error = nil;
		check([NSPropertyListSerialization propertyListWithData:[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding]
						       options:0 format:&format error:&error] == nil && error != nil,
		      "malformed property-list data answers nil and an error");
	}

	/* ============================== ARCHIVERS ================================================ */

	{
		CodableThing *parent = [[CodableThing alloc] init];
		CodableThing *child = [[CodableThing alloc] init];
		CodableThing *decoded;
		NSError *error = nil;
		NSData *data;

		parent->name = [@"parent" copy];
		parent->size = [[NSNumber numberWithInt:1] retain];
		child->name = [@"child" copy];
		child->size = [[NSNumber numberWithInt:2] retain];
		child->link = [parent retain];		/* a cycle: parent -> child -> parent */
		parent->link = [child retain];

		data = [NSKeyedArchiver archivedDataWithRootObject:parent requiringSecureCoding:NO error:&error];
		check(data != nil && error == nil, "a keyed archive writes a cyclic graph");
		decoded = data != nil
			? [NSKeyedUnarchiver unarchivedObjectOfClass:[CodableThing class] fromData:data error:&error]
			: nil;
		check(decoded != nil, "the keyed archive reads back");
		check([decoded->name isEqualToString:@"parent"], "the root's fields round-trip");
		check(decoded->link != nil && [decoded->link->name isEqualToString:@"child"],
		      "the child round-trips");
		check(decoded->link->link == decoded, "a cycle is preserved, not duplicated");
		[parent release];
		[child release];
	}

	{
		/* AND THE KEYED ARCHIVER'S BINARY FORM. -setOutputFormat: has always accepted the binary format;
		 * before the property list could write it, the archive came back nil. */
		CodableThing *thing = [[CodableThing alloc] init];
		NSMutableData *buffer = [NSMutableData data];
		NSKeyedArchiver *writer = [[NSKeyedArchiver alloc] initForWritingWithMutableData:buffer];
		CodableThing *decoded;

		thing->name = [@"binary" copy];
		thing->size = [[NSNumber numberWithInt:5] retain];
		[writer setOutputFormat:NSPropertyListBinaryFormat_v1_0];
		[writer encodeObject:thing forKey:@"root"];
		[writer finishEncoding];
		check([buffer length] >= 8 && memcmp([buffer bytes], "bplist00", 8) == 0,
		      "NSKeyedArchiver writes bplist00 when -setOutputFormat: asks for binary");
		decoded = [NSKeyedUnarchiver unarchiveObjectWithData:buffer];
		check(decoded != nil && [decoded->name isEqualToString:@"binary"],
		      "a binary keyed archive reads back");
		[writer release];
		[thing release];
	}

	{
		SequentialThing *thing = [[SequentialThing alloc] init];
		NSData *data;
		SequentialThing *decoded;

		thing->name = [@"sequential" copy];
		thing->number = 9;
		data = [NSArchiver archivedDataWithRootObject:thing];
		check(data != nil, "the sequential archiver writes a graph");
		decoded = data != nil ? [NSUnarchiver unarchiveObjectWithData:data] : nil;
		check(decoded != nil && [decoded isEqual:thing], "the sequential archive round-trips");
		[thing release];
	}

	{
		/* THE CLASS-NAME MAP: the writer renames the class, and the reader maps the name back. */
		SequentialThing *thing = [[SequentialThing alloc] init];
		NSMutableData *buffer = [NSMutableData data];
		NSArchiver *writer = [[NSArchiver alloc] initForWritingWithMutableData:buffer];
		SequentialThing *decoded;

		thing->name = [@"renamed" copy];
		thing->number = 3;
		[writer encodeClassName:@"SequentialThing" intoClassName:@"ArchivedSequentialThing"];
		[writer encodeRootObject:thing];
		{
			NSUnarchiver *reader = [[NSUnarchiver alloc] initForReadingWithData:buffer];

			/* THE MAP MUST BE IN PLACE BEFORE THE ROOT IS DECODED, which is why this door exists separately from
			 * +unarchiveObjectWithData: (that one decodes the root for the caller immediately). */
			[reader decodeClassName:@"ArchivedSequentialThing" asClassName:@"SequentialThing"];
			decoded = [reader decodeObject];
			check([decoded isEqual:thing], "the class-name map makes a renamed class readable");
			[reader release];
		}
		[writer release];
		[thing release];
	}

	/* ============================== URLs ===================================================== */

	{
		NSURL *url = [NSURL URLWithString:@"https://user@example.com:8443/a%20b/c?q=1&r=two#frag"];

		check([[url scheme] isEqualToString:@"https"], "-scheme");
		check([[url host] isEqualToString:@"example.com"], "-host");
		check([[url user] isEqualToString:@"user"], "-user");
		check([[url port] intValue] == 8443, "-port");
		check([[url path] isEqualToString:@"/a b/c"], "-path decodes percent escapes");
		check([[url query] isEqualToString:@"q=1&r=two"], "-query");
		check([[url fragment] isEqualToString:@"frag"], "-fragment");
		check([[url absoluteString] rangeOfString:@"%20"].location != NSNotFound,
		      "-absoluteString keeps the escaped form");
	}
	{
		NSURL *base = [NSURL URLWithString:@"https://example.com/dir/page.html"];
		NSURL *resolved = [NSURL URLWithString:@"../other.html" relativeToURL:base];

		check([[resolved absoluteString] isEqualToString:@"https://example.com/other.html"],
		      "a relative URL resolves against its base");
		check([[base URLByAppendingPathComponent:@"child"] path].length > 0,
		      "-URLByAppendingPathComponent:");
	}
	{
		NSURL *file = [NSURL fileURLWithPath:@"/tmp/a file.txt"];

		check([file isFileURL], "-isFileURL");
		check([[file path] isEqualToString:@"/tmp/a file.txt"], "a file URL round-trips a path with a space");
		check([[file absoluteString] rangeOfString:@"%20"].location != NSNotFound,
		      "a file URL escapes the space in its string form");
		check([NSURL URLWithString:[file absoluteString]] != nil, "the escaped form parses back");
	}

	[pool drain];
	printf(g_fail ? "core_values: FAIL\n" : "core_values: all checks passed\n");
	return g_fail;
}
