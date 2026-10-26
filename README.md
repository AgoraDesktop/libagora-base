# libagora-base

**Foundation for Agora** — the Objective-C class library of Agora's Cocoa-compatible stack:
`NSObject`, the value types (`NSString`, `NSNumber`, `NSData`, `NSDate`), the collections
(`NSArray`, `NSDictionary`, `NSSet`, …), `NSError`/`NSException`, `NSURL`, the property-list and
JSON codecs, and the rest of Foundation.

Agora is an installable desktop environment for Linux and BSD; see the project README in the parent
directory (`../README.md`). `libagora-base` sits on `libagora-core` (Core Foundation).

## Provenance

Taken from the Foundation in the Fiwix tree (`../Fiwix/userland/Foundation`), where it was written as
a standalone Objective-C Foundation on libobjc2 — deliberately **without** CoreFoundation. See
[`PROVENANCE.md`](PROVENANCE.md) for the exact revision and what is being changed.

## Status

**Imported, building, running, and toll-free bridged to `libagora-core`.**

**AND THE RUN LOOP IS `libagora-core`'S, WHICH IS THE BRIDGE THAT MATTERED MOST.** `NSRunLoop` used to be its own
implementation — a timer array, an fd-source array and a `select(2)` wait — with `-getCFRunLoop` raising, because
Core Foundation's loop was a different loop. It is now a façade: an `NSTimer` owns a `CFRunLoopTimer`, an fd source
is a `CFRunLoopSource` whose readiness a `dispatch_source` reports (so `NSFileHandle`'s background reads fire, on the
loop's thread), a performer is one signalled source in the common modes, and the notification queue's two phases are
a `CFRunLoopObserver` at BeforeWaiting. The waiting is Core Foundation's, which means the main dispatch queue's port
is watched by the same wait: `dispatch_async(dispatch_get_main_queue(), ^{…})` runs on the next pass of an
application's loop, and `dispatch_source` on a descriptor works. Two measured consequences are recorded in place
rather than left to be found: a LISTENING socket is a source now (epoll reports it; `select(2)` never did), and a
REGULAR FILE is refused as one because a readiness source is ALWAYS ready for it (9673 firings in 400 ms), which is
a busy loop rather than a notification. `tests/runloop_cf.m` holds all of it to its contract.

**Zones are implemented.** `NSZone` is an opaque allocator handle (`NSZone.h`), with
`NSCreateZone`, `NSZoneMalloc`/`Calloc`/`Realloc`/`Free`, `NSZoneName` and
`NSZoneFromPointer`; `NSAllocateObject` records the zone an object was allocated in, and
`-zone`/`-setZone:` report it. Apple ignores zones for object allocation on 64-bit runtimes,
and so does the runtime here (it has one heap); the C allocator and the identity are real.
Cocoa's copying protocol is restored in its published shape: `-copyWithZone:` and
`-mutableCopyWithZone:` are the override points, and `-copy`/`-mutableCopy` delegate to them
with a NULL zone. `tests/zones.m` measures the whole contract.

1. **The build is wired and verified.** Every `.m` in the directory is compiled (a directory glob, as
   Fiwix's own build generates its rules) with clang, plus `plist.c` — the property-list core that
   lives beside the Foundation in the Fiwix tree (`../Fiwix/userland/plist.c`, header
   `../Fiwix/include/plist.h`). It links against `libagora-objc` (the Objective-C runtime),
   `libagora-core` (Core Foundation), `libagora-dispatch`, the system ICU, zlib and libcurl, and Core
   Graphics' headers come from the sibling `libagora-drawing`. An Objective-C smoke test using
   `NSString`/`NSArray`/`NSAutoreleasePool` links and runs.
2. **Toll-free bridging is made.** `CFStringRef` and `NSString *` *are the same object*, and so are
   the other seventeen types the two libraries share: `CFArray`/`NSArray`, `CFData`/`NSData`,
   `CFDictionary`/`NSDictionary`, `CFSet`/`NSSet`, `CFNumber`/`NSNumber`, `CFDate`/`NSDate`,
   `CFNull`/`NSNull`, `CFURL`/`NSURL`, `CFTimeZone`/`NSTimeZone`, `CFLocale`/`NSLocale`,
   `CFError`/`NSError`, `CFAttributedString`/`NSAttributedString`,
   `CFCharacterSet`/`NSCharacterSet`, `CFCalendar`/`NSCalendar`, `CFReadStream`/`NSInputStream`,
   `CFWriteStream`/`NSOutputStream` and `CFRunLoopTimer`/`NSTimer`. The bridge is four mechanisms,
   each measured rather than assumed:

   - **Core Foundation's own objects wear an Objective-C class**, built from a table in
     `libagora-core/CFRuntime.c`, so a `CFStringRef` Core Foundation created answers `-length` and a
     `CFURLRef` answers `-host`; **and a type Foundation does not bridge at all wears `__NSCFType`**,
     Apple's generic class, so a `CTFontRef`, a `CGColorSpaceRef` or a `CFUUIDRef` is an object
     Foundation can hold in an `NSArray` or an `NSDictionary` — before this it had NO class, and
     `-setObject:forKey:` died in `objc_retain` on a null isa;
   - **Core Foundation's own doors keep Core Foundation's own callbacks**, so `CFHash`, `CFEqual` and
     `CFCopyDescription` on a `CFUUIDRef` or a `CTFontDescriptorRef` answer from the type's own
     `hash`/`equal`/`copyDebugDesc` rather than NSObject's pointer identity. A BRIDGED owned class is
     the exception and must be: `__NSCFString` *is* an `NSString`, and `CFHash` has to reach
     Foundation's `-hash` for the toll-free agreement to hold;
   - **the CF-facing doors are answered by this Foundation**, including the ones whose signatures Core
     Foundation's own numbering makes easy to get wrong (the byte doors, which are handed a
     `CFStringEncoding` where Cocoa expects an `NSStringEncoding`) and the calendar's three varargs
     doors, which upstream only Swift's bridge implements;
   - **the reference count in force is Core Foundation's**, so `CFRetain`/`CFRelease` and
     `-retain`/`-release` move one count rather than two.

   **and the MUTABLE half of seven of them is bridged too** — `CFMutableArray`,
   `CFMutableDictionary`, `CFMutableSet`, `CFMutableString`, `CFMutableData`, `CFMutableCharacterSet` and
   `CFMutableAttributedString`. Each needed a second owned class, chosen at CREATION from the category its
   constructor passes, because a mutable and an immutable object share one type id; and Foundation's side
   had to be made to read through its own storage doors rather than its fields, which is where the same
   defect kept appearing.

   Verified by `tests/bridges.m`: **76 cases**, every one of the eighteen types in both directions, the
   seven mutable ones from both APIs, a type Foundation never bridges, and — a direction nothing had
   tested before — Core Foundation
   asking a *Foundation* object (`CFReadStreamGetError`, `CFCalendarDecomposeAbsoluteTime`,
   `CFCalendarComposeAbsoluteTime`, `CFCalendarAddComponents`, `CFDictionaryContainsKey` and the rest of
   the doors a surface survey found missing). `PROVENANCE.md` records both what is deliberately *not*
   bridged and what is bridged imperfectly.

3. **The Swift-facing names and shapes are being aligned with Darwin.** The importer takes a class's
   Swift name from `NS_SWIFT_NAME` on the `@interface`, so 28 classes that Darwin renames are
   annotated (`NSBundle` -> `Bundle`, `NSBlockOperation` -> `BlockOperation`, `NSFileHandle` ->
   `FileHandle`, `NSOperation` -> `Operation`, `NSUserDefaults` -> `UserDefaults`, …) and Swift reads
   them under Cocoa's spelling. The same pass is making the *shapes* match where the importer's choice
   is driven by this header: `NSObject`'s `description` and `debugDescription` are properties (a
   method-shaped `description` cannot satisfy `CustomStringConvertible`), and so is `hash`. Both are
   measured, class by class, by `swift-toolchain/scripts/verify-foundation-parity.sh`, which diffs this
   library's Swift surface against the reference Foundation and gates the remaining work
   (`../SWIFT-FOUNDATION-PARITY-PLAN.md`).

4. **KVO has its automatic half.** `-addObserver:forKeyPath:options:context:` observes a simple key by moving the
   object to a dynamic subclass (`NSKVONotifying_<Class>`) whose setter brackets the original IMP with
   `-willChangeValueForKey:`/`-didChangeValueForKey:`, so `[model setName:x]` — a setter called directly, which is
   what application code writes — notifies with the kind, the old and new values, the options and the context.
   `-class` keeps answering the declared class and `-isKindOfClass:` is true; the subclass is created once per
   class and reused by every observed instance. `-setValue:forKey:` asks an internal seam whether the setter will
   announce, so a KVC write is reported EXACTLY ONCE, whichever door it came through. Object/class,
   `char`/`BOOL`, `short`, `int`, `long`, `long long`, `float` and `double` setter arguments are wrapped; **STRUCT,
   pointer, C-string and selector arguments, a key with no setter, and a dotted key path fall back to the manual
   pair**, and the header names each. The dynamic subclass is not restored when the last observer leaves: the
   wrappers then announce to an empty registry, which is a lookup rather than a crash. Measured by
   `tests/kvo_automatic.m` (**34 cases**): the class lie, every wrapped type, Prior and Initial, the
   one-announcement rule, the unwrapped struct's manual fallback, both removal spellings, and the silent-but-usable
   state after the last observer is gone.

5. **KVC's live collection proxies and KVO's to-many pair.** `-mutableArrayValueForKey:` and
   `-mutableSetValueForKey:` answer live views over a property's collection (and `…KeyPath:` walks to the
   object at the head of the path). A mutation through a proxy whose property already holds an `NSMutableArray`
   or `NSMutableSet` changes it IN PLACE and announces `-willChange:valuesAtIndexes:forKey:` /
   `-didChange:…` — kind, indexes, and the OLD/NEW objects (retained past a removal that frees them) — or, for a
   SET, `-willChangeValueForKey:withSetMutation:usingObjects:`, where union is an insertion, minus/intersect a
   removal and set a replacement. A property whose value is immutable (a computed collection, or one a getter
   copies) takes the other arm: the proxy builds a mutable copy and writes it back through KVC, so the observer
   sees the ordinary SETTING change. **The live pair is what a binding controller needs to notice items added and
   removed instead of only whole-array replacement.** Measured by `tests/kvo_tomany.m` (**37 cases**): the four
   array mutations with their index sets and old/new objects, Prior, the immutable and nil-property arms, the set
   mutations with NSSet values, the dotted path, and an unobserved proxy still mutating.
   **And `-setValue:nil forKey:` now reaches an `id` setter with nil** — the argument TYPE is asked before nil is
   refused, which the binding layer's NSNull placeholder needs; a scalar setter still raises through
   `-setNilValueForKey:`. `tests/kvo_automatic.m` holds the case.

6. **The settings store announces its keys.** `NSUserDefaults` writes through `-setObject:forKey:` and its typed
   spellings, so KVO's automatic setter wrapper — which brackets `-setFoo:` — has nothing to wrap. The per-key doors
   now send the manual `-willChangeValueForKey:`/`-didChangeValueForKey:` pair themselves, around the locked write and
   **outside** it (the lock is not recursive and the will half reads the old value through `-objectForKey:`), and
   `-valueForKey:`/`-setValue:forKey:` are the KVC spellings Apple documents for this class — a read is the store's
   lookup, a write is `-setObject:forKey:`, so a KVC write is announced by the STORE and not twice. A caller can
   observe an arbitrary key string, which is what AppKit does with `NSWindow Frame <name>`.
   **What announces, and what does not, is stated rather than implied.** `-setObject:forKey:`, the six typed setters
   (they funnel through it), `-removeObjectForKey:` (only when a value was actually there) and `-registerDefaults:`
   (only for keys whose EFFECTIVE value moves — a key an app domain already supplies is silent, and so is registering
   the value that is already registered) are the announcing doors, and each write is ONE notification. **The
   whole-domain doors do not announce** (`-setPersistentDomain:forName:`, `-removePersistentDomainForName:`, the
   volatile-domain pair and the suite pair): which keys they changed is a question answered by walking domains the
   store deliberately does not expose. A value that is not a property list is refused BEFORE the announcement, so a
   rejected write announces nothing. Measured by `tests/user_defaults_kvo.m` (**25 cases**): one notification per
   door, the KVC write's single announcement, the removed-and-absent removal, the registration's effective-value rule,
   two observers with one removed, Prior's bracket, and the rejected write's silence.

## The 10.6 surface, measured

`Foundation.h` names macOS 10.6 as this library's reference, and the reference is a number rather than a sentence.
`api/10.6/foundation-manifest.txt` holds the committed facts of Apple's 10.6 Foundation — 173 classes, 23 protocols,
183 C functions and 2,840 declared selectors, names and relationships only, because the SDK is not redistributable —
and `tests/api-10.6-census.txt` pins what this tree answers.

**173 of 173 classes, 2,840 of 2,840 selectors, 23 of 23 protocols, 180 of 180 functions.** The gate is
`foundation-api-census` in `tests/`, which runs `../libagora-app/tools/api-ledger` and fails in both directions: a
metric that moves, a metric that appears, or a metric that disappears. Inline doors are exempt from being symbols,
and `NSMakeRange`/`NSMaxRange` are found where they are declared (`libagora-core`).

**A complete surface is not a behavioural claim.** Every name has a body; what the bodies DO is measured by callers,
in seven probes: `object_surface` (the F1 slice), `scripting_surface` (the last five waves), `core_values` (strings,
collections, numbers, data, dates, index sets, JSON, property lists, archivers and URLs), `foundation_behaviour`
(predicates and KVC operators, sort descriptors, notifications, operations, the file manager, streams, undo, regular
expressions, date formatting, timers, character sets), `foundation_behaviour_2` (calendar arithmetic and DST,
formatters, defaults domains, XML, transformers, cookies, locales and zones), `foundation_behaviour_3` (secure coding
with allow-lists, defaults written by another process, an HTTP request against a loopback server, socket streams, an
NSConnection round-trip, file handles, and a coarse performance smoke test) and `foundation_behaviour_4` (a redirect
with its cookie, a POST body and header, NSTask's pipes and environment, NSConnection on its own thread, and a
lifecycle soak). They found and fixed sixteen defects, each recorded in its commit: clamped range doors that should
raise, a NUL answer for an out-of-range character, double-precision number comparison, NaN equality, ignored search
options, numeric comparison, a cancelled operation that never finished, a lenient-by-default date parser, an element
string value that ignored its text, a path-less input stream that could not open (which made every socket stream
unreadable), a selector-based sort that was still quadratic (50,000 numbers: 84 seconds before, 0.05 after), a
relative redirect that left the synchronous door waiting forever, an `HTTPShouldHandleCookies` that nothing honoured,
and a serving thread that watched nothing (so `-runInNewThread` never answered).

Five waves closed the surface, and three of them are **refusals by name rather than imitations**:

- **F1** — the root-class and value doors, including the informal delegate protocols (declared and marked
  `FN_INFORMAL`, counted in `methods-informal`).
- **F5/F11** — `NSCondition` restored on the pthread body that had been re-homed as `FNCondition`;
  `NSSimpleCString` as a real C-string-backed concrete string; `NSGarbageCollector` with the documented
  no-collector answers.
- **F10** — a working scripting model: eight specifier kinds, whose/logical tests, the nine standard commands,
  descriptions and the suite registry, and the NSObject scripting category. The AppleEvent descriptor is a data type
  (bytes, lists, keyword records, coercion); `NSAppleScript` and `NSAppleEventManager` execution **raise or return an
  error naming the absent OSA component and AppleEvents transport**.
- **F3** — `NSMetadataQuery` over a provider this library owns: a walk of the search scopes building `kMDItem`
  attributes, with the predicate, sorting, grouping and value lists applied. The first gathering is synchronous; live
  updates are a run-loop poll of the same walk (half a second, or `-notificationBatchingInterval`), diffed by path and
  announced with `NSMetadataQueryDidUpdateNotification`, which `-disableUpdates`/`-enableUpdates` start and stop.
- **F6** — `NSNetService`/`NSNetServiceBrowser` store their identity and TXT records (the TXT codec is a real wire
  format), but publishing, resolving and browsing **report `NSNetServicesInvalidError` to the delegate**, because this
  system has no DNS-SD responder.

`methods-declared-not-implemented` is pinned at **0**. The last three were `NSAffineTransform`'s `-set`, `-concat` and
`-transformBezierPath:`, which this framework declares and AppKit implements; they are marked `FN_COMPANION`, counted in
`methods-external`, and implemented in `libagora-app`. No declaration in this tree is left without a body somewhere.
The census measures 10.6 because that is the reference; `Foundation.h`'s 10.2 baseline (§11.0) governs what may be
removed, and the difference between a door the baseline cut and a door nobody finished is exactly what this pin made
visible.

## The 10.11 surface, measured too

10.6 is this library's reference, not the surface the Cocoa plan promises. `api/10.11/foundation-manifest.txt` holds
the facts of Apple's 10.11 Foundation (220 classes, 40 protocols, 185 functions, 3,763 selectors, plus the iOS-only
class and the `NS_UNAVAILABLE` doors the census must not charge as gaps), and `tests/api-10.11-census.txt` pins what
this tree answers of it — the second `foundation-api-10.11-census` gate runs the same instrument with a different
denominator. **198 of 219 classes, 3,422 of 3,521 selectors, 31 of 40 protocols, 182 of 182 functions**, and every name
still missing is 10.8–10.11: the 10.6 debt is closed. `FOUNDATION-10.11-PLAN.md` at the workspace root stages what
remains, and `../libagora-app/tools/api-ledger selftest` holds the extractor's own regressions (three faults in that
reader had undercounted this surface by 299 property accessors and invented two doors).

The second tier of that surface is measured too. The availability macros used to be inert by decision; they now expand
to clang's availability attribute, and every declaration this tree shares with Apple carries Apple's own version —
`foundation-api-availability` pins 800 of 800, with a wrong version failing outright. `foundation-header-compile`
compiles each of the 201 public headers ALONE as Objective-C, Objective-C++ and under ARC (plus the umbrella in each),
which is the client's question rather than the library's.

Two residues of that tier are closed and gated. **Nullability:** every pointer in every public header states
`_Nonnull`/`_Nullable`/`_Null_unspecified`; `foundation-header-nullability` pins the count of declarations still
missing one at **0**, deduped by `header:line:column` across all three modes (a warning-line count is misleading —
clang repeats an included header once per probe). **Extensions:** API later than 10.11 is marked `AGORA_EXTENSION`
with the version it really arrived in, expands to `unavailable` under `-DAG_TARGET_OS_X_10_11`, and
`foundation-strict-surface` proves the strict umbrella still compiles while each marked declaration and no normal
build's door is affected. `tests/api-10.11-nullability.txt` and the plan's §4.13 record the facts and the recipes.
