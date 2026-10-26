/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSMetadataAttributes.h — the kMDItem attribute names NSMetadataItem answers (W7), in Apple's own file.
 *
 * Apple's header carries the whole Spotlight vocabulary; this one carries the SEVEN attributes this library's provider
 * observes and documents that it is a subset. THE VALUES ARE APPLE'S SPELLINGS because a predicate is written against
 * them: `[NSPredicate predicateWithFormat:@"kMDItemFSSize > 0"]` is the query language, and the constants exist so a
 * caller who prefers not to spell the string has the same fact.
 */
#ifndef FOUNDATION_NSMETADATAATTRIBUTES_H
#define FOUNDATION_NSMETADATAATTRIBUTES_H

#import <Foundation/NSObjCRuntime.h>

@class NSString;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSMetadataItemFSNameKey;		/* "kMDItemFSName" */
extern NSString *const NSMetadataItemPathKey;		/* "kMDItemPath" */
extern NSString *const NSMetadataItemFSSizeKey;		/* "kMDItemFSSize" */
extern NSString *const NSMetadataItemContentModificationDateKey;	/* "kMDItemContentModificationDate" */
extern NSString *const NSMetadataItemContentCreationDateKey;	/* "kMDItemContentCreationDate" */
extern NSString *const NSMetadataItemContentTypeKey;	/* "kMDItemContentType" */
extern NSString *const NSMetadataItemKindKey;		/* "kMDItemKind" */

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSMETADATAATTRIBUTES_H */
