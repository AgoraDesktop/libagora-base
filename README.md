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

**Imported and building; not yet bridged.**

1. **The build is wired.** Foundation compiles and links with clang against `libagora-objc` (the
   Objective-C runtime), `libagora-core` (Core Foundation), `libagora-dispatch`, the system ICU and
   zlib, plus `plist.c` \u2014 the property-list core that lives beside the Foundation in the Fiwix tree
   (`../Fiwix/userland/plist.c`, header `../Fiwix/include/plist.h`).
2. **Toll-free bridging is still owed.** The imported Foundation has no CoreFoundation, so its value
   types are standalone (`NSString` \u2192 `NSOwnedString` owns its own buffer). Agora's `libagora-base`
   must **toll-free bridge** them to `libagora-core` the way Apple does \u2014 `CFStringRef` and
   `NSString *` *are the same object* \u2014 by making the concrete value classes the CF objects and
   registering them with Core Foundation (`_CFRuntimeBridgeTypeToClass` plus the `__CFSwiftBridge`
   bridge structs).
