#import <Foundation/Foundation.h>

/// Netegram: decides which outgoing API calls never reach the network.
///
/// Ghost mode works by refusing to *tell the server* things — that you came online, that you
/// are typing, that you opened a chat. There is no client-side flag for any of that: the only
/// way to stay invisible is for the request never to leave the device.
///
/// Dropping a request outright would leave the caller waiting forever, so instead a plausible
/// success response is fabricated and handed back as if the server had answered. The rest of
/// the app cannot tell the difference, which is what keeps the UI from stalling.
///
/// The decision is made here, in MTProtoKit, because this is the last place the raw TL payload
/// of an outgoing call is visible — above this layer a "typing" notification and a "read
/// history" call are indistinguishable Swift values.
NS_ASSUME_NONNULL_BEGIN

@interface MTNetegramGhost : NSObject

/// Returns the response to answer with instead of sending, or nil to let the call through.
/// `payload` is the serialised TL function, starting with its constructor id.
+ (nullable NSData *)fakeResponseForPayload:(NSData *)payload;

/// Seconds to hold a send back for, or 0 to send immediately.
///
/// Only sends are delayed. Holding back a read receipt or a typing notification would make the
/// app feel broken for no benefit — the point is the window in which you can still change your
/// mind about a message.
+ (NSTimeInterval)sendDelayForPayload:(NSData *)payload;

/// Drops every send still inside its delay window. Called from the "cancel" button on the
/// notice the app puts up while a message is waiting.
+ (void)cancelDelayedSends;

/// True while a cancel is in force, so a scheduled send knows to give up.
+ (BOOL)isDelayedSendCancelled:(NSInteger)generation;

/// The generation a send was scheduled in. Compare it later against a cancel.
+ (NSInteger)currentDelayedSendGeneration;

@end

/// Posted when a send starts waiting, so the app can offer to cancel it.
extern NSString *const MTNetegramDelayedSendStartedNotification;

NS_ASSUME_NONNULL_END
