/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSArchiver and NSUnarchiver — THE CLASSIC, SEQUENTIAL ARCHIVER PAIR (§62.86), and with it
 * `NXReadNSObjectFromCoder`. This closes `Files and Data Persistence / Deprecated`.
 *
 * SEQUENTIAL IS THE WHOLE POINT: a value is written with a TYPE and read back in the SAME ORDER with the
 * same type — there are no keys and no coercion. That is what makes this pair a *different* format from
 * `NSKeyedArchiver`/`NSKeyedUnarchiver` rather than an older spelling of it, and the two cannot be
 * confused: **each family implements its own doors and RAISES in the other's** (see NSCoder.h), and the
 * sequential reader REFUSES a keyed archive outright.
 *
 * THE WIRE IS OURS, AND THAT IS STATED RATHER THAN IMPLIED. Apple's classic archiver wrote `typedstream`,
 * whose structure is not published; this library neither produces nor consumes it. What is honoured is
 * the CONTRACT (a round-tripping, sequential, single-root archive) and the one interoperability rule
 * Apple states in words — a keyed archive cannot be read here. The layout is in `FNArchiverWire.h`,
 * internal and documented, because a format nobody can read is a format nobody can test.
 *
 * CLASS-NAME TRANSLATION IS IMPLEMENTED (§63.247), because the wire is ours and the mapping is part of what an
 * archiver is FOR: `-encodeClassName:intoClassName:` records the name written in place of a class and
 * `-classNameEncodedForTrueClassName:` is the door the writer consults. The reader has the mirror pair, so a
 * renamed class round-trips instead of being a name the reader cannot find.
 *
 * WHAT IS ABSENT, NAMED AND WITH ITS GROUND:
 *   * `-versionForClassName:` IS declared (it is on the base) and RAISES here, because this wire records
 *     no class versions — answering a number that was never written would be a fabrication.
 *
 * AN OBJECT THAT IS NOT `NSCoding` IS REFUSED (NSInconsistentArchiveException), and so is a class whose
 * `-encodeWithCoder:` reaches for the KEYED doors: that is not a defect of this pair, it is what
 * "sequential" means — a class written against keys has no order to fall back on.
 */

#import <Foundation/NSCoder.h>

NS_ASSUME_NONNULL_BEGIN

@class NSData;
@class NSMutableData;
@class NSString;

@interface NSArchiver : NSCoder
{
@private
	id _data;		/* the NSMutableData the caller supplied, retained */
	id _objects;		/* the object table: the WIRE's indices live here */
	id _replaced;		/* sources, in the order they were registered */
	id _targets;		/* their replacements, index for index */
	BOOL _rootEncoded;
	NSZone *_objectZone;	/* the zone substituted objects are allocated in; default when unset */
	id _classMap;		/* true class name -> the name written, for -encodeClassName:intoClassName: */
}

/* ONE ROOT, AND THE DATA COMES BACK. Both write a header before any value, so a reader can tell this
 * format from another one; `+archiveRootObject:toFile:` answers NO if the file could not be written. */
+ (NSData *)archivedDataWithRootObject:(id)rootObject;
+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path;

/* A nil `data` is a PROGRAMMING ERROR, not an empty archive, and it raises `NSInvalidArgumentException`
 * (Apple's own contract). */
- (instancetype)initForWritingWithMutableData:(nullable NSMutableData *)data NS_DESIGNATED_INITIALIZER;

/* WRITE THE GRAPH. Sending this TWICE raises `NSInvalidArgumentException`: one archive holds one root, and
 * a second root would be a second archive wearing the first one's header. */
- (void)encodeRootObject:(id)rootObject;

/* The data this archiver was given — the SAME object, which is why a caller can read it back after
 * `-encodeRootObject:` returns. */
- (NSMutableData *)archiverData;

/* Object substitution on the WRITING side: `object` is written out as `newObject`. A nil replacement
 * means the object is written as nil, which is a value here. */
- (void)replaceObject:(nullable id)object withObject:(nullable id)newObject;

/* THE ZONE OBJECTS ARE DECODED INTO. Apple's classic archiver pair carries it; a NULL answer means the
 * default zone, and setting NULL restores that. */
- (NSZone *)objectZone;
- (void)setObjectZone:(nullable NSZone *)zone;

/* THE CLASS-NAME MAP (10.0). `-encodeClassName:intoClassName:` records that `trueName` is written as
 * `inArchiveName`; `-classNameEncodedForTrueClassName:` answers the recorded name or the name itself, which is the
 * question the writer asks for every object. The reader's mirror pair is on NSUnarchiver. */
- (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName;
- (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName;

@end

@interface NSUnarchiver : NSCoder
{
@private
	id _data;		/* the NSData being read, retained */
	NSUInteger _pos;	/* where the next byte is */
	id _objects;		/* the object table, built as values are decoded */
	id _replaced;		/* substitution sources */
	id _targets;		/* their replacements */
	NSZone *_objectZone;	/* the zone decoded objects are allocated in; default when unset */
	id _decodeMap;		/* the name in the archive -> the class name to look up */
}

/* AN INVALID ARCHIVE ANSWERS nil RATHER THAN RAISING, because "this is not an archive of mine" is a value
 * a caller can act on — but a nil ARGUMENT is a programming error and raises, as on the writing side. */
+ (nullable id)unarchiveObjectWithData:(NSData *)data;
+ (nullable id)unarchiveObjectWithFile:(NSString *)path;
- (nullable instancetype)initForReadingWithData:(nullable NSData *)data NS_DESIGNATED_INITIALIZER;

/* Whether the reader is at the end of the archive — the door that tells a caller whether the object it
 * just decoded was the WHOLE archive. */
- (BOOL)isAtEnd;

/* Object substitution on the READING side: whenever a value EQUAL TO `object` is decoded from the archive,
 * `replacement` is handed back instead. **THE MATCH IS BY EQUALITY HERE AND BY IDENTITY ON THE WRITING
 * SIDE** — inherent rather than chosen: outbound the caller holds the instance it substitutes, inbound the
 * object does not exist until it has been decoded, so a caller can only name what it is equal to. */
- (void)replaceObject:(nullable id)object withObject:(nullable id)newObject;

- (NSZone *)objectZone;
- (void)setObjectZone:(nullable NSZone *)zone;


@end

/* THE OBJECT-SUBSTITUTION CALLBACK (10.0), on the root class as an informal protocol: an object may answer a
 * DIFFERENT object to be written in its place. The default substitutes nothing. */
@interface NSObject (NSArchiverCallback)
- (nullable id)replacementObjectForArchiver:(NSCoder *)anArchiver;
@end

/* Reads one object from a coder. APPLE DECLARES THIS IN `NSSerialization.h`, A HEADER THIS LIBRARY DOES
 * NOT SHIP: it is declared here, beside the pair it belongs to, rather than in a header created to hold
 * one line. It is the legacy free-function spelling of `-decodeObject` and does nothing else. */
id _Nullable NXReadNSObjectFromCoder(NSCoder *coder);

NS_ASSUME_NONNULL_END
