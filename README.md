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
   `CFWriteStream`/`NSOutputStream` and `CFRunLoopTimer`/`NSTimer`. The bridge is three mechanisms,
   each measured rather than assumed:

   - **Core Foundation's own objects wear an Objective-C class**, built from a table in
     `libagora-core/CFRuntime.c`, so a `CFStringRef` Core Foundation created answers `-length` and a
     `CFURLRef` answers `-host`;
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

   Verified by `tests/bridges.m`: **73 cases**, every one of the eighteen types in both directions, the
   seven mutable ones from both APIs, and — a direction nothing had tested before — Core Foundation
   asking a *Foundation* object (`CFReadStreamGetError`, `CFCalendarDecomposeAbsoluteTime`,
   `CFCalendarComposeAbsoluteTime`, `CFCalendarAddComponents`, `CFDictionaryContainsKey` and the rest of
   the doors a surface survey found missing). `PROVENANCE.md` records both what is deliberately *not*
   bridged and what is bridged imperfectly.
