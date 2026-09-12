

#import <Foundation/Foundation.h>

@class MTRequestContext;
@class MTRequestErrorContext;
@class MTRpcError;

@interface MTRequestResponseInfo : NSObject

@property (nonatomic, readonly) int32_t networkType;
@property (nonatomic, readonly) double timestamp;
@property (nonatomic, readonly) double duration;

- (instancetype)initWithNetworkType:(int32_t)networkType timestamp:(double)timestamp duration:(double)duration;

@end

@interface MTRequest : NSObject

@property (nonatomic, strong, readonly) id internalId;

@property (nonatomic, strong, readonly) NSData *payload;
@property (nonatomic, strong, readonly) id metadata;
@property (nonatomic, strong, readonly) id shortMetadata;
@property (nonatomic, strong, readonly) id (^responseParser)(NSData *);

@property (nonatomic, strong) NSArray *decorators;
@property (nonatomic) int32_t transactionResetStateVersion;
@property (nonatomic, strong) MTRequestContext *requestContext;
@property (nonatomic, strong) MTRequestErrorContext *errorContext;
@property (nonatomic) bool hasHighPriority;
@property (nonatomic) bool dependsOnPasswordEntry;
@property (nonatomic) bool passthroughPasswordEntryError;
@property (nonatomic) bool needsTimeoutTimer;
@property (nonatomic) int32_t expectedResponseSize;

@property (nonatomic, copy) void (^completed)(id result, MTRequestResponseInfo *info, MTRpcError *error);
@property (nonatomic, copy) void (^progressUpdated)(float progress, NSUInteger packetLength);
@property (nonatomic, copy) void (^acknowledgementReceived)();

@property (nonatomic, copy) bool (^shouldContinueExecutionWithErrorContext)(MTRequestErrorContext *errorContext);
@property (nonatomic, copy) bool (^shouldDependOnRequest)(MTRequest *anotherRequest);

/// Netegram: when set, this request is answered locally with the given serialised response
/// and never sent. Filled in by MTNetegramGhost as the payload is attached. See
/// MTNetegramGhost.h for why the interception has to happen at this layer.
@property (nonatomic, strong) NSData *netegramFakeData;

/// Netegram: set once a delayed send has served its wait, so re-queueing it after the delay
/// does not start a second one.
@property (nonatomic) bool netegramWasDelayed;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser;

@end
