/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSXMLDTDNode.h — one DTD declaration as a node (W7), in Apple's own file.
 *
 * The kind enum and the class were declared in NSXMLDTD.h with the container that holds them; Apple gives the node its
 * own header. `NSXMLDTD` (the container) is NSXMLDTD.h and the base node is NSXMLNode.h.
 */
#ifndef FOUNDATION_NSXMLDTDNODE_H
#define FOUNDATION_NSXMLDTDNODE_H

#import <Foundation/NSXMLNode.h>

@class NSString;

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	NSXMLAttributeCDATAKind = 100,
	NSXMLAttributeEntitiesKind = 101,
	NSXMLAttributeEntityKind = 102,
	NSXMLAttributeEnumerationKind = 103,
	NSXMLAttributeIDKind = 104,
	NSXMLAttributeIDRefKind = 105,
	NSXMLAttributeIDRefsKind = 106,
	NSXMLAttributeNMTokenKind = 107,
	NSXMLAttributeNMTokensKind = 108,
	NSXMLAttributeNotationKind = 109,
	NSXMLElementDeclarationAnyKind = 110,
	NSXMLElementDeclarationElementKind = 111,
	NSXMLElementDeclarationEmptyKind = 112,
	NSXMLElementDeclarationMixedKind = 113,
	NSXMLElementDeclarationUndefinedKind = 114,
	NSXMLEntityGeneralKind = 115,
	NSXMLEntityParameterKind = 116,
	NSXMLEntityParsedKind = 117,
	NSXMLEntityUnparsedKind = 118,
	/* §62.103: the predefined entities (&amp; &lt; &gt; &quot; &apos;) are a KIND of entity node, and this enum's
	 * numbering is its own (D2) — so the new case takes the next value after the four that were here. */
	NSXMLEntityPredefined = 119,
} NSXMLDTDNodeKind;

/* "A node in a DTD": one declaration, of one of the kinds above. */
@interface NSXMLDTDNode : NSXMLNode
{
@public
	NSString *_fnElementName;	/* OURS: see the note below on the ivar this replaces */
	NSXMLDTDNodeKind _dtdKind;
	NSString *_publicID;
	NSString *_systemID;
	NSString *_notationName;
	NSString *_elementName;		/* OURS: the ELEMENT an attribute declaration belongs to, which Apple's
					 * -attributeDeclarationForName:elementName: looks up by and does not otherwise expose */
}
- (id)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithKind:(NSXMLNodeKind)kind
                     options:(NSXMLNodeOptions)options NS_DESIGNATED_INITIALIZER;
- (nullable id)initWithXMLString:(NSString *)string NS_DESIGNATED_INITIALIZER;
- (id)initWithKind:(NSXMLDTDNodeKind)kind;

/* THE ELEMENT AN ATTRIBUTE DECLARATION BELONGS TO, which Apple's -attributeDeclarationForName:elementName: looks
 * up by and does not otherwise expose. Declared in the HEADER's internal category rather than in NSXMLDTD.m
 * because it has callers in other files - NSXMLDocument sets it, NSXMLParser reads it - and a declaration only
 * one file could see made both calls invisible to the compiler. */
- (void)fnSetElementName:(NSString *)name;
- (NSString *)fnElementName;

- (NSXMLDTDNodeKind)DTDKind;
- (void)setDTDKind:(NSXMLDTDNodeKind)kind;
- (nullable NSString *)publicID;
- (void)setPublicID:(nullable NSString *)publicID;
- (nullable NSString *)systemID;
- (void)setSystemID:(nullable NSString *)systemID;
- (nullable NSString *)notationName;
- (void)setNotationName:(nullable NSString *)notationName;

/* APPLE'S EXTERNALITY QUESTION: a declaration is external when it names a system ID (the external subset's own
 * entity/notation declaration), and internal otherwise. */
- (BOOL)isExternal;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSXMLDTDNODE_H */
