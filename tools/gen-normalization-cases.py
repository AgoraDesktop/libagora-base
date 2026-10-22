#!/usr/bin/env python3
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

"""Emit the C case table for Unicode's normalization test suite, one case per construct.

`NormalizationTest.txt` states, for 19,074 cases, five columns — source, NFC, NFD, NFKC, NFKD — and six
invariants that every conformant implementation must satisfy. It is 2.6 MB, so what is COMMITTED is this
recipe and a curated table it produces: **the shortest case the data has for each construct**, which is
the data's own answer and not this tier's.

    python3 tools/gen-normalization-cases.py > /tmp/rows.c

THE FILE IS NOT IN THIS REPOSITORY, the same standing every other UCD file has. The full file was run when
the gate was opened and its score is recorded in `libagora-core/CFString.c` beside `CFStringNormalize` —
**19,074 of 19,074** — and anyone can repeat it by pointing `NORM_TEST` at the download.

    curl -o /tmp/NormalizationTest.txt \
        https://www.unicode.org/Public/15.1.0/ucd/NormalizationTest.txt
"""
import sys

PATH = "/tmp/NormalizationTest.txt"

# The constructs the normalizer has separate code paths for, and a code point that reaches each. A marker is
# (name, required code points, predicate on the case's columns) — the predicate is for the cases whose point is
# the RELATIONSHIP between columns rather than a character.
def build():
    rows = []
    with open(PATH, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#") or line.startswith("@") or not line.strip():
                continue
            body = line.split("#")[0].strip()
            fields = [f.strip() for f in body.split(";")]
            if len(fields) < 5:
                continue
            cols = [[int(x, 16) for x in f.split()] for f in fields[:5]]
            rows.append(cols)
    return rows


# NOTE: there is no separate row for raw Hangul jamo. The data never uses a bare L+V pair as a SOURCE — jamo
# appear in the NFD column — and the invariants feed every column in as an input, so the syllable row below
# already asks the normalizer to compose 1100 1161 back to AC00 (`NFC(c3) == c2`).
CONSTRUCTS = [
    ("a composed letter and its decomposition", {0x00C5}),
    ("a singleton: a compatibility character with a CANONICAL decomposition", {0x212B}),
    ("a compatibility ligature, which only NFKC/NFKD apply", {0xFB01}),
    ("a compatibility number", {0x2460}),
    ("an astral compatibility mapping", {0x1D400}),
    ("a composition exclusion", {0x0958}),
    ("a Hangul syllable", {0xAC00}),
    ("an LV syllable and a trailing jamo: the OTHER half of Hangul composition", {0x1100, 0xAC00, 0x11A8}),
]


def main():
    rows = build()
    chosen = {}
    for cols in rows:
        present = set(cols[0])
        for name, need in CONSTRUCTS:
            matched = need <= present
            if matched:
                if name not in chosen or len(cols[0]) < len(chosen[name][0]):
                    chosen[name] = cols
    # AND ONE CASE WHOSE POINT IS A RELATIONSHIP: the shortest whose NFD is not a simple expansion, i.e. one
    # where marks must be REORDERED.
    reorder = None
    for cols in rows:
        if len(cols[0]) >= 3 and cols[0] != cols[2] and sorted(cols[0]) != cols[0]:
            if reorder is None or len(cols[0]) < len(reorder[0]):
                reorder = cols
    if reorder is not None:
        chosen["canonical ordering: marks that do not arrive in canonical order"] = reorder

    write = sys.stdout.write
    for name, _ in CONSTRUCTS:
        if name not in chosen:
            sys.stderr.write("no case for %s\n" % name)
            continue
        cols = chosen[name]
        write("\t/* %s */\n" % name)
        write('\t{ "%s", "%s", "%s", "%s", "%s", "%s" },\n'
              % (" ".join("%04X" % c for c in cols[0]), " ".join("%04X" % c for c in cols[1]),
                 " ".join("%04X" % c for c in cols[2]), " ".join("%04X" % c for c in cols[3]),
                 " ".join("%04X" % c for c in cols[4]), name.replace('"', '\\"')))
    for name in chosen:
        if name.startswith("canonical ordering"):
            cols = chosen[name]
            write("\t/* %s */\n" % name)
            write('\t{ "%s", "%s", "%s", "%s", "%s", "%s" },\n'
                  % (" ".join("%04X" % c for c in cols[0]), " ".join("%04X" % c for c in cols[1]),
                     " ".join("%04X" % c for c in cols[2]), " ".join("%04X" % c for c in cols[3]),
                     " ".join("%04X" % c for c in cols[4]), name))


if __name__ == "__main__":
    main()
