#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Netegram: where every setting this fork owns actually lives.
///
/// It used to be `NSUserDefaults.standard`, which is wrong here for two reasons.
///
/// Telegram is not one process. The app, the notification service, the share sheet, Siri and
/// the widget all run separately, and `standard` resolves to the *calling bundle's* domain —
/// so a flag written by the app reads back as `NO` inside an extension. The notification
/// service is not a bystander: it runs `standaloneStateManager`, polls the difference and
/// applies deletions into the shared Postbox. Anti-revoke consulted there was therefore
/// always off, and messages deleted while the app sat in the background were deleted for
/// real. That is the "settings reset themselves after a few hours" report: nothing reset,
/// the other process never saw them.
///
/// And a preferences domain is not a durable store. It is a single plist owned by cfprefsd,
/// shared with every other key the process writes; the fork's hottest writer (the deleted
/// message list) rewrote a large array through it on every incoming deletion.
///
/// So: the app group's shared defaults for reach, a JSON file beside it for durability, and
/// memory in front of both because these are read while laying out every bubble. The file is
/// the source of truth — if the defaults come back empty the file puts them back.
@interface NGStore : NSObject

/// Posted on the main thread after any value changes, including changes made by another
/// process. Caches that mirror a key should refresh here rather than on
/// `NSUserDefaultsDidChangeNotification`, which in this app fires constantly for reasons
/// that have nothing to do with Netegram.
@property (class, nonatomic, readonly) NSNotificationName didChangeNotification;

/// The key prefix everything in here shares. Import refuses anything outside it, so a
/// settings file cannot reach into Telegram's own preferences.
@property (class, nonatomic, readonly) NSString *keyPrefix;

+ (BOOL)boolForKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key;
+ (double)doubleForKey:(NSString *)key;
+ (nullable NSString *)stringForKey:(NSString *)key;
+ (nullable NSArray<NSString *> *)stringArrayForKey:(NSString *)key;
+ (nullable NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)key;
+ (nullable id)objectForKey:(NSString *)key;

+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (void)setDouble:(double)value forKey:(NSString *)key;
+ (void)setObject:(nullable id)value forKey:(NSString *)key;
+ (void)removeObjectForKey:(NSString *)key;

/// Every stored value, for export.
+ (NSDictionary<NSString *, id> *)allValues;

/// Applies an imported document. Keys outside the prefix and values JSON cannot carry are
/// skipped rather than trusted. Existing keys the document does not mention are left alone.
+ (void)applyValues:(NSDictionary<NSString *, id> *)values;

/// Drops every Netegram value, in both the defaults and the file.
+ (void)removeAllValues;

/// Directory inside the shared container that Netegram may write to, creating it if needed.
/// Returns nil when neither the app group nor the app's own container can be opened.
///
/// Exposed because the deleted-message list keeps its own file here: it is written on every
/// incoming deletion, and a hot writer does not belong in the same document as the switches.
+ (nullable NSString *)storageDirectory;

/// Forces anything still buffered out to disk. Called when the app steps back.
+ (void)flush;

@end

NS_ASSUME_NONNULL_END
