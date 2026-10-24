/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSNetServices.h — Bonjour's objects, DECLARED AND REFUSED BY NAME.
 *
 * Publishing, resolving and browsing need a DNS-SD responder and a multicast resolver; this system has neither
 * (no Avahi client library is installed, and this library ships no mDNS stack). The subjects are still real: the
 * service's domain/type/name/port are stored, the TXT-record encoder and decoder are real (they are a wire format,
 * not a network call), and the run-loop scheduling is remembered. Every network operation reports
 * `NSNetServicesInvalidError` to the delegate instead of claiming a publication that never happened.
 */
#ifndef FOUNDATION_NSNETSERVICES_H
#define FOUNDATION_NSNETSERVICES_H

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>

@class NSArray;
@class NSMutableArray;
@class NSData;
@class NSDictionary;
@class NSString;
@class NSRunLoop;
@class NSInputStream;
@class NSOutputStream;
@class NSNetService;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNetServicesErrorCode;
extern NSString *const NSNetServicesErrorDomain;

enum {
	NSNetServicesUnknownError = -72000,
	NSNetServicesCollisionError = -72001,
	NSNetServicesNotFoundError = -72002,
	NSNetServicesActivityInProgress = -72003,
	NSNetServicesBadArgumentError = -72004,
	NSNetServicesCancelledError = -72005,
	NSNetServicesInvalidError = -72006,
	NSNetServicesTimeoutError = -72007
};
typedef NSInteger NSNetServicesError;

enum {
	NSNetServiceNoAutoRename = 1UL << 0
};
typedef NSUInteger NSNetServiceOptions;

@protocol NSNetServiceDelegate <NSObject>
@optional
- (void)netServiceWillPublish:(NSNetService *)sender;
- (void)netServiceDidPublish:(NSNetService *)sender;
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict;
- (void)netServiceWillResolve:(NSNetService *)sender;
- (void)netServiceDidResolveAddress:(NSNetService *)sender;
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict;
- (void)netServiceDidStop:(NSNetService *)sender;
- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data;
@end

@interface NSNetService : NSObject
{
@private
	NSString *_domain;
	NSString *_type;
	NSString *_name;
	NSInteger _port;
	id _delegate;
	NSData *_txtRecord;
	id _protocolSpecificInformation;
	NSMutableArray *_schedules;
	BOOL _published;
	BOOL _resolving;
}

- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(NSInteger)port;
- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name;

@property (nullable, assign) id <NSNetServiceDelegate> delegate;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *type;
@property (readonly, copy) NSString *name;
@property (readonly) NSInteger port;
@property (readonly, copy) NSArray *addresses;
@property (nullable, readonly, copy) NSString *hostName;

- (void)publish;
- (void)publishWithOptions:(NSNetServiceOptions)options;
- (void)resolve;
- (void)resolveWithTimeout:(NSTimeInterval)timeout;
- (void)stop;
- (void)startMonitoring;
- (void)stopMonitoring;

+ (nullable NSDictionary *)dictionaryFromTXTRecordData:(NSData *)txtData;
+ (nullable NSData *)dataFromTXTRecordDictionary:(NSDictionary *)txtDictionary;
- (BOOL)setTXTRecordData:(nullable NSData *)recordData;
@property (nullable, readonly, copy) NSData *TXTRecordData;
@property (nullable, copy) NSString *protocolSpecificInformation;

- (BOOL)getInputStream:(NSInputStream * _Nullable * _Nullable)inputStream
	  outputStream:(NSOutputStream * _Nullable * _Nullable)outputStream;
@end

@protocol NSNetServiceBrowserDelegate <NSObject>
@optional
- (void)netServiceBrowserWillSearch:(id)aNetServiceBrowser;
- (void)netServiceBrowserDidStopSearch:(id)aNetServiceBrowser;
- (void)netServiceBrowser:(id)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict;
- (void)netServiceBrowser:(id)aNetServiceBrowser didFindDomain:(NSString *)domainString moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(id)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(id)aNetServiceBrowser didRemoveDomain:(NSString *)domainString moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(id)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
@end

@interface NSNetServiceBrowser : NSObject
{
@private
	id _delegate;
	NSMutableArray *_schedules;
	BOOL _searching;
}
- (instancetype)init;
@property (nullable, assign) id <NSNetServiceBrowserDelegate> delegate;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)searchForBrowsableDomains;
- (void)searchForRegistrationDomains;
- (void)searchForAllDomains;
- (void)searchForServicesOfType:(NSString *)serviceType inDomain:(NSString *)domainString;
- (void)stop;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSNETSERVICES_H */
