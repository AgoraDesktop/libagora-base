/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSHFSFileTypes.h — the classic Mac four-character file type, and the three doors that read it (W7), in Apple's own
 * file.
 *
 * THE THREE HFS FUNCTIONS ARE THE CLASSIC MAC TYPE-CODE DOOR. Two are pure string arithmetic over a four-character
 * code, which is why they are implemented; NSHFSTypeOfFile() is NOT, because the type of a file on classic HFS lives
 * in a RESOURCE FORK this system does not have — it answers nil and says so on the log rather than pretending a file
 * system fact it cannot read.
 */
#ifndef FOUNDATION_NSHFSFILETYPES_H
#define FOUNDATION_NSHFSFILETYPES_H

#import <Foundation/NSObjCRuntime.h>

@class NSString;

NS_ASSUME_NONNULL_BEGIN

extern NSString * _Nullable NSFileTypeForHFSTypeCode(unsigned int hfsTypeCode);
extern unsigned int NSHFSTypeCodeFromFileType(NSString * _Nullable fileType);
extern NSString * _Nullable NSHFSTypeOfFile(NSString * _Nullable fullFilePath);

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSHFSFILETYPES_H */
