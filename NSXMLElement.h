/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSXMLElement.h — the element node: children and attributes (W7), in Apple's own file.
 *
 * An element is what a tree is built from; the base node is NSXMLNode.h, the serialization options are
 * NSXMLNodeOptions.h, and the DTD's declaration node is NSXMLDTDNode.h. W7 moved the class out of NSXMLNode.h
 * without changing a door.
 */
#ifndef FOUNDATION_NSXMLELEMENT_H
#define FOUNDATION_NSXMLELEMENT_H

#import <Foundation/NSXMLNode.h>

@class NSDictionary;
@class NSMutableArray;
@class NSMutableDictionary;

NS_ASSUME_NONNULL_BEGIN

/* "The element nodes in an XML tree structure" - children and attributes, which is what an element ADDS. */
@interface NSXMLElement : NSXMLNode
{
	NSMutableDictionary *_attributesByName;		/* retained: name -> NSXMLNode, insertion ordered the Cocoa way */
	NSMutableArray *_attributeOrder;		/* retained: the names in the order they were added */
}

/* AN ELEMENT STATES ITS OWN DESIGNATED GRAPH, including the two doors it INHERITS: a class that marks any
 * initializer designated has to say which of the inherited ones it honours, or a caller's subclass of NSXMLElement
 * cannot tell (and clang reads the override as convenience). */
- (id)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithKind:(NSXMLNodeKind)kind
                     options:(NSXMLNodeOptions)options NS_DESIGNATED_INITIALIZER;
- (id)initWithName:(NSString *)name;
- (id)initWithName:(NSString *)name stringValue:(nullable NSString *)stringValue;
- (id)initWithName:(NSString *)name URI:(nullable NSString *)URI NS_DESIGNATED_INITIALIZER;
- (id)initWithName:(NSString *)name children:(nullable NSArray *)children
	   attributes:(nullable NSArray *)attributes;

- (NSArray *)elementsForName:(NSString *)name;
- (NSArray *)elementsForLocalName:(NSString *)localName URI:(nullable NSString *)URI;

/* THE CHILD-MUTATION DOORS ARE INHERITED, not redeclared: see the note in NSXMLNode's interface for why this
 * tree declares them once, on the node that implements them. */
- (void)normalizeAdjacentTextNodesPreservingCDATA:(BOOL)preserve;

- (void)addAttribute:(id)attribute;
- (void)removeAttributeForName:(NSString *)name;
- (void)setAttributes:(nullable NSArray *)attributes;
- (void)setAttributesWithDictionary:(NSDictionary *)attributes;
- (nullable NSArray *)attributes;
- (nullable id)attributeForName:(NSString *)name;

- (void)addNamespace:(id)aNamespace;
- (void)setNamespaces:(NSArray *)namespaces;

/* THE XPATH AND XQUERY DOORS (10.2), DECLARED AND REFUSED BY NAME. Query evaluation needs an XPath engine and
 * XQuery needs a query processor; this library's tree is its own, so each door sets the error it was given and
 * answers nil rather than returning a guessed node set. */
- (nullable NSArray<__kindof NSXMLNode *> *)nodesForXPath:(NSString *)xpath error:(NSError ** _Nullable)error;
- (nullable NSArray *)objectsForXQuery:(NSString *)xquery
			    constants:(nullable NSDictionary *)constants
				error:(NSError ** _Nullable)error;
- (nullable NSArray *)objectsForXQuery:(NSString *)xquery error:(NSError ** _Nullable)error;
- (void)removeNamespaceForPrefix:(NSString *)name;
- (nullable NSArray *)namespaces;
- (nullable id)namespaceForPrefix:(NSString *)name;
- (nullable id)resolveNamespaceForName:(NSString *)name;
- (nullable id)resolvePrefixForNamespaceURI:(NSString *)namespaceURI;


/* §63.213: THE ELEMENT'S THREE. `-attributeForLocalName:URI:` reads the SAME order array the serializer walks,
 * so the two cannot disagree about which attribute is which; `-setAttributesAsDictionary:` REPLACES the set
 * (Apple's door takes the whole of it); `-initWithXMLString:error:` is the failing form of the door the class
 * already has. */
- (nullable id)attributeForLocalName:(NSString *)localName URI:(nullable NSString *)URI;
- (void)setAttributesAsDictionary:(NSDictionary *)attributes;
- (nullable id)initWithXMLString:(NSString *)string error:(NSError **)errorPtr NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSXMLELEMENT_H */
