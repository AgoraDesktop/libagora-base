/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * Foundation.h — the umbrella.
 *
 * A consumer writes `#import <Foundation/Foundation.h>`. The path is lower-case
 * on purpose: Apple's Foundation is <Foundation/…>, and the wall's gate fails
 * the build if a first-party file ever imports that spelling.
 *
 * docs/design/foundation-plan.md — F0 ships the ROOT CLASS. It ships no pool
 * class, because the RUNTIME adopts any class named NSAutoreleasePool as its own
 * pool object (§6 of the plan), so pools are the runtime's and ARC's
 * `@autoreleasepool` is the interface to them.
 *
 * THE OWNERSHIP RULE, STATED ONCE FOR THE WHOLE LIBRARY (F13.21), because it is
 * the one thing a reader of any file here needs and no single file can say:
 *
 *   THE LIBRARY IS COMPILED WITHOUT ARC, and not by preference — this system's
 *   libobjc2 uses the LEGACY runtime ABI, and clang refuses -fobjc-arc on it
 *   ("not supported on platforms using the legacy runtime"). Enabling ARC would
 *   mean changing the runtime's object layout, not adding a flag.
 *
 *   SO THE MODEL IS MANUAL, AND IT IS THE SAME IN EVERY FILE: a method STORES
 *   the pointers it is given and owns NOTHING. An object handed to the library
 *   must outlive its use of it; a collection does not keep its members alive; a
 *   delegate, target or observer is the caller's to keep. The exceptions are
 *   the classes that own C STORAGE (a buffer, a mutex, a compiled regex), and
 *   each of those frees what it allocated in -dealloc and says so in its own
 *   header.
 *
 *   THE CONSEQUENCE, WHICH IS WHY THIS IS WRITTEN DOWN: a caller must not
 *   release a pointer it has handed in until the library is done with it, and a
 *   library call that outlives its caller's scope — a thread, a timer, a queue —
 *   is the caller's to keep alive. Every file in this library was written to
 *   that rule; the four that were not were fixed when they were found.
 */

#ifndef FOUNDATION_FOUNDATION_H
#define FOUNDATION_FOUNDATION_H

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSGarbageCollector.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSByteOrder.h>
#import <Foundation/NSUUID.h>
#import <Foundation/NSDecimal.h>
#import <Foundation/NSDecimalNumber.h>
#import <Foundation/NSDateInterval.h>
#import <Foundation/NSValueTransformer.h>
#import <Foundation/NSAffineTransform.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSProxy.h>
#import <Foundation/NSUndoManager.h>
#import <Foundation/NSJSONSerialization.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSCalendar.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/FoundationErrors.h>
/* THE URL LOADING SYSTEM'S ERROR NAMES (§56): the codes, the two reason enums and the userInfo keys. Its own
 * header because the family is its own, and imported here so a caller of Foundation has them. */
#import <Foundation/NSURLError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSOrthography.h>
#import <Foundation/NSLinguisticTagger.h>
#import <Foundation/NSSpellServer.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSUbiquitousKeyValueStore.h>
#import <Foundation/NSUserActivity.h>
#import <Foundation/NSDistantObjectRequest.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSIndexPath.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSDirectoryEnumerator.h>
#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSFilePresenter.h>
#import <Foundation/NSFileSecurity.h>
#import <Foundation/NSFileVersion.h>
#import <Foundation/NSFileProviderService.h>
#import <Foundation/NSXMLDTD.h>
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLNodeOptions.h>
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDTDNode.h>
#import <Foundation/NSXMLParser.h>
#import <Foundation/NSFileWrapper.h>
#import <Foundation/NSPropertyList.h>
#import <Foundation/NSPropertyListSerialization.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSURLComponents.h>
#import <Foundation/NSURLQueryItem.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSSortDescriptor.h>
/* THE PREDICATE FAMILY IS BACK (§63.161 REVERSED, COREDATA-PLAN.md §4.1), and the paragraph that used to sit
 * here is kept in one line because its reasoning is worth remembering: the family is macOS 10.4, it was removed
 * against a 10.2 baseline, and §63.135 had already removed its ledger rows in the same campaign. The tree's
 * REFERENCE is 10.6 — `tests/api-10.6-census.txt` says so in its own preamble — so 10.4 is inside the reference
 * and the removal was measuring yesterday's target. Two further facts settled it: `api/10.6/appkit-manifest.txt`
 * carries 29 rows naming a predicate (`-fetchPredicate`, `-filterPredicate`, `NSPredicateEditorRowTemplate`), and
 * Core Data's `NSFetchRequest` is a fetcher OF predicates. The collection doors went with the family and come back
 * with it: `-filteredArrayUsingPredicate:`, `-filterUsingPredicate:`, `-filteredSetUsingPredicate:`.
 *
 * ⚠ AND THE CENSUS THAT PREAMBLE NAMED NOW EXISTS FOR THIS LIBRARY TOO: `api/10.6/foundation-manifest.txt` is the
 * facts and `../tests/api-10.6-census.txt` is the pin, so "inside the reference" is answered by a metric rather
 * than by this comment. It measures the whole 10.6 surface, including the 10.3–10.6 doors the baseline rule had
 * excluded; scheduling those is the plan's decision, not the census's. */
#import <Foundation/NSExpression.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSClassDescription.h>
#import <Foundation/NSScriptClassDescription.h>
#import <Foundation/NSScriptExecutionContext.h>
#import <Foundation/NSScriptCoercionHandler.h>
#import <Foundation/NSScriptKeyValueCoding.h>
#import <Foundation/NSScriptCommandDescription.h>
#import <Foundation/NSScriptSuiteRegistry.h>
#import <Foundation/NSScriptStandardSuiteCommands.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <Foundation/NSObjectScripting.h>
#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSScriptCommand.h>
#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSAppleEventManager.h>
#import <Foundation/NSAppleScript.h>
#import <Foundation/NSMetadata.h>
#import <Foundation/NSMetadataAttributes.h>
#import <Foundation/NSNetServices.h>
#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSFormatter.h>
#import <Foundation/NSByteCountFormatter.h>
#import <Foundation/NSLengthFormatter.h>
#import <Foundation/NSMassFormatter.h>
#import <Foundation/NSEnergyFormatter.h>
#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSPersonNameComponents.h>
#import <Foundation/NSPersonNameComponentsFormatter.h>
#import <Foundation/NSISO8601DateFormatter.h>
#import <Foundation/NSDateIntervalFormatter.h>
#import <Foundation/NSRelativeDateTimeFormatter.h>
#import <Foundation/NSDateComponentsFormatter.h>
/* W12's first slice: the unit machinery and the value that carries one. None of these four needs ICU —
 * the arithmetic is the converters' — which is why they are not in FN_FOUNDATION_ICU. */
/* W12's dimensional families. Each is a table and a set of class methods — and none needs ICU, for the same
 * reason the machinery above needs none: the arithmetic is the converters'. */
#import <Foundation/NSKeyedArchiverDelegate.h>
#import <Foundation/NSKeyedUnarchiverDelegate.h>
#import <Foundation/NSSecureUnarchiveFromDataTransformer.h>
#import <Foundation/NSPointerFunctions.h>
#import <Foundation/NSPointerArray.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSDiscardableContent.h>
#import <Foundation/NSPurgeableData.h>
#import <Foundation/NSCache.h>
#import <Foundation/NSCacheDelegate.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSCountedSet.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSMutableOrderedSet.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <Foundation/NSNotificationQueue.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSCoding.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSHFSFileTypes.h>
#import <Foundation/NSTextCheckingResult.h>
#import <Foundation/NSRegularExpression.h>
#import <Foundation/NSDataDetector.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSCondition.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSBackgroundActivityScheduler.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSProgress.h>
#import <Foundation/NSOperation.h>
#import <Foundation/NSBlockOperation.h>
#import <Foundation/NSInvocationOperation.h>
#import <Foundation/NSOperationQueue.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSMachPort.h>
#import <Foundation/NSMessagePort.h>
#import <Foundation/NSPortNameServer.h>
#import <Foundation/NSMessagePortNameServer.h>
#import <Foundation/NSSocketPortNameServer.h>
#import <Foundation/NSMachBootstrapServer.h>
#import <Foundation/NSProtocolChecker.h>
#import <Foundation/NSDistributedLock.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortMessage.h>
#import <Foundation/NSSocketPort.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSPipe.h>
#import <Foundation/NSInputStream.h>
#import <Foundation/NSOutputStream.h>
#import <Foundation/NSUserUnixTask.h>
#import <Foundation/NSStream.h>
#import <Foundation/NSTask.h>
#import <Foundation/NSURLRequest.h>
#import <Foundation/NSURLResponse.h>
#import <Foundation/NSURLConnection.h>
#import <Foundation/NSURLDownload.h>
#import <Foundation/NSURLHandle.h>
#import <Foundation/NSCachedURLResponse.h>
#import <Foundation/NSURLCache.h>
#import <Foundation/NSURLProtocol.h>
#import <Foundation/FNCURLURLProtocol.h>
/* THE NSURLSession FAMILY IS IN THE UMBRELLA (W7, AND §63.159 IS REVERSED). §63.159 removed seven classes here
 * because they are Apple's LATER than the 10.2 baseline; that reasoning measured the WRONG QUESTION, and W7's
 * reference is 10.11, where the family is a first-class part of Foundation. The classes now exist, are implemented
 * over the URL-protocol seam (§63.153, §63.157), and a client that writes `#import <Foundation/Foundation.h>` must
 * see them — an umbrella missing a family the library ships is the defect this line fixes.
 *
 * AND THE TWO RULES ARE STATED TOGETHER, because they answer different questions and both stay:
 *   * §11.0's 10.2 baseline governs what this library MAY LOSE. It is why a 10.6 door that disappears fails
 *     `foundation-api-census` (173 of 173 classes, 2,840 of 2,840 selectors).
 *   * The 10.11 reference — `api/10.11/foundation-manifest.txt` and the pin `tests/api-10.11-census.txt` — governs
 *     what the Cocoa plan PROMISES. It is why a 10.11 door that never arrives fails `foundation-api-10.11-census`
 *     (219 of 219 classes, 3,744 of 3,744 selectors, 40 of 40 protocols, 182 of 182 functions).
 * The session family is 10.9: outside the 10.6 denominator, inside the 10.11 one, and therefore admitted here. */
#import <Foundation/NSURLSession.h>
#import <Foundation/NSURLSessionConfiguration.h>
#import <Foundation/NSHTTPURLResponse.h>
#import <Foundation/NSHTTPCookie.h>
#import <Foundation/NSURLProtectionSpace.h>
#import <Foundation/NSURLCredential.h>
#import <Foundation/NSURLAuthenticationChallenge.h>
#import <Foundation/NSURLCredentialStorage.h>
#import <Foundation/NSHTTPCookieStorage.h>

/* ---- THE 10.11 FAMILIES AND THE ORGANISATION HEADERS (W7) --------------------------------------------
 *
 * WHAT IS HERE AND WHY IT IS A SEPARATE PARAGRAPH: these names arrived with the 10.8–10.11 waves and were reachable
 * only by importing their own headers. Apple's umbrella has always carried them, and a client written against
 * Apple's Foundation must not have to know which of the family's headers to name. Each import below is a family the
 * plan's §3.1/§3.5 measured, so this list is the plan's own inventory rather than a preference.
 */
/* THE EXTENSION FAMILY, in Apple's three files (W7 split W4a's combined header). */
#import <Foundation/NSExtensionItem.h>
#import <Foundation/NSExtensionContext.h>
#import <Foundation/NSExtensionRequestHandling.h>
#import <Foundation/NSItemProvider.h>
/* THE NOTIFICATION FAMILY (10.8): the value, its action, and the in-process centre. */
#import <Foundation/NSUserNotification.h>
#import <Foundation/NSUserNotificationCenter.h>
/* XPC (10.8): every door refuses by name; the CLASSES are still the client-visible surface. */
#import <Foundation/NSXPCConnection.h>
/* THE SCRIPT TASKS (10.8): the base and its two refused subclasses. */
#import <Foundation/NSUserScriptTask.h>

#endif /* FOUNDATION_FOUNDATION_H */
