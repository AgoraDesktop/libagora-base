/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * FoundationErrors.h — the CODES of the Cocoa error domain, and their family bounds (W7), in Apple's own file.
 *
 * NSError.h is the class, its domains and its userInfo keys; the numeric codes are Apple's other header. THE NAMES ARE
 * APPLE'S AND THE VALUES ARE OURS (§11.6.1 D2), WITH ONE PROPERTY THAT DOES MATTER: an error code is a number a caller
 * can compare, so each family here is numbered sequentially and its Minimum/Maximum pair ENCLOSES EXACTLY ITS OWN
 * CODES. A program that compares against the symbols is right; a program that hardcodes Apple's numbers is not
 * portable, and this header says so rather than implying a fidelity the library does not claim.
 *
 * A CALLER THAT IMPORTS NSError.h ALONE DOES NOT GET THESE, which is Apple's arrangement too: Foundation's umbrella
 * imports both, and a source file that names a code imports this header (W7 added the import to the component's own
 * files that had been relying on NSError.h's old reach).
 */
#ifndef FOUNDATION_FOUNDATIONERRORS_H
#define FOUNDATION_FOUNDATIONERRORS_H

#import <Foundation/NSObjCRuntime.h>	/* NSInteger */

NS_ASSUME_NONNULL_BEGIN

extern NSInteger const NSBundleErrorMaximum;
extern NSInteger const NSBundleErrorMinimum;
extern NSInteger const NSBundleOnDemandResourceExceededMaximumSizeError;
extern NSInteger const NSBundleOnDemandResourceInvalidTagError;
extern NSInteger const NSBundleOnDemandResourceOutOfSpaceError;
extern NSInteger const NSCloudSharingConflictError;
extern NSInteger const NSCloudSharingErrorMaximum;
extern NSInteger const NSCloudSharingErrorMinimum;
extern NSInteger const NSCloudSharingNetworkFailureError;
extern NSInteger const NSCloudSharingNoPermissionError;
extern NSInteger const NSCloudSharingOtherError;
extern NSInteger const NSCloudSharingQuotaExceededError;
extern NSInteger const NSCloudSharingTooManyParticipantsError;
extern NSInteger const NSCoderErrorMaximum;
extern NSInteger const NSCoderErrorMinimum;
extern NSInteger const NSCoderInvalidValueError;
extern NSInteger const NSCoderReadCorruptError;
extern NSInteger const NSCoderValueNotFoundError;
extern NSInteger const NSExecutableArchitectureMismatchError;
extern NSInteger const NSExecutableErrorMaximum;
extern NSInteger const NSExecutableErrorMinimum;
extern NSInteger const NSExecutableLinkError;
extern NSInteger const NSExecutableLoadError;
extern NSInteger const NSExecutableNotLoadableError;
extern NSInteger const NSExecutableRuntimeMismatchError;
extern NSInteger const NSFeatureUnsupportedError;
extern NSInteger const NSFileErrorMaximum;
extern NSInteger const NSFileErrorMinimum;
extern NSInteger const NSFileLockingError;
extern NSInteger const NSFileManagerUnmountBusyError;
extern NSInteger const NSFileManagerUnmountUnknownError;
extern NSInteger const NSFileNoSuchFileError;
extern NSInteger const NSFileReadCorruptFileError;
extern NSInteger const NSFileReadInapplicableStringEncodingError;
extern NSInteger const NSFileReadInvalidFileNameError;
extern NSInteger const NSFileReadNoPermissionError;
extern NSInteger const NSFileReadNoSuchFileError;
extern NSInteger const NSFileReadTooLargeError;
extern NSInteger const NSFileReadUnknownError;
extern NSInteger const NSFileReadUnknownStringEncodingError;
extern NSInteger const NSFileReadUnsupportedSchemeError;
extern NSInteger const NSFileWriteFileExistsError;
extern NSInteger const NSFileWriteInapplicableStringEncodingError;
extern NSInteger const NSFileWriteInvalidFileNameError;
extern NSInteger const NSFileWriteNoPermissionError;
extern NSInteger const NSFileWriteOutOfSpaceError;
extern NSInteger const NSFileWriteUnknownError;
extern NSInteger const NSFileWriteUnsupportedSchemeError;
extern NSInteger const NSFileWriteVolumeReadOnlyError;
extern NSInteger const NSFormattingError;
extern NSInteger const NSFormattingErrorMaximum;
extern NSInteger const NSFormattingErrorMinimum;
extern NSInteger const NSPropertyListErrorMaximum;
extern NSInteger const NSPropertyListErrorMinimum;
extern NSInteger const NSPropertyListReadCorruptError;
extern NSInteger const NSPropertyListReadStreamError;
extern NSInteger const NSPropertyListReadUnknownVersionError;
extern NSInteger const NSPropertyListWriteInvalidError;
extern NSInteger const NSPropertyListWriteStreamError;
extern NSInteger const NSUbiquitousFileErrorMaximum;
extern NSInteger const NSUbiquitousFileErrorMinimum;
extern NSInteger const NSUbiquitousFileNotUploadedDueToQuotaError;
extern NSInteger const NSUbiquitousFileUbiquityServerNotAvailable;
extern NSInteger const NSUbiquitousFileUnavailableError;
extern NSInteger const NSUserActivityConnectionUnavailableError;
extern NSInteger const NSUserActivityErrorMaximum;
extern NSInteger const NSUserActivityErrorMinimum;
extern NSInteger const NSUserActivityHandoffFailedError;
extern NSInteger const NSUserActivityHandoffUserInfoTooLargeError;
extern NSInteger const NSUserActivityRemoteApplicationTimedOutError;
extern NSInteger const NSUserCancelledError;
extern NSInteger const NSValidationErrorMaximum;
extern NSInteger const NSValidationErrorMinimum;

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_FOUNDATIONERRORS_H */
