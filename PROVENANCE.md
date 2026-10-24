# Provenance

`libagora-base` is Foundation for Agora. Its source is taken from the Foundation that lives in the
Fiwix tree, where it was written as a standalone Objective-C Foundation.

| | |
|---|---|
| Source | `../Fiwix/userland/Foundation` |
| Source revision | Fiwix `df3147a451e88d8d2256537e6d6dcdf69471695f` (2026-10-10) |
| Extraction date | 2026-10-10 |
| Extraction | the whole `userland/Foundation` tree, verbatim — 315 files (144 `.m`, 170 `.h`) |
| Licence | LGPL-3.0-or-later for the library, GPL-3.0-or-later for `tests/` (per the per-file headers; see `LICENSE`) |

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
are recorded above. `libagora-base/tests/bridges.m` is the instrument: **76 cases**, each type in both
directions, the mutable ones from both APIs, a type Foundation never bridges (a `CFUUIDRef` is an
object, an `NSArray` holds it, and its `CFHash`/`CFEqual` stay Core Foundation's), plus Core Foundation
asking Foundation objects for a stream error, for calendar arithmetic and for the doors a surface survey
found missing.

**NOT BRIDGED, AND THE TWO REASONS ARE DIFFERENT — MEASURED, BOTH WAYS, RATHER THAN ASSUMED:**

- **Pairs that exist on both sides and are still not bridged**: `libagora-core` has `CFBundle.c`,
  `CFSocket.c` and `CFUUID.c`, and this Foundation has `NSBundle`, `NSSocketPort` and `NSUUID`, but no
  registration in `NSCFBridging.m` names one for the other — so a `CFUUIDRef` is a Core Foundation object
  and not an `NSUUID *`, and it is the type `reg_unbridged_type` uses to prove the generic class.
  (`CFMachPort` and `CFMessagePort` do not exist in `libagora-core` at all, so `NSMachPort` and
  `NSMessagePort` cannot be bridged without writing that half first.)
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

### KVO's automatic half

**The v1 registry announced KVC's writes and not a setter called directly.** `-setValue:forKey:` wrapped its own
write in the will/did pair, so a model was observable only when it was written THROUGH KVC; application code writes
`[model setName:x]`, and that was invisible. This slice is Cocoa's answer to the same problem: the first observation
of a simple key moves the object to a dynamic subclass, `NSKVONotifying_<Class>`, allocated with
`objc_allocateClassPair` and given an override of the key's setter. The override announces the change, calls the
original IMP through a function pointer typed for the argument, and announces the end. `-class` is overridden to keep
answering the declared class, which is the one lie Cocoa's KVO tells and the reason a caller cannot see the move.

**THE WRAPPER EXISTS ONCE PER (CLASS, KEY), AND THE TYPED FUNCTIONS ARE THE ABI.** A wrapper cannot be a variadic
trampoline, so there is one C function per argument type this tier can carry — object/class, `char`/`BOOL`, `short`,
`int`, `long`, `long long`, `float`, `double` — chosen from the setter's argument encoding. A STRUCT, a pointer, a
C string or a selector is deliberately NOT wrapped (that would mean an ABI for every type), and a key with no setter
has nothing to wrap; both fall back to the manual pair, and KVC's writer still announces its own write once. Dotted
key paths are not decomposed for automatic notification, and dependent keys
(`+keyPathsForValuesAffectingValueForKey:`) are not computed yet; both are named in the header.

**AND THE TWO ANNOUNCERS ASK EACH OTHER RATHER THAN BOTH SPEAKING.** KVC's `-setValue:forKey:` now asks an internal
C seam, `fn_kvo_auto_notifies`, whether the object's class carries the automatic setter for that key. When it does,
the setter announces and KVC stays quiet; when it does not, KVC wraps the write itself. That is what keeps one write
to one notification regardless of the door it came through — the defect the probe's "a KVC write announces exactly
once after observation" case exists to catch.

`tests/kvo_automatic.m` is the instrument: **34 cases**, the class lie, an object setter and every scalar wrapper, the
old/new/context dictionary, Prior's two-sided pair, Initial, the one-announcement rule for KVC, the ivar-only key,
the unwrapped struct with the manual fallback, two observers with both removal spellings, the exception for removing
what was never registered, an unobserved instance of the same class, and the silent-but-usable state after the last
observer is removed.

### KVC's live collection proxies and KVO's to-many pair

**A binding controller has to see items arrive and leave, and KVO's setting half cannot see that.** The array proxy
is built on the seven storage primitives `NSMutableArray` documents (count, objectAtIndex, insert, remove,
removeAll, replace, and the fast-enumeration word); the set proxy on the set's single `-fnReplaceMembers:` primitive,
whose new member list is diffed to recover what was added and removed. Both read and write through
`-valueForKey:`/`-setValue:forKey:`, so the proxy is a view of the property rather than a snapshot of it.

**THE ARM THAT RUNS DEPENDS ON THE BACKING VALUE, AND BOTH ARE HONEST.** A property already holding an
`NSMutableArray`/`NSMutableSet` is mutated in place, wrapped in the to-many pair; a property whose value is immutable
is replaced by a mutable copy through KVC, which is a setting change. A nil property is created by the first
insertion the same way and is in place from the second. The change dictionary carries the kind
(Insertion/Removal/Replacement), the indexes (array forms) and the affected objects — **retained by the pending
record, because a removal frees the objects it took out before the `did` half runs** — with NSNull for the side that
does not exist (an insertion's OLD, a removal's NEW).

**THE SET FORM CARRIES NSSETS, NOT ARRAYS**, and maps its mutation to a kind: union is an insertion, minus and
intersect are removals, set is a replacement. The ordered-set proxy is the remaining row and is named in both headers.

`tests/kvo_tomany.m` is the instrument: **37 cases**, the four array mutations with their index sets and OLD/NEW
objects, Prior's before-notification, the immutable and nil-property arms, the set's union/removal with NSSet values,
a dotted key path whose notification belongs to the head object, and an unobserved proxy that still mutates.

**AND THE PROXY'S NIL WRITE FOUND A KVC DEFECT.** `-setValue:nil forKey:` refused every nil BEFORE it asked the
setter's argument type, so an `id` property with a perfectly good `-setFoo:` raised "cannot set nil for the scalar
key" — the message naming a scalar the property was not. The type is now asked first: an object/Class/pointer/block
setter receives nil, a scalar still goes to `-setNilValueForKey:`. The binding layer's `NSNullPlaceholderBindingOption`
is the caller that measured it, and `tests/kvo_automatic.m` keeps the case.

### The settings store announces its keys

**A KEY IN `NSUserDefaults` HAS NO SETTER, SO KVO'S AUTOMATIC HALF CANNOT SEE IT.** The store's write door is
`-setObject:forKey:`, and `fn_install_auto_kvo` wraps a `-setFoo:` that does not exist. The announcement therefore has to
be the store's own: the per-key doors send `-willChangeValueForKey:`/`-didChangeValueForKey:` around the write. Two
consequences shaped the code, and both are recorded because each is a trap that a later reader would otherwise undo:

* **The pair is OUTSIDE `_lock`.** The `will` half reads the old value when an observer asked for Old or Prior, and
  `-objectForKey:` takes `_lock` itself; `_lock` is an `NSLock`, which is not recursive, so announcing while holding it
  deadlocks. The shape is will (unlocked, old value) → lock/write/unlock → did (unlocked, new value), with the `did`
  in a `@finally` so a write that raises still closes the bracket — an unpaired `will` leaves a pending change in the
  registry for the life of the object.
* **A KVC WRITE MUST NOT BE ANNOUNCED TWICE.** `NSObject`'s `-setValue:forKey:` announces its own writes when the key
  has no wrapped setter. `NSUserDefaults` therefore implements `-setValue:forKey:` itself, calling the store's write
  directly, so the store is the only announcer. `-valueForKey:` is its counterpart and is not optional: KVO fills the
  change dictionary's Old and New values with it, and without it an observation of an arbitrary key would raise from
  `-valueForUndefinedKey:` while the dictionary was being built.

**ANNOUNCING EXACTLY WHAT CHANGED.** `-removeObjectForKey:` checks presence first, because removing a key that was
never there is not a change. `-registerDefaults:` announces only the keys whose EFFECTIVE value moves: a key any domain
ahead of `NSRegistrationDomain` supplies keeps that domain's value (so a registration for it is silent), and a key with
no other source changes only when the registered value differs from the one already registered. Both halves are asked
BEFORE the merge, because the `will` half has to precede it, and the merge itself happens under the lock between the two
halves. **The whole-domain doors do not announce** — `-setPersistentDomain:forName:`, `-removePersistentDomainForName:`,
the volatile pair and the suite pair — because attributing a key to a domain is a question the store answers internally
and does not expose; the header says so at the class rather than leaving a caller to discover it.

`tests/user_defaults_kvo.m` is the instrument: **25 cases**, one notification per writing door, the KVC write's single
announcement, `NSNull` for an absent old value, the removal of an absent key's silence, the registration's
effective-value rule (new, same, replaced, shadowed), the non-property-list refusal's silence, two observers with one
removed, and Prior's two-notification bracket. The probe points the store at a scratch root with `FNX_CONFIG_ROOT`, so
it touches nothing in the image.
