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

**Made, INCLUDING THE MUTABLE HALF.** `CFStringRef`/`NSString *` and the seventeen other shared types are
one object each, and so are the MUTABLE forms of seven of them (`CFMutableArray`, `CFMutableDictionary`,
`CFMutableSet`, `CFMutableString`, `CFMutableData`, `CFMutableCharacterSet`, `CFMutableAttributedString`).
The mechanism, the parts of the original plan that were superseded and why, and the doors that came back
are recorded above. `libagora-base/tests/bridges.m` is the instrument: **74 cases**, each type in both
directions, the mutable ones from both APIs, plus Core Foundation asking Foundation objects for a stream
error, for calendar arithmetic and for the doors a surface survey found missing.

**NOT BRIDGED, AND THE TWO REASONS ARE DIFFERENT — MEASURED, BOTH WAYS, RATHER THAN ASSUMED:**

- **Foundation classes with no Core Foundation counterpart in this tree**: `NSBundle`, `NSMachPort`,
  `NSMessagePort`, `NSSocketPort` and `NSUUID` are all here, and there is no `CFBundle`, `CFMachPort`,
  `CFMessagePort`, `CFSocket` or `CFUUID` in `libagora-core` for them to be one object *with*. Nothing
  is missing here that could be added without writing the Core Foundation half first.
So the bridge covers the eighteen types the two libraries share — plus their mutable forms where the type
has one — and saying "everything is bridged" would overstate it in that direction.

**AND TWO THINGS ARE BRIDGED IMPERFECTLY, RECORDED RATHER THAN LEFT. THE BOOLEANS WERE, AND ARE NOT ANY
MORE:** this section used to say that `kCFBooleanTrue`/`kCFBooleanFalse` "change hands as nothing", with no
class registered for the type. THAT IS NO LONGER TRUE AND THE LINE IS GONE: the type now has an owned class
of its own (`__NSCFBoolean`), `[NSNumber numberWithBool:]` reports CFBoolean's type id, a Boolean's
`-agKind` answers Apple's `'c'`, and the suite holds `CFBooleanGetValue(@YES)`, `[kCFBooleanTrue boolValue]`
and `[kCFBooleanTrue isEqual:@YES]` as cases.

- **Character sets now reach all seventeen planes, WHICH THEY DID NOT.** This bullet used to say the type
  was BMP-only and that a Core Foundation set spanning planes lost everything above plane 0 on the way into
  a Foundation-owned set. That is FIXED: the decoder reads Core Foundation's full form, both plane doors
  answer for the whole code space, and `-bitmapRepresentation` emits the full form when a set needs it --
  measured by taking Core Foundation's bitmap for a set holding `'a'` and `U+1F600` (16385 bytes), rebuilding
  a Foundation set from those bytes, and finding Core Foundation's bitmap for the result is
  **byte-identical**, with the superset test passing BOTH ways. A case in the suite holds all of it --
  `Core Foundation's bitmap annex planes survive a round trip` -- and disabling the decoder's annex walk
  fails it five ways, including the original symptom `rebuilt covers: NO`.
- **Seven `incorrect signature` reports remain** (all pointer-only differences, audited at the rows in
  `libagora-core/internalInclude/CFBridgedMethods.h`). Whether libobjc2 installs a trampoline for a
  pointer-only difference is **not measured**.
- **The calendar doors carry five recorded deviations**, each written at the code that deviates.
