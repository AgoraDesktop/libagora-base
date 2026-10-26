/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_operation_progress.m — THE OPERATION QUEUE'S SERVICE CLASS AND TARGET QUEUE, THE OPERATION'S
 * NAME/SERVICE/ASYNC DOORS, PROGRESS PUBLISHING, AND THE JSON STREAM ROUND-TRIP.
 *
 * W6's tail fills NSOperation (name, qualityOfService, isAsynchronous), NSOperationQueue (qualityOfService,
 * underlyingQueue), NSProgress (publish/unpublish, the subscriber pair, isOld) and NSJSONSerialization's two stream
 * doors. Each is measured by its own observable: an operation really runs on the dispatch queue the caller named, a
 * published progress really calls the subscriber's handler and the handler's unpublishing block, and a JSON document
 * really round-trips through an output stream and an input stream.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSProgress.h>
#import <Foundation/NSOperation.h>
#import <Foundation/NSOperationQueue.h>
#import <Foundation/NSJSONSerialization.h>
#import <Foundation/NSStream.h>

#include <dispatch/dispatch.h>
#include <stdio.h>

/* THE BLOCK RUNTIME, declared rather than included, as this library's own files do: a returned stack block must be
 * copied, and a block is not an ordinary object to own. */
extern void *_Block_copy(const void *aBlock);

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

/* AN OPERATION THAT APPENDS ITS NAME, so the order and the thread can both be read back. */
@interface RecordingOperation : NSOperation
{
@public
	NSMutableArray *_log;
	NSString *_label;
	BOOL _sawTargetQueue;
}
@end

@implementation RecordingOperation
- (void)main
{
	@synchronized (_log) {
		[_log addObject:_label];
	}
	_sawTargetQueue = dispatch_get_specific("agora.target") != NULL;
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ---- NSOperation: the label, the service class, and the async answer ---- */
	{
		RecordingOperation *operation = [[RecordingOperation alloc] init];

		check([operation name] == nil && [operation qualityOfService] == NSQualityOfServiceDefault,
		      "an operation starts with no name and the default service class");
		[operation setName:@"copy"];
		[operation setQualityOfService:NSQualityOfServiceUtility];
		check([[operation name] isEqualToString:@"copy"] &&
		      [operation qualityOfService] == NSQualityOfServiceUtility,
		      "the name and service class are stored and reported");
		check([operation isAsynchronous] == NO && [operation isConcurrent] == NO,
		      "a synchronous operation answers NO to both spellings");
		[operation release];
	}

	/* ---- NSOperationQueue: the service class, and an underlying dispatch queue that really receives the work ---- */
	{
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		dispatch_queue_t target = dispatch_queue_create("agora.test.target", DISPATCH_QUEUE_SERIAL);
		NSMutableArray *log = [NSMutableArray array];
		RecordingOperation *first;
		RecordingOperation *second;
		__block BOOL firstSawTarget = NO;
		__block BOOL secondSawTarget = NO;

		dispatch_queue_set_specific(target, "agora.target", (void *)1, NULL);
		check([queue qualityOfService] == NSQualityOfServiceDefault && [queue underlyingQueue] == NULL,
		      "a queue starts with the default service class and no target queue");
		[queue setQualityOfService:NSQualityOfServiceBackground];
		[queue setUnderlyingQueue:target];
		dispatch_release(target);		/* the queue retained it */
		check([queue qualityOfService] == NSQualityOfServiceBackground && [queue underlyingQueue] != NULL,
		      "the service class and target queue are stored and reported");

		[queue setMaxConcurrentOperationCount:1];
		first = [[RecordingOperation alloc] init];
		first->_log = [log retain];
		first->_label = @"first";
		second = [[RecordingOperation alloc] init];
		second->_log = [log retain];
		second->_label = @"second";
		[queue addOperation:first];
		[queue addOperation:second];
		[queue waitUntilAllOperationsAreFinished];
		firstSawTarget = first->_sawTargetQueue;
		secondSawTarget = second->_sawTargetQueue;
		check([log count] == 2 && [[log objectAtIndex:0] isEqualToString:@"first"] &&
		      [[log objectAtIndex:1] isEqualToString:@"second"],
		      "a serial underlying queue runs the operations in the order they were added");
		check(firstSawTarget && secondSawTarget,
		      "the operations really ran ON the target dispatch queue");
		[first release];
		[second release];
		[queue release];
	}

	/* ---- NSProgress: publish, the subscriber's handler, and its unpublishing block ---- */
	{
		NSURL *url = [NSURL fileURLWithPath:@"/tmp/agora-progress-published"];
		NSProgress *progress = [NSProgress progressWithTotalUnitCount:10];
		__block NSProgress *published = nil;
		__block int unpublished = 0;
		id subscriber;

		check([progress isOld] == NO, "a progress object this process made is not old");
		[progress setUserInfoObject:url forKey:NSProgressFileURLKey];
		subscriber = [NSProgress addSubscriberForFileURL:url
				      withPublishingHandler:^NSProgressUnpublishingHandler(NSProgress *object) {
			published = [object retain];
			return _Block_copy(^{
				unpublished++;
			});
		}];
		check(subscriber != nil, "a subscriber for a file URL is registered");
		[progress publish];
		check(published == progress, "publishing calls the handler with the progress object");
		check(unpublished == 0, "nothing is unpublished until -unpublish is sent");
		[progress unpublish];
		check(unpublished == 1, "unpublishing runs the handler's unpublishing block");
		[progress publish];
		[progress unpublish];
		check(unpublished == 2, "a second publish/unpublish pair runs it again");
		[NSProgress removeSubscriber:subscriber];
		[progress publish];
		[progress unpublish];
		check(unpublished == 2, "a removed subscriber is no longer called");
		[published release];
	}

	/* ---- NSJSONSerialization: the document through an output stream and back through an input stream ---- */
	{
		NSDictionary *object = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSArray arrayWithObjects:@"one", [NSNumber numberWithInt:2], nil], @"items",
			@"value", @"key", nil];
		NSData *canonical = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
		NSOutputStream *out = [NSOutputStream outputStreamToMemory];
		NSData *written;
		NSInputStream *in;
		id parsed;
		NSError *error = nil;

		[out open];
		check([NSJSONSerialization writeJSONObject:object toStream:out options:0 error:&error] ==
		      (NSInteger)[canonical length] && error == nil,
		      "writeJSONObject:toStream: answers the number of bytes it wrote");
		written = [out propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
		check([written isEqualToData:canonical],
		      "the stream carries exactly the bytes the data door produces");
		[out close];

		in = [NSInputStream inputStreamWithData:written];
		[in open];
		parsed = [NSJSONSerialization JSONObjectWithStream:in options:0 error:&error];
		[in close];
		check(parsed != nil && error == nil && [parsed isEqualToDictionary:object],
		      "JSONObjectWithStream: parses the stream back into the same object");

		/* A TOP-LEVEL SCALAR IS A FRAGMENT IN BOTH DIRECTIONS, as the data doors already state. */
		out = [NSOutputStream outputStreamToMemory];
		[out open];
		check([NSJSONSerialization writeJSONObject:@"fragment"
					    toStream:out
					     options:NSJSONWritingFragmentsAllowed
					       error:NULL] > 0,
		      "a top-level scalar is written only with the fragments option");
		written = [out propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
		[out close];
		in = [NSInputStream inputStreamWithData:written];
		[in open];
		parsed = [NSJSONSerialization JSONObjectWithStream:in options:NSJSONReadingFragmentsAllowed error:NULL];
		[in close];
		check([parsed isEqual:@"fragment"],
		      "and read back with the reading fragments option");
		check([NSJSONSerialization JSONObjectWithStream:[NSInputStream inputStreamWithData:written]
						       options:0
							 error:NULL] == nil,
		      "a fragment is still refused without the reading option");
	}

	printf("foundation_10_11_operation_progress: %d of %d cases passed, %d failed\n",
	       g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
