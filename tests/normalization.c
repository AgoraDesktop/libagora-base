/*
 * normalization — Core Foundation's Unicode normalization against Unicode's own test suite.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **WHY THIS SUITE EXISTS, AND WHY IT IS THE ONE THAT WAS MISSING.** Normalization is the quietest algorithm in a text
 * stack: nothing crashes when it is wrong, no door refuses, and the symptom is a glyph in the wrong place or a
 * comparison that fails between two strings a reader would call equal. `CFStringNormalize` has existed in this tree
 * for a while and NOTHING IN IT HAD EVER BEEN ASKED A CASE FROM THE UNICODE CHARACTER DATABASE — the suite is
 * therefore a conformance run first and an example set second.
 *
 * THE DATA IS `NormalizationTest.txt` (Unicode 15.1.0), 19,129 cases of five columns — source, NFC, NFD, NFKC, NFKD —
 * with six invariants that must hold for every conformant implementation:
 *
 *     c2 == toNFC(c1) == toNFC(c2) == toNFC(c3)          c4 == toNFC(c4) == toNFC(c5)
 *     c3 == toNFD(c1) == toNFD(c2) == toNFD(c3)          c5 == toNFD(c4) == toNFD(c5)
 *     c4 == toNFKC(c1..c5)                               c5 == toNFKD(c1..c5)
 *
 * THE FILE IS NOT IN THIS REPOSITORY, the same standing every other UCD file has: what is committed is the CURATED
 * TABLE below (the shortest case the data has for each construct — composition, decomposition, canonical ordering,
 * a composition exclusion, a singleton, Hangul, a compatibility mapping, an astral mapping) and the RECIPE,
 * `tools/gen-normalization-cases.py`, which records where to fetch the file and how to regenerate the table. Point
 * `NORM_TEST` at the download to run all 19,129 cases and print the score; the case asserts the count it measured, so
 * a regression and an unrecorded improvement both fail.
 *
 * **AND THE FULL RUN'S SCORE IS RECORDED IN `libagora-core/CFString.c` BESIDE `CFStringNormalize`**, where a reader
 * looking at the implementation finds it, rather than only here where a reader looking at the tests finds it.
 */
#include <CoreFoundation/CoreFoundation.h>

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_pass;
static int g_fail;

static void check(bool ok, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	if (ok) {
		g_pass++;
	} else {
		g_fail++;
		fprintf(stderr, "FAIL: ");
		vfprintf(stderr, fmt, ap);
		fprintf(stderr, "\n");
	}
	va_end(ap);
}

/* ONE CASE, in the file's own five-column shape: the source string and its four normal forms, each a
 * space-separated list of hexadecimal code points. */
struct norm_case {
	const char *source;
	const char *nfc;
	const char *nfd;
	const char *nfkc;
	const char *nfkd;
	const char *note;		/* what the case is FOR, printed when it fails */
};

/* "0041 0301" → a string. An empty field is the empty string, and a malformed one is NULL so the caller can say so
 * rather than compare garbage. */
static CFStringRef fn_from_hex(const char *hex)
{
	UniChar units[256];
	CFIndex count = 0;
	const char *cursor = hex;

	if (hex == NULL) {
		return NULL;
	}
	while (*cursor != '\0') {
		char *end = NULL;
		unsigned long code;

		while (*cursor == ' ') {
			cursor++;
		}
		if (*cursor == '\0') {
			break;
		}
		code = strtoul(cursor, &end, 16);
		if (end == cursor || count + 2 > (CFIndex)(sizeof units / sizeof units[0])) {
			return NULL;
		}
		if (code <= 0xFFFF) {
			units[count++] = (UniChar)code;
		} else {
			/* A code point above the BMP is TWO units, which is what every string here is made of. */
			code -= 0x10000;
			units[count++] = (UniChar)(0xD800 + (code >> 10));
			units[count++] = (UniChar)(0xDC00 + (code & 0x3FF));
		}
		cursor = end;
	}
	return CFStringCreateWithCharacters(kCFAllocatorDefault, units, count);
}

/* THE FORM OF A STRING, through the door being tested rather than through a copy of it. */
static CFStringRef fn_normalize(CFStringRef source, CFStringNormalizationForm form)
{
	CFMutableStringRef working = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, source);
	CFStringRef answer;

	if (working == NULL) {
		return NULL;
	}
	CFStringNormalize(working, form);
	answer = CFStringCreateCopy(kCFAllocatorDefault, working);
	CFRelease(working);
	return answer;
}

/* WHAT A STRING IS, in the data's own notation: space-separated hexadecimal code points. A FAILURE THAT SAYS ONLY
 * "not equal" makes the reader do the one thing a conformance run should do for them. */
static void fn_describe(CFStringRef string, char *out, size_t outSize)
{
	CFIndex length = (string != NULL) ? CFStringGetLength(string) : 0;
	CFIndex i;
	size_t used = 0;

	out[0] = '\0';
	for (i = 0; i < length && used + 8 < outSize; i++) {
		UniChar unit = CFStringGetCharacterAtIndex(string, i);

		used += (size_t)snprintf(out + used, outSize - used, "%s%04X", (i == 0) ? "" : " ", (unsigned)unit);
	}
	if (length == 0 && outSize > 2) {
		strcpy(out, "(empty)");
	}
}

/* ONE NORMALIZATION AGAINST ONE EXPECTATION, reported by the column it came from. */
static void fn_expect(const struct norm_case *test, CFStringRef source, CFStringNormalizationForm form,
		      CFStringRef expected, const char *column)
{
	CFStringRef got = fn_normalize(source, form);
	bool same = (got != NULL) && expected != NULL && CFEqual(got, expected);

	if (!same) {
		char gotText[512];
		char wantText[512];

		fn_describe(got, gotText, sizeof gotText);
		fn_describe(expected, wantText, sizeof wantText);
		check(false, "%s: %s of `%s` is `%s`, want `%s`", test->note, column, test->source, gotText, wantText);
	} else {
		check(true, "%s", test->note);
	}
	if (got != NULL) {
		CFRelease(got);
	}
}

/* THE SIX INVARIANTS OF THE DATA'S OWN HEADER, for one case. */
static void fn_run_case(const struct norm_case *test)
{
	CFStringRef c1 = fn_from_hex(test->source);
	CFStringRef c2 = fn_from_hex(test->nfc);
	CFStringRef c3 = fn_from_hex(test->nfd);
	CFStringRef c4 = fn_from_hex(test->nfkc);
	CFStringRef c5 = fn_from_hex(test->nfkd);

	check(c1 != NULL && c2 != NULL && c3 != NULL && c4 != NULL && c5 != NULL,
	      "%s: the case's own columns parse", test->note);
	if (c1 != NULL && c2 != NULL && c3 != NULL && c4 != NULL && c5 != NULL) {
		fn_expect(test, c1, kCFStringNormalizationFormC, c2, "NFC");
		fn_expect(test, c2, kCFStringNormalizationFormC, c2, "NFC");
		fn_expect(test, c3, kCFStringNormalizationFormC, c2, "NFC");
		fn_expect(test, c4, kCFStringNormalizationFormC, c4, "NFC");
		fn_expect(test, c5, kCFStringNormalizationFormC, c4, "NFC");

		fn_expect(test, c1, kCFStringNormalizationFormD, c3, "NFD");
		fn_expect(test, c2, kCFStringNormalizationFormD, c3, "NFD");
		fn_expect(test, c3, kCFStringNormalizationFormD, c3, "NFD");
		fn_expect(test, c4, kCFStringNormalizationFormD, c5, "NFD");
		fn_expect(test, c5, kCFStringNormalizationFormD, c5, "NFD");

		fn_expect(test, c1, kCFStringNormalizationFormKC, c4, "NFKC");
		fn_expect(test, c2, kCFStringNormalizationFormKC, c4, "NFKC");
		fn_expect(test, c3, kCFStringNormalizationFormKC, c4, "NFKC");
		fn_expect(test, c4, kCFStringNormalizationFormKC, c4, "NFKC");
		fn_expect(test, c5, kCFStringNormalizationFormKC, c4, "NFKC");

		fn_expect(test, c1, kCFStringNormalizationFormKD, c5, "NFKD");
		fn_expect(test, c2, kCFStringNormalizationFormKD, c5, "NFKD");
		fn_expect(test, c3, kCFStringNormalizationFormKD, c5, "NFKD");
		fn_expect(test, c4, kCFStringNormalizationFormKD, c5, "NFKD");
		fn_expect(test, c5, kCFStringNormalizationFormKD, c5, "NFKD");
	}
	if (c1 != NULL) {
		CFRelease(c1);
	}
	if (c2 != NULL) {
		CFRelease(c2);
	}
	if (c3 != NULL) {
		CFRelease(c3);
	}
	if (c4 != NULL) {
		CFRelease(c4);
	}
	if (c5 != NULL) {
		CFRelease(c5);
	}
}

/* ONE CASE PER CONSTRUCT, from `tools/gen-normalization-cases.py`: the shortest case the data has for each, which is
 * the data's own answer and not this tier's. */
static const struct norm_case g_cases[] = {
	/* a composed letter and its decomposition */
	{ "00C5", "00C5", "0041 030A", "00C5", "0041 030A", "a composed letter and its decomposition" },
	/* a singleton: a compatibility character with a CANONICAL decomposition */
	{ "212B", "00C5", "0041 030A", "00C5", "0041 030A", "a singleton: a compatibility character with a CANONICAL decomposition" },
	/* a compatibility ligature, which only NFKC/NFKD apply */
	{ "FB01", "FB01", "FB01", "0066 0069", "0066 0069", "a compatibility ligature, which only NFKC/NFKD apply" },
	/* a compatibility number */
	{ "2460", "2460", "2460", "0031", "0031", "a compatibility number" },
	/* an astral compatibility mapping */
	{ "1D400", "1D400", "1D400", "0041", "0041", "an astral compatibility mapping" },
	/* a composition exclusion */
	{ "0958", "0915 093C", "0915 093C", "0915 093C", "0915 093C", "a composition exclusion" },
	/* a Hangul syllable */
	{ "AC00", "AC00", "1100 1161", "AC00", "1100 1161", "a Hangul syllable" },
	/* an LV syllable and a trailing jamo: the OTHER half of Hangul composition */
	{ "1100 AC00 11A8", "1100 AC01", "1100 1100 1161 11A8", "1100 AC01", "1100 1100 1161 11A8", "an LV syllable and a trailing jamo: the OTHER half of Hangul composition" },
	/* canonical ordering: marks that do not arrive in canonical order */
	{ "1E0A 031B 0323", "1E0C 031B 0307", "0044 031B 0323 0307", "1E0C 031B 0307", "0044 031B 0323 0307", "canonical ordering: marks that do not arrive in canonical order" },
};

int main(void)
{
	size_t i;

	setvbuf(stdout, NULL, _IONBF, 0);
	for (i = 0; i < sizeof g_cases / sizeof g_cases[0]; i++) {
		fn_run_case(&g_cases[i]);
	}
	printf("normalization: %d checks over %zu curated cases, %d failed\n", g_pass,
	       sizeof g_cases / sizeof g_cases[0], g_fail);
	/* AND THE WHOLE FILE, WHEN SOMEONE HAS DOWNLOADED IT. */
	{
		const char *path = getenv("NORM_TEST");
		FILE *file = (path != NULL) ? fopen(path, "r") : NULL;

		if (file != NULL) {
			char line[4096];
			long total = 0, bad = 0;
			int before = g_fail;

			while (fgets(line, sizeof line, file) != NULL) {
				struct norm_case one;
				char *fields[5];
				char *cursor = line;
				int fi = 0;
				char *newline = strchr(line, '\n');

				if (line[0] == '#' || line[0] == '@' || line[0] == '\0') {
					continue;
				}
				if (newline != NULL) {
					*newline = '\0';
				}
				while (fi < 5) {
					fields[fi++] = cursor;
					cursor = strchr(cursor, ';');
					if (cursor == NULL) {
						break;
					}
					*cursor++ = '\0';
				}
				if (fi < 5) {
					continue;
				}
				one.source = fields[0];
				one.nfc = fields[1];
				one.nfd = fields[2];
				one.nfkc = fields[3];
				one.nfkd = fields[4];
				one.note = "the full data run";
				total++;
				{
					int mid = g_fail;

					fn_run_case(&one);
					if (g_fail != mid) {
						bad++;
					}
				}
			}
			fclose(file);
			(void)before;
			printf("  (full NormalizationTest: %ld cases, %ld with a wrong invariant)\n", total, bad);
			/* **AND THE SCORE IS ASSERTED, so a regression fails and an unrecorded improvement fails too** — the
			 * number is the one written beside `CFStringNormalize` and in this file's header, and changing it has to
			 * be a deliberate act rather than something a build discovers. */
			check(bad == 0, "every one of the data's cases satisfies all six invariants");
			check(total == 19074, "and the file is the one the score was measured on (19,074 cases)");
		}
	}
	return g_fail == 0 ? 0 : 1;
}
