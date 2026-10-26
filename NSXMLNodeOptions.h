/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSXMLNodeOptions.h — the serialization options an XML node is read or written with (W7), in Apple's own file.
 *
 * The bits were declared in NSXMLNode.h with the class that uses them; Apple gives them a header of their own, which
 * is what a client that passes an option imports. The values are ours (§11.6.1 D2) and the names are Apple's.
 */
#ifndef FOUNDATION_NSXMLNODEOPTIONS_H
#define FOUNDATION_NSXMLNODEOPTIONS_H

#import <Foundation/NSObjCRuntime.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	NSXMLNodeOptionsNone = 0,
	NSXMLNodeCompactEmptyElement = 1 << 0,
	NSXMLNodeExpandEmptyElement = 1 << 1,
	NSXMLNodeIsCDATA = 1 << 2,
	NSXMLNodeUseSingleQuotes = 1 << 3,
	NSXMLNodeUseDoubleQuotes = 1 << 4,
	NSXMLNodeNeverEscapeContents = 1 << 5,
	NSXMLNodePreserveWhitespace = 1 << 6,
	NSXMLNodePreserveCDATA = 1 << 7,
	NSXMLNodePromoteSignificantWhitespace = 1 << 8,
	NSXMLNodePreserveNamespaceOrder = 1 << 9,
	NSXMLNodePreserveAttributeOrder = 1 << 10,
	NSXMLNodePreserveEntities = 1 << 11,
	NSXMLNodePreservePrefixes = 1 << 12,
	NSXMLNodePreserveQuotes = 1 << 13,
	NSXMLNodePreserveDTD = 1 << 14,
	NSXMLNodePreserveCharacterReferences = 1 << 15,
	NSXMLNodePreserveEmptyElements = 1 << 16,
	NSXMLNodePreserveAll = 1 << 17,
	NSXMLNodeLoadExternalEntitiesAlways = 1 << 18,
	NSXMLNodeLoadExternalEntitiesNever = 1 << 19,
	NSXMLNodeLoadExternalEntitiesSameOriginOnly = 1 << 20,
	NSXMLNodePrettyPrint = 1 << 21,
} NSXMLNodeOptions;

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSXMLNODEOPTIONS_H */
