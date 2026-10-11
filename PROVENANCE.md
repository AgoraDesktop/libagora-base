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

Agora **has** CoreFoundation (`libagora-core`), and `libagora-base` bridges them: `CFStringRef` and
`NSString *` are the same object, and likewise `NSArray`/`CFArray`, `NSDictionary`/`CFDictionary`,
`NSSet`/`CFSet`, `NSNumber`/`CFNumber`, `NSData`/`CFData`, `NSDate`/`CFDate` and the other eleven
types Core Foundation and this Foundation share.

**AND NOT BY THE ROUTE THIS SECTION ORIGINALLY PLANNED, WHICH IS WORTH RECORDING.** The plan was the one
`libagora-core` was imported carrying: populate CF's `__CFSwiftBridge` structs (`_NSObjectBridge`,
`_NSArrayBridge`, …) so Core Foundation calls through a table of function pointers. That mechanism is
Swift's, and this build is Objective-C: `CFInternal.h` compiles the Swift bridge out. What was built
instead, and measured, is:

- **Core Foundation's objects wear an Objective-C class.** `CFRuntime.c` holds a table that maps each CF
  type to the class name Core Foundation's own objects should carry and to the handful of primitives
  that answer for it (`-length`, `-objectAtIndex:`, `-host`, …), and builds each class at first use.
  A `CFStringRef` then answers `-length` directly, and Core Foundation's own doors refuse to dispatch
  into it, which is what keeps the two sides from calling each other in circles.
- **Core Foundation is told which class each CF type is**, via `_CFRuntimeBridgeTypeToClass` — the one
  piece of the original plan that survived, and the reason a CF-created object and an `NSString *` are
  one object.
- **This Foundation answers Core Foundation's private doors.** Every bridged class here answers the
  doors Core Foundation sends at it — some are primitives (`-host` for `CFURLCopyHostName`, the byte
  doors for `CFStringGetBytes`), and the rest of the class's methods were routed through those
  primitives so that the derived machinery works from Core Foundation's storage too.
- **The reference count is Core Foundation's**, so `CFRetain`/`CFRelease` and `-retain`/`-release` move
  one count; and the encoding at issue between the two libraries is converted, never cast
  (`kCFStringEncodingUTF8` is `0x08000100` where `NSUTF8StringEncoding` is `4`).
- **The CF-facing doors the Fiwix tree removed came back as far as they can.** `CFFileSecurity` is
  here (`NSFileSecurity.h`/`.m`). `-[NSRunLoop getCFRunLoop]` is still not, and for a stated reason
  rather than an omission: this Foundation's run loop is its own, so a `CFRunLoopRef` returned from it
  would not be the same loop Core Foundation hands out for the thread, which is Apple's contract
  (`NSRunLoop.h` records it).

What is verified — 63 cases in `tests/bridges.m`, every registered type in both directions plus the
forward direction — and what is deliberately not bridged (the CF types this Foundation does not
register, `CFBoolean`'s constants among them) are recorded under **Toll-free bridging** below.

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

**Made.** `CFStringRef`/`NSString *` and the seventeen other shared types are one object each; the
mechanism, the parts of the original plan that were superseded and why, and the doors that came back
are recorded above. `libagora-base/tests/bridges.m` is the instrument: 63 cases, each type in both
directions, plus Core Foundation asking Foundation objects for a stream error and for calendar
arithmetic.

**NOT BRIDGED, AND THE TWO REASONS ARE DIFFERENT — MEASURED, BOTH WAYS, RATHER THAN ASSUMED:**

- **Foundation classes with no Core Foundation counterpart in this tree**: `NSBundle`, `NSMachPort`,
  `NSMessagePort`, `NSSocketPort` and `NSUUID` are all here, and there is no `CFBundle`, `CFMachPort`,
  `CFMessagePort`, `CFSocket` or `CFUUID` in `libagora-core` for them to be one object *with*. Nothing
  is missing here that could be added without writing the Core Foundation half first.
- **Core Foundation constants with no class of their own**: `kCFBooleanTrue`/`kCFBooleanFalse` are
  what Core Foundation returns where an `NSNumber` might have been expected, and no class is registered
  for the type, so neither object changes hands as the other.

So the bridge covers the eighteen types the two libraries share, and saying "everything is bridged"
would overstate it in each of those two directions.
