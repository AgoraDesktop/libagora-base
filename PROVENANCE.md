# Provenance

`libagora-base` is Foundation for Agora. Its source is taken from the Foundation that lives in the
Fiwix tree, where it was written as a standalone Objective-C Foundation.

| | |
|---|---|
| Source | `../Fiwix/userland/Foundation` |
| Source revision | Fiwix `df3147a451e88d8d2256537e6d6dcdf69471695f` (2026-10-10) |
| Extraction date | 2026-10-10 |
| Extraction | the whole `userland/Foundation` tree, verbatim — 315 files (144 `.m`, 170 `.h`) |
| Licence | MIT, © 2026 Kyle J. Cardoza (per the per-file headers; see `LICENSE`) |

Fiwix had no working-tree changes under `userland/Foundation` when this was taken, so the import
matches that revision exactly.

## Why it is being changed

The Fiwix Foundation was written **without CoreFoundation**, deliberately. `NSRunLoop.h` says *"this
system has NO CoreFoundation, so there is nothing for them to answer"*; `NSFileSecurity.h` says it
*"HAS NO COREFOUNDATION — no `CFFileSecurity`, no `CFUUID`, no CoreFoundation family at all"*; and the
value types are standalone (`NSString` → `NSOwnedString`, which owns its own buffer).

Agora **has** CoreFoundation (`libagora-core`), and `libagora-base` must **toll-free bridge** the
CF/NS types the way Apple's implementation does: `CFStringRef` and `NSString *` are the same object,
and likewise `NSArray`/`CFArray`, `NSDictionary`/`CFDictionary`, `NSSet`/`CFSet`, `NSNumber`/`CFNumber`,
`NSData`/`CFData` and `NSDate`/`CFDate`.

That means:

- **the bridged value classes become CF-backed** — their concrete classes are the CF objects rather
  than owning separate storage;
- **Core Foundation is told which class each CF type is**, via `_CFRuntimeBridgeTypeToClass` (already
  declared by `libagora-core` in `include/ForSwiftFoundationOnly.h`), so a CF-created object and an
  `NSString *` are one object;
- **CF's `__CFSwiftBridge` structs are populated** (`_NSObjectBridge`, `_NSArrayBridge`, …) so CF
  dispatches to the Objective-C implementation when it is handed an NS object;
- the CF-facing doors the Fiwix tree removed — `-[NSRunLoop getCFRunLoop]`, the `CFFileSecurity`
  family — can come back, answering against Agora's CoreFoundation.

## Agora changes

### The build

- **the property-list core came with it** — Foundation's `NSPropertyListSerialization` includes
  `<plist.h>` and links a C file that sits *beside* the Foundation in the Fiwix tree, not inside it:
  `userland/plist.c` and `include/plist.h` were copied in, and `plist.c` is compiled as part of the
  library;
- **every `.m` in the directory is compiled** — the source list is a directory glob, as Fiwix's own
  build generates its Foundation rules ("one rule per source from the directory listing"). Fiwix's
  curated subset left undefined symbols in the library (`NSDecimal*`, `NSAutoreleasePool`,
  `NSNotificationCenter`, the `NSURLAuthenticationMethod*` constants);
- **the dependencies are**: `libagora-objc` (the Objective-C runtime), `libagora-core` (Core
  Foundation), `libagora-dispatch`, the system ICU, zlib and **libcurl** (for
  `NSURLConnection`/`NSURLSession`);
- **`<CoreGraphics/…>` resolves through an include shim** onto the sibling `libagora-drawing`
  component. Foundation needs Core Graphics' *geometry types* only (structs plus the `CG_INLINE`
  makers), so that component is not linked.

Verified: the library builds with clang (0 errors), and an Objective-C smoke test using
`NSString`/`NSArray`/`NSAutoreleasePool` links against it and runs.

### Toll-free bridging

Not yet made — this section records it as it lands.
