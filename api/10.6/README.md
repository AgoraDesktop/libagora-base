# api/10.6 — the committed facts of Apple's 10.6 Foundation

**The SDK is not here, and must not be.** Apple's headers are not redistributable. What is here is a **name
manifest**: class names with their superclasses, protocol names, selector names per class, and C function names —
facts of the same kind as a symbol table, which is the arrangement `COCOA-10.11-SURFACE-PLAN.md` §2.1 commits to
("the recipe and the generated name manifest, which is a list of facts (names, versions, selectors), not Apple's
expression of them"). No declaration, comment, availability annotation, nullability or line of Apple's prose is
copied into this directory.

`foundation-manifest.txt` — 173 classes, 23 protocols, 183 C functions, 2,840 declared selectors.

## Why 10.6

`Foundation.h` names 10.6 as this library's reference, and `tests/api-10.6-census.txt` as the measurement of it.
Until this directory existed, both statements pointed at nothing: the reference was prose and the census file had
never been in the tree. 10.6 is also the denominator the AppKit tier uses (`../libagora-app/api/10.6/`), and the
10.11 SDK is a **new** reference rather than a replacement — measuring against it charges this tier for classes and
selectors that only exist in 10.7–10.11 and that no slice has promised. The plan's own §0 finding is that the gap is
overwhelmingly the 10.6 surface this tree never finished.

**One dimension is deliberately not resolved here.** `Foundation.h` also records a 10.2 baseline (§11.0) that was
used to decide removals. A baseline is a rule about what may be *taken out*; it is not a denominator for what a
caller can *reach*. The census therefore measures the whole 10.6 surface and pins the 10.3–10.6 additions as debt,
so that re-admitting or refusing each one is a decision with a number attached rather than an omission.

## Regenerating the manifest

Needs network access and a local checkout of the 10.6 SDK headers. Nothing is installed into the tree except the
manifest.

```sh
BASE=https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.6.sdk/System/Library/Frameworks
mkdir -p /tmp/sdk106/Foundation

# the 10.6 frameworks put their headers in Versions/C/Headers; `Headers` is a symlink to it
curl -s "https://api.github.com/repos/phracker/MacOSX-SDKs/contents/MacOSX10.6.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers" \
  | python3 -c 'import json,sys; [print(x["name"]) for x in json.load(sys.stdin) if x["type"]=="file"]' \
  > /tmp/Foundation.names
cat /tmp/Foundation.names | xargs -P 12 -I{} curl -s -o "/tmp/sdk106/Foundation/{}" \
  "$BASE/Foundation.framework/Versions/C/Headers/{}"

../../libagora-app/tools/api-ledger manifest /tmp/sdk106/Foundation > api/10.6/foundation-manifest.txt
```

**Only the Foundation directory is passed, unlike the AppKit manifest, which passes Foundation second to decide
ownership.** That parameter removes classes another framework declares *primarily*; here it would drop
`NSFileWrapper`, which 10.6 ships in AppKit and this tree implements in Foundation. The AppKit manifest already
carries that class and its census charges it there, so excluding it here would make one real class invisible in both
ledgers instead of charging it twice. Every other name in this manifest is declared by Apple's Foundation.

## Using it

```sh
# the measurement (the built library is an input: a declaration is not a door)
../../libagora-app/tools/api-ledger census api/10.6/foundation-manifest.txt . \
  --library build/libagora-base.so --include ../libagora-core/include

# what is absent, by class and selector
../../libagora-app/tools/api-ledger missing api/10.6/foundation-manifest.txt . \
  --library build/libagora-base.so --include ../libagora-core/include

# the gate the build runs, against the pinned census
ctest -R foundation-api-census --output-on-failure
```

`--include` is not optional for Foundation: `NSMakeRange`, `NSMaxRange` and `NSLocationInRange` are inline doors
declared in `libagora-core/include/CFBridgingTypes.h` and reached through `NSObjCRuntime.h`. Without it the ledger
compares this directory's headers against the manifest and reports two of them as functions with no symbol.

## What the census does and does not say

It says how many names a caller can reach, with inheritance resolved and `@property` expanded, and it treats a
**declaration** as reachable even when no body implements it — that is the AppKit convention, and the separate
`methods-declared-not-implemented` metric is what holds the write side. It does not say a door behaves. That is the
plan's M2 tier, and `tests/bridges.m` plus the rest of this suite is where behaviour is measured.

A **refusal in prose is not a door.** `NSAffineTransform.h` and `NSXMLNode.h` say what they do not do, and the census
counts those selectors absent until a body answers them (by raising, if that is the honest answer). The pin is
`methods-declared-not-implemented` **0**: the refusals that used to owe a body now raise by name (`NSXMLNode`), or are
implemented by the companion framework and counted in `methods-external` (`NSAffineTransform`'s three). When this
paragraph was first written it said 5, and 5 was the number of doors that still owed one.

## The 10.11 sibling

This directory is one of two denominators. `../10.11/` holds the facts of Apple's 10.11 Foundation and
`../../tests/api-10.11-census.txt` pins what the tree answers of the surface `COCOA-10.11-SURFACE-PLAN.md` commits to.
The 10.6 pin stays because it answers a different question — a 10.6 door that disappears — and neither supersedes the
other; `Foundation.h`'s 10.2 baseline (§11.0) is a third rule, about what may be removed.
