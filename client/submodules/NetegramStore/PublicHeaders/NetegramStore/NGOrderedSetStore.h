#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Netegram: a bounded, append-only set of short strings kept on disk.
///
/// Built for the list of messages someone tried to take back. That list has nothing in common
/// with a settings switch: it is appended to on every incoming deletion, from whichever
/// process is applying the difference, and it is read while laying out every bubble. Sharing a
/// preferences plist with the switches meant the fork's hottest writer sat in the same
/// document as its most valuable state.
///
/// Two behaviours matter and neither is what the old list did:
///
/// Overflowing evicts the oldest entries. The previous implementation dropped the whole list
/// on reaching its limit, so every mark in the app vanished at once, roughly a day into a busy
/// account — indistinguishable from the settings resetting themselves.
///
/// Writes merge rather than replace. The app and the notification service both append here,
/// and a plain last-writer-wins save would throw away whatever the other process recorded
/// while this one held its copy in memory.
@interface NGOrderedSetStore : NSObject

/// `name` becomes the file name inside Netegram's shared directory. `limit` is the number of
/// entries kept; the oldest are dropped first.
- (instancetype)initWithName:(NSString *)name limit:(NSUInteger)limit;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)containsObject:(NSString *)value;

- (void)addObjects:(NSArray<NSString *> *)values;

/// Forces the pending save out. Called when the app steps back.
- (void)flush;

@end

NS_ASSUME_NONNULL_END
