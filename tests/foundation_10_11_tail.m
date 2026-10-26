/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_tail.m — THE REMAINING SINGLES OF W6: the linguistic tagger's four doors, the regular expression's
 * three, the pointer array's four factories, and the stored properties on NSUserActivity, NSDateComponents,
 * NSProcessInfo, NSNetService and NSXMLParser.
 *
 * The two that carry the wave's acceptance are here: the tagger is measured AGAINST FNTextBreaking (the same break
 * iterator the rest of the library uses, so its token ranges must be the bridge's, not a second opinion), and the
 * regular expression's escapers are measured by round-tripping a literal through a pattern and a template.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSLinguisticTagger.h>
#import <Foundation/NSRegularExpression.h>
#import <Foundation/NSPointerArray.h>
#import <Foundation/NSUserActivity.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSNetServices.h>
#import <Foundation/NSXMLParser.h>
#import <Foundation/FNTextBreaking.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ---- NSLinguisticTagger: the 10.7 class door, the batch tags, the lattice, and the edit notice ---- */
	{
		NSArray *schemes = [NSLinguisticTagger availableTagSchemesForLanguage:@"en"];
		NSLinguisticTagger *tagger = [[[NSLinguisticTagger alloc] initWithTagSchemes:
			[NSArray arrayWithObjects:NSLinguisticTagSchemeTokenType, NSLinguisticTagSchemeScript, nil]
									 options:0] autorelease];
		NSString *text = @"One two. Three four!";
		NSArray *bridgeWords = [NSMutableArray array];
		NSArray *tags;
		NSArray *tokenRanges = nil;
		__block NSUInteger bridgeCount = 0;

		check([schemes containsObject:NSLinguisticTagSchemeTokenType] &&
		      [schemes containsObject:NSLinguisticTagSchemeScript] &&
		      ![schemes containsObject:NSLinguisticTagSchemeLexicalClass],
		      "availableTagSchemesForLanguage: names the two schemes that are properties of a token, not the refused one");
		[tagger setString:text];
		[FNTextBreaking fnEnumerate:FNTextUnitWord
				   inString:text
				      range:NSMakeRange(0, [text length])
				 usingBlock:^(NSRange unitRange, BOOL *stop) {
			(void)stop;
			bridgeCount++;
			[(NSMutableArray *)bridgeWords addObject:[NSValue valueWithRange:unitRange]];
		}];
		tags = [tagger tagsInRange:NSMakeRange(0, [text length])
				    scheme:NSLinguisticTagSchemeTokenType
				   options:0
			       tokenRanges:&tokenRanges];
		check([tags count] == bridgeCount && [tokenRanges count] == bridgeCount,
		      "tagsInRange: visits exactly the units FNTextBreaking reports");
		check([tokenRanges isEqualToArray:bridgeWords],
		      "and every token range is the bridge's own range, not a second opinion");
		check([[tags objectAtIndex:0] isEqualToString:NSLinguisticTagWord] &&
		      [[tags objectAtIndex:1] isEqualToString:NSLinguisticTagWhitespace],
		      "the tags classify the tokens they cover");
		{
			NSRange token = NSMakeRange(NSNotFound, 0);
			NSRange sentence = NSMakeRange(NSNotFound, 0);
			NSArray *possible;
			NSArray *scores = nil;

			possible = [tagger possibleTagsAtIndex:0
							scheme:NSLinguisticTagSchemeTokenType
						    tokenRange:&token
						 sentenceRange:&sentence
							scores:&scores];
			check([possible count] == 1 && [[possible objectAtIndex:0] isEqualToString:NSLinguisticTagWord] &&
			      [scores count] == 1 && [[scores objectAtIndex:0] doubleValue] == 1.0,
			      "the lattice answers one alternative with score 1.0 where the tagger is certain");
			check(token.location == 0 && token.length == 3 &&
			      sentence.location == [tagger sentenceRangeForRange:NSMakeRange(0, 3)].location &&
			      sentence.length == [tagger sentenceRangeForRange:NSMakeRange(0, 3)].length,
			      "the lattice fills the token range and the sentence range the same door reports");
			check([tagger possibleTagsAtIndex:0
						   scheme:NSLinguisticTagSchemeLexicalClass
					       tokenRange:NULL
					    sentenceRange:NULL
						   scores:&scores] == nil && [scores count] == 0,
			      "and answers nil, with no scores, for a refused scheme");
		}
		{
			NSOrthography *orthography = [[[NSOrthography alloc] init] autorelease];
			NSRange effective = NSMakeRange(NSNotFound, 0);

			[tagger setOrthography:orthography range:NSMakeRange(10, 5)];
			[tagger stringEditedInRange:NSMakeRange(0, 0) changeInLength:4];	/* an insertion before it */
			[tagger orthographyAtIndex:14 effectiveRange:&effective];
			check(effective.location == 14 && effective.length == 5,
			      "an insertion before the orthography's range shifts it by the length change");
			[tagger stringEditedInRange:NSMakeRange(14, 2) changeInLength:2];	/* inside it */
			[tagger orthographyAtIndex:14 effectiveRange:&effective];
			check(effective.location == 14 && effective.length == 7,
			      "an edit inside it changes its length");
		}
	}

	/* ---- NSRegularExpression: the escapers and one replacement ---- */
	{
		NSString *literal = @"a.b*c(d)$e[f]\\g";
		NSString *pattern = [NSRegularExpression escapedPatternForString:literal];
		NSRegularExpression *escaped = [NSRegularExpression regularExpressionWithPattern:pattern
											options:0
											  error:NULL];
		NSString *template = [NSRegularExpression escapedTemplateForString:@"$1\\literal"];
		NSString *replaced;
		NSRegularExpression *groups = [NSRegularExpression regularExpressionWithPattern:@"([a-z]+)@([a-z]+)"
										       options:0
											 error:NULL];
		NSTextCheckingResult *match = [groups firstMatchInString:@"mail me@example now"
								options:0
								  range:NSMakeRange(0, 20)];

		check([escaped numberOfMatchesInString:literal options:0 range:NSMakeRange(0, [literal length])] == 1 &&
		      [[[escaped firstMatchInString:literal options:0 range:NSMakeRange(0, [literal length])] description]
		       length] > 0,
		      "an escaped pattern matches its literal text");
		replaced = [escaped stringByReplacingMatchesInString:literal
							      options:0
								range:NSMakeRange(0, [literal length])
						 withTemplate:template];
		check([replaced isEqualToString:@"$1\\literal"],
		      "an escaped template produces its literal text, with $ and backslash inert");
		check(match != nil && [match numberOfRanges] == 3,
		      "the group pattern matches with two captures");
		check([groups replacementStringForResult:match
						inString:@"mail me@example now"
						  offset:0
						template:@"$2 <$1>"] != nil &&
		      [[groups replacementStringForResult:match
						 inString:@"mail me@example now"
						   offset:0
					       template:@"$2 <$1>"] isEqualToString:@"example <me>"],
		      "the replacement template substitutes the capture groups by number");
		check([[groups replacementStringForResult:match
						 inString:@"XX mail me@example now"
						   offset:3
					       template:@"$0"] isEqualToString:@"me@example"],
		      "the offset moves where the matched text is cut from the string");
	}

	/* ---- NSPointerArray: the four 10.5 factories ---- */
	{
		NSPointerArray *byOptions = [NSPointerArray pointerArrayWithOptions:
			NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
		NSPointerFunctions *functions = [[[NSPointerFunctions alloc]
			initWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality] autorelease];
		NSPointerArray *byFunctions = [NSPointerArray pointerArrayWithPointerFunctions:functions];
		NSPointerArray *strong = [NSPointerArray pointerArrayWithStrongObjects];
		NSPointerArray *weak = [NSPointerArray pointerArrayWithWeakObjects];
		NSString *object = @"member";

		[byOptions addPointer:(void *)object];
		[byFunctions addPointer:(void *)object];
		[strong addPointer:(void *)object];
		[weak addPointer:(void *)object];
		check([byOptions count] == 1 && [byOptions pointerAtIndex:0] == (void *)object &&
		      [[byOptions allObjects] count] == 1,
		      "pointerArrayWithOptions: takes its options and holds the pointer");
		check([byFunctions count] == 1 && [byFunctions pointerAtIndex:0] == (void *)object &&
		      [byFunctions pointerFunctions] == functions,
		      "pointerArrayWithPointerFunctions: keeps the functions it was handed");
		check([strong count] == 1 && [strong pointerAtIndex:0] == (void *)object &&
		      [weak count] == 1 && [weak pointerAtIndex:0] == (void *)object,
		      "the two deprecated object factories make the two object configurations");
	}

	/* ---- the stored properties: NSUserActivity, NSDateComponents, NSProcessInfo, NSNetService, NSXMLParser ---- */
	{
		NSUserActivity *activity = [[[NSUserActivity alloc] initWithActivityType:@"com.example.type"] autorelease];
		NSDateComponents *components = [[[NSDateComponents alloc] init] autorelease];
		NSString *xml = @"<?xml version=\"1.0\"?><root><child/></root>";
		NSXMLParser *parser = [[[NSXMLParser alloc] initWithData:
			[xml dataUsingEncoding:NSUTF8StringEncoding]] autorelease];
		NSURL *allowed = [NSURL fileURLWithPath:@"/tmp/agora-allowed"];
		NSNetService *service = [[[NSNetService alloc] initWithDomain:@"local." type:@"_http._tcp." name:@"web" port:80]
			autorelease];
		NSNetServiceBrowser *browser = [[[NSNetServiceBrowser alloc] init] autorelease];

		check([activity isEligibleForHandoff] == NO && [activity isEligibleForSearch] == NO &&
		      [activity isEligibleForPublicIndexing] == NO,
		      "an activity starts ineligible for all three");
		[activity setEligibleForHandoff:YES];
		[activity setEligibleForSearch:YES];
		[activity setEligibleForPublicIndexing:YES];
		check([activity isEligibleForHandoff] && [activity isEligibleForSearch] &&
		      [activity isEligibleForPublicIndexing],
		      "and reports each flag it was given");

		[components setYear:2024];
		[components setMonth:2];
		[components setDay:29];
		check([components isLeapMonth] == NO, "a components bag starts not declaring a leap month");
		[components setLeapMonth:YES];
		check([components isLeapMonth] && [components isValidDate],
		      "the leap-month flag is stored and the leap day is a valid date");

		check([[NSProcessInfo processInfo] isLowPowerModeEnabled] == NO,
		      "this system has no low-power mode to be in");

		check([service includesPeerToPeer] == NO && [browser includesPeerToPeer] == NO,
		      "a service and a browser start without peer-to-peer");
		[service setIncludesPeerToPeer:YES];
		[browser setIncludesPeerToPeer:YES];
		check([service includesPeerToPeer] && [browser includesPeerToPeer],
		      "the 10.10 flag is stored and reported on both");

		check([parser externalEntityResolvingPolicy] == NSXMLParserResolveExternalEntitiesNever &&
		      [parser allowedExternalEntityURLs] == nil,
		      "the parser resolves no external entity and permits none");
		[parser setExternalEntityResolvingPolicy:NSXMLParserResolveExternalEntitiesNoNetwork];
		[parser setAllowedExternalEntityURLs:[NSArray arrayWithObject:allowed]];
		check([parser externalEntityResolvingPolicy] == NSXMLParserResolveExternalEntitiesNoNetwork &&
		      [[parser allowedExternalEntityURLs] isEqualToArray:[NSArray arrayWithObject:allowed]],
		      "the policy and the allowed list are stored and reported");
		check([parser parse], "the stored policy does not break parsing the document");
	}

	printf("foundation_10_11_tail: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
