# api/10.11 — the committed facts of Apple's 10.11 Foundation

**The SDK is not here, and must not be.** Apple's headers are not redistributable. What is here is a **name manifest**:
class names with their superclasses, protocol names, selector names per class, C function names, and the two
availability facts a name list cannot carry — names and relationships only, facts of the same kind as a symbol table.
That is the arrangement `COCOA-10.11-SURFACE-PLAN.md` §2.1 commits to ("the recipe and the generated name manifest,
which is a list of facts (names, versions, selectors), not Apple's expression of them"). No declaration, comment,
availability annotation, nullability or line of Apple's prose is copied into this directory.

`foundation-manifest.txt` — 220 classes, 40 protocols, 185 C functions, 3,763 declared selectors, 1 iOS-only class,
9 `NS_UNAVAILABLE` selectors, and **969 availability facts** (109 class-level, 860 selector-level) carrying Apple's
introduction and deprecation tokens verbatim.

## Why 10.11

10.11 is the target `COCOA-10.11-SURFACE-PLAN.md` commits to: the last SDK before the Swift 3 renaming, whose
Objective-C names are the ones this tree's clients already spell, and the newest point at which the four frameworks'
surfaces are still recognisably Cocoa.

**This directory does not replace `api/10.6/`.** The two answer different questions. 10.6 is the reference
`Foundation.h` names, and `tests/api-10.6-census.txt` pins what a 10.6 caller could reach — it is complete (173 of 173
classes, 2,840 of 2,840 selectors) and stays that way. 10.11 is the surface the Cocoa plan promises, and
`tests/api-10.11-census.txt` pins how much of it exists. `Foundation.h`'s 10.2 baseline (§11.0) is a third rule: it
governs what may be *removed*. Three denominators, three questions.

## The grammar

One fact per line, sorted:

```
class <Name> : <Superclass>          an empty superclass is `-` (a root class)
selector <Class> <selector>          the class declares this door (categories merged)
protocol <Name>
function <Name>                      a C function; inline doors are exempt from being symbols
ios-class <Name>                     declared by this SDK, but NS_CLASS_AVAILABLE(NA, …) on macOS
unavailable-selector <Class> <sel>    declared with NS_UNAVAILABLE — a door a caller must not send
class-era <Name> <introduced> <deprecated>        Apple's tokens, `-` for no deprecation
selector-era <Class> <sel> <introduced> <deprecated>
```

**The last four exist because a name list is not the surface.** `ios-class` and `unavailable-selector` are disposals
that would otherwise be charged as gaps. The two `era` kinds are the S2 tier: the version tokens `10_6` and `-` are
facts of the same kind as a name, and committing them is what lets the availability gate run without an SDK checkout —
the alternative, a sweep annotated from memory, is the drift `FOUNDATION-10.11-PLAN.md` §4.12 forbids.

Protocols carry no availability fact: the 10.11 headers do not annotate protocols — Apple annotates the classes and
lets conformance inherit the era.

## Regenerating the manifest

Needs network access and a local checkout of the 10.11 SDK headers. Nothing is installed into the tree except the
manifest.

```sh
BASE=https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.11.sdk/System/Library/Frameworks
mkdir -p /tmp/sdk1011/Foundation

# the 10.11 frameworks put their headers in Versions/C/Headers. `Headers` is a SYMLINK there, and a GitHub contents
# listing of it returns one entry ("Headers"), so the versioned path is what is requested.
curl -s "https://api.github.com/repos/phracker/MacOSX-SDKs/contents/MacOSX10.11.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers" \
  | python3 -c 'import json,sys; [print(x["name"]) for x in json.load(sys.stdin) if x["type"]=="file"]' \
  > /tmp/sdk1011/Foundation.names
cat /tmp/sdk1011/Foundation.names | xargs -P 12 -I{} curl -s -o "/tmp/sdk1011/Foundation/{}" \
  "$BASE/Foundation.framework/Versions/C/Headers/{}"

../../libagora-app/tools/api-ledger manifest /tmp/sdk1011/Foundation > api/10.11/foundation-manifest.txt
```

**Only the Foundation directory is passed**, unlike the AppKit manifest, which passes Foundation second to decide
ownership. The 10.6 note applies unchanged: excluding a class another framework declares primarily would drop
`NSFileWrapper`, which 10.11 still ships in AppKit and this tree implements in Foundation.

## Using it

```sh
# the measurement (the built library is an input: a declaration is not a door)
../../libagora-app/tools/api-ledger census api/10.11/foundation-manifest.txt . \
  --library build/libagora-base.so --include ../libagora-core/include

# what is absent, by class and selector, plus the exemptions
../../libagora-app/tools/api-ledger missing api/10.11/foundation-manifest.txt . \
  --library build/libagora-base.so --include ../libagora-core/include

# the developer-facing shortcut; the build gate is `foundation-api-10.11-census`
../../libagora-app/tools/api-ledger check api/10.11/foundation-manifest.txt . \
  tests/api-10.11-census.txt --library build/libagora-base.so --include ../libagora-core/include
```

`check` fails on a metric that moved, appeared or vanished, and on a present+missing arithmetic that no longer adds up.
Changing the pin is therefore a deliberate act in the same commit that says which wave moved it.

## The measured position

Pinned 2026-10-25, the first pin that does not contain the extractor's faults:

| Unit | 10.11 | local | missing |
|---|---:|---:|---:|
| classes (macOS) | 219 | 193 | **26** |
| protocols | 40 | 30 | **10** |
| selectors on classes the tree has | 3,407 | 3,296 | **111** |
| C functions | 182 | 182 | **0** |
| annotated declarations (S2) | 802 | 0 | **802** |

The annotation row is its own census (`tests/api-10.11-annotations.txt`, gate `foundation-api-availability`): the
macros became real in the same slice that made the row measurable. A declaration stating a version Apple does not
fails the gate outright; the 802 is the sweep's work list and may only fall.

**Everything missing is 10.8–10.11** — 0 owed from 10.6. The remaining work is staged in `FOUNDATION-10.11-PLAN.md`;
the 111 selectors are 11 `-initWithCoder:` doors (one `NSCoding` conformance decision) and 100 individual doors
(appendix C of that plan).

## Three faults the first pass contained

Each produced a plausible wrong answer, each is fixed in `../../libagora-app/tools/api-ledger`, and each has a
regression case in `api-ledger selftest`:

1. **A property's trailing annotation was read as its name — or made the property disappear.** The reader took the
   last identifier of `@property (readonly) ObjectType firstObject NS_AVAILABLE(10_6, 4_0);`, which ends in `)` and so
   matched nothing: **299 property accessors were never in the manifest at all**, and the census never charged them.
   The seven properties ending in a bare macro (`NS_RETURNS_INNER_POINTER`) went the other way and were recorded as a
   selector with that name. One regex, two failure directions, 306 doors mis-measured.
2. **A string literal was read as syntax.** `NS_DEPRECATED(…, "Use [NSURLSession dataTaskWithRequest:completionHandler:]
   …")` is inside the declaration's own span, so two `NSURLConnection` doors were charged under concatenated names
   that exist nowhere. String literals are now blanked before a declaration is read.
3. **Availability was not a fact.** `NA` and `NS_UNAVAILABLE` could not be told apart from absent, which is exactly
   where the phantom class and two phantom selectors came from. Both are manifest facts now.
