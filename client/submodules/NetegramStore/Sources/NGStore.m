#import <NetegramStore/NGStore.h>

#include <notify.h>

static NSString * const NGStoreKeyPrefixValue = @"netegram.";
static NSNotificationName const NGStoreDidChangeNotificationValue = @"NGStoreDidChangeNotification";

/// Darwin notifications carry no payload, so a process that receives one re-reads the file
/// rather than being told what changed. The name is fixed rather than derived from the bundle
/// id: every process that shares the app group shares this store, and a per-bundle name would
/// mean the extensions listened on channels nobody posts to.
static const char *NGStoreDarwinNotificationName = "ph.telegra.Telegraph.netegram.storeChanged";

static NSString * const NGStoreDirectoryName = @"netegram";
static NSString * const NGStoreFileName = @"settings.json";

#pragma mark - Shared state

static NSLock *NGStoreLock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

/// Everything below is touched only while NGStoreLock() is held, except where a comment says
/// otherwise.
static NSMutableDictionary<NSString *, id> *NGStoreValues = nil;
static BOOL NGStoreDidLoad = NO;

#pragma mark - Container resolution

/// The defaults suite and directory shared by the app and its extensions.
///
/// `NSUserDefaults.standard` resolves to the calling bundle's own domain, so an extension
/// reading it sees an empty store however much the app wrote. The app group is the only
/// domain all of them share.
///
/// The group is named after the *host* app, and an extension's bundle id carries an extra
/// trailing component (`…Telegraph.NotificationService`). Rather than guessing how many
/// components to strip, each candidate is offered to the file coordinator and the first one
/// that actually resolves to a container wins.
///
/// Everything falls back to the app's own container when no group is available — a build
/// sideloaded without the entitlement, which AppDelegate already handles the same way. The
/// fork then behaves exactly as it did before this store existed: correct within the app,
/// invisible to extensions.
static void NGStoreResolveContainer(NSUserDefaults **outDefaults, NSString **outDirectory) {
    static NSUserDefaults *resolvedDefaults = nil;
    static NSString *resolvedDirectory = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSMutableArray<NSString *> *candidates = [NSMutableArray array];
        NSString *current = bundleId;
        while (current.length > 0) {
            [candidates addObject:current];
            NSRange lastDot = [current rangeOfString:@"." options:NSBackwardsSearch];
            if (lastDot.location == NSNotFound) {
                break;
            }
            current = [current substringToIndex:lastDot.location];
        }

        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *candidate in candidates) {
            NSString *groupName = [@"group." stringByAppendingString:candidate];
            NSURL *containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:groupName];
            if (containerUrl == nil) {
                continue;
            }
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:groupName];
            if (defaults == nil) {
                continue;
            }
            resolvedDefaults = defaults;
            resolvedDirectory = [containerUrl.path stringByAppendingPathComponent:NGStoreDirectoryName];
            break;
        }

        if (resolvedDefaults == nil) {
            resolvedDefaults = [NSUserDefaults standardUserDefaults];
            NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
            NSString *support = paths.firstObject;
            if (support != nil) {
                resolvedDirectory = [support stringByAppendingPathComponent:NGStoreDirectoryName];
            }
        }
    });

    if (outDefaults != NULL) {
        *outDefaults = resolvedDefaults;
    }
    if (outDirectory != NULL) {
        *outDirectory = resolvedDirectory;
    }
}

static NSUserDefaults *NGStoreDefaults(void) {
    NSUserDefaults *defaults = nil;
    NGStoreResolveContainer(&defaults, NULL);
    return defaults;
}

/// Created on demand, with the same protection class the file gets: readable once the device
/// has been unlocked a first time, which is what lets a background extension read it.
static NSString *NGStoreEnsureDirectory(void) {
    NSString *directory = nil;
    NGStoreResolveContainer(NULL, &directory);
    if (directory == nil) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:directory]) {
        NSDictionary *attributes = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
        [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:attributes error:NULL];
    }
    return directory;
}

static NSString *NGStoreFilePath(void) {
    NSString *directory = NGStoreEnsureDirectory();
    if (directory == nil) {
        return nil;
    }
    return [directory stringByAppendingPathComponent:NGStoreFileName];
}

#pragma mark - Disk

static NSDictionary<NSString *, id> *NGStoreReadFile(void) {
    NSString *path = NGStoreFilePath();
    if (path == nil) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return (NSDictionary<NSString *, id> *)object;
}

/// Written whole and atomically: a settings document is small, and a half-written one is
/// worse than a stale one. The protection class matches the directory's so a background
/// extension can still read it after the device has been unlocked once.
static void NGStoreWriteFile(NSDictionary<NSString *, id> *values) {
    NSString *path = NGStoreFilePath();
    if (path == nil) {
        return;
    }
    if (![NSJSONSerialization isValidJSONObject:values]) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:values options:NSJSONWritingSortedKeys error:NULL];
    if (data == nil) {
        return;
    }
    NSDataWritingOptions options = NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
    [data writeToFile:path options:options error:NULL];
}

/// Only values JSON can carry are kept. Everything the fork stores is a string, number,
/// boolean, array or dictionary of those, so nothing is lost in practice — the check is here
/// so one exotic future setting cannot make the whole document unwritable.
static BOOL NGStoreIsStorableValue(id value) {
    return value != nil && [NSJSONSerialization isValidJSONObject:@{@"v": value}];
}

static NSDictionary<NSString *, id> *NGStoreNetegramKeysOf(NSUserDefaults *defaults) {
    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, id> *representation = [defaults dictionaryRepresentation];
    for (NSString *key in representation) {
        if (![key hasPrefix:NGStoreKeyPrefixValue]) {
            continue;
        }
        id value = representation[key];
        if (NGStoreIsStorableValue(value)) {
            result[key] = value;
        }
    }
    return result;
}

static void NGStoreMirrorToDefaults(NSDictionary<NSString *, id> *values) {
    NSUserDefaults *defaults = NGStoreDefaults();
    for (NSString *key in values) {
        [defaults setObject:values[key] forKey:key];
    }
}

#pragma mark - Loading

/// Call with the lock held.
///
/// The file is authoritative. The defaults are a mirror, kept because they are cheap to read
/// and because the group suite is what a future reader is most likely to reach for — but if
/// they have lost the values and the file still has them, they are put back. That is the
/// self-heal: whatever emptied them, the next launch restores them instead of the user
/// finding the fork back at its factory state.
static void NGStoreLoadLocked(void) {
    if (NGStoreDidLoad) {
        return;
    }
    NGStoreDidLoad = YES;

    NSDictionary<NSString *, id> *fileValues = NGStoreReadFile();
    if (fileValues.count > 0) {
        NGStoreValues = [fileValues mutableCopy];
        NGStoreMirrorToDefaults(NGStoreValues);
        return;
    }

    // Nothing on disk yet: either a fresh install, or the first launch after the update that
    // introduced this store. Take whatever the old locations hold — the shared suite first,
    // then the app's own domain, which is where every setting lived before.
    NSDictionary<NSString *, id> *suiteValues = NGStoreNetegramKeysOf(NGStoreDefaults());
    NSMutableDictionary<NSString *, id> *migrated = [suiteValues mutableCopy];
    NSUserDefaults *standard = [NSUserDefaults standardUserDefaults];
    if (standard != NGStoreDefaults()) {
        NSDictionary<NSString *, id> *legacyValues = NGStoreNetegramKeysOf(standard);
        for (NSString *key in legacyValues) {
            if (migrated[key] == nil) {
                migrated[key] = legacyValues[key];
            }
        }
    }

    NGStoreValues = migrated;
    if (NGStoreValues.count > 0) {
        NGStoreWriteFile(NGStoreValues);
        NGStoreMirrorToDefaults(NGStoreValues);
    }
}

/// Call with the lock held. Re-reads the file after another process said it changed.
static void NGStoreReloadLocked(void) {
    NSDictionary<NSString *, id> *fileValues = NGStoreReadFile();
    NGStoreValues = fileValues != nil ? [fileValues mutableCopy] : [NSMutableDictionary dictionary];
    NGStoreDidLoad = YES;
}

#pragma mark - Change propagation

/// Always asynchronous, even when the caller is already on the main thread.
///
/// Observers of this notification typically guard a cache with a lock, and the code that
/// writes a value usually holds that same lock. Posting inline would re-enter it from within
/// the setter and deadlock on the first non-recursive NSLock. Deferring also means a burst of
/// writes made in one turn of the run loop is observed once things have settled.
static void NGStorePostLocalChange(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:NGStoreDidChangeNotificationValue object:nil];
    });
}

static void NGStoreDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;

    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreReloadLocked();
    [lock unlock];

    NGStorePostLocalChange();
}

/// Registered the first time anything touches the store, in every process that links it.
static void NGStoreEnsureDarwinObserver(void) {
    /// Held in a static rather than passed as an autoreleased temporary: the notification
    /// centre keeps the name for the lifetime of the observer, and an object it does not own
    /// outliving the pool is not something to rely on.
    static NSString *observedName = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        observedName = [NSString stringWithUTF8String:NGStoreDarwinNotificationName];
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            NGStoreDarwinCallback,
            (__bridge CFStringRef)observedName,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    });
}

/// Call without the lock held: the write has to be visible to the other processes before they
/// are told to look.
static void NGStoreCommit(NSDictionary<NSString *, id> *snapshot) {
    NGStoreWriteFile(snapshot);
    NGStoreMirrorToDefaults(snapshot);
    notify_post(NGStoreDarwinNotificationName);
    NGStorePostLocalChange();
}

#pragma mark - Accessors

static id NGStoreValueForKey(NSString *key) {
    NGStoreEnsureDarwinObserver();
    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreLoadLocked();
    id value = NGStoreValues[key];
    [lock unlock];
    return value;
}

/// Returns the snapshot to commit, or nil when nothing actually changed — a toggle set to the
/// value it already had must not cost a file write or wake the other processes.
static NSDictionary<NSString *, id> *NGStoreSetValueForKey(id value, NSString *key) {
    NGStoreEnsureDarwinObserver();
    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreLoadLocked();

    id existing = NGStoreValues[key];
    BOOL unchanged = (existing == nil && value == nil) || (existing != nil && value != nil && [existing isEqual:value]);
    if (unchanged) {
        [lock unlock];
        return nil;
    }

    if (value == nil) {
        [NGStoreValues removeObjectForKey:key];
    } else {
        NGStoreValues[key] = value;
    }
    NSDictionary<NSString *, id> *snapshot = [NGStoreValues copy];
    [lock unlock];
    return snapshot;
}

@implementation NGStore

+ (NSNotificationName)didChangeNotification {
    return NGStoreDidChangeNotificationValue;
}

+ (NSString *)keyPrefix {
    return NGStoreKeyPrefixValue;
}

+ (BOOL)boolForKey:(NSString *)key {
    id value = NGStoreValueForKey(key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

+ (NSInteger)integerForKey:(NSString *)key {
    id value = NGStoreValueForKey(key);
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

+ (double)doubleForKey:(NSString *)key {
    id value = NGStoreValueForKey(key);
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

+ (NSString *)stringForKey:(NSString *)key {
    id value = NGStoreValueForKey(key);
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

+ (NSArray<NSString *> *)stringArrayForKey:(NSString *)key {
    id value = NGStoreValueForKey(key);
    if (![value isKindOfClass:[NSArray class]]) {
        return nil;
    }
    for (id element in (NSArray *)value) {
        if (![element isKindOfClass:[NSString class]]) {
            return nil;
        }
    }
    return (NSArray<NSString *> *)value;
}

+ (NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)key {
    id value = NGStoreValueForKey(key);
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary<NSString *, id> *)value : nil;
}

+ (id)objectForKey:(NSString *)key {
    return NGStoreValueForKey(key);
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [NGStore setObject:@(value) forKey:key];
}

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [NGStore setObject:@(value) forKey:key];
}

+ (void)setDouble:(double)value forKey:(NSString *)key {
    [NGStore setObject:@(value) forKey:key];
}

+ (void)setObject:(id)value forKey:(NSString *)key {
    if (![key hasPrefix:NGStoreKeyPrefixValue]) {
        return;
    }
    if (value != nil && !NGStoreIsStorableValue(value)) {
        return;
    }
    NSDictionary<NSString *, id> *snapshot = NGStoreSetValueForKey(value, key);
    if (snapshot != nil) {
        if (value == nil) {
            [NGStoreDefaults() removeObjectForKey:key];
        }
        NGStoreCommit(snapshot);
    }
}

+ (void)removeObjectForKey:(NSString *)key {
    [NGStore setObject:nil forKey:key];
}

+ (NSDictionary<NSString *, id> *)allValues {
    NGStoreEnsureDarwinObserver();
    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreLoadLocked();
    NSDictionary<NSString *, id> *snapshot = [NGStoreValues copy];
    [lock unlock];
    return snapshot;
}

+ (void)applyValues:(NSDictionary<NSString *, id> *)values {
    NGStoreEnsureDarwinObserver();
    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreLoadLocked();
    for (NSString *key in values) {
        if (![key isKindOfClass:[NSString class]] || ![key hasPrefix:NGStoreKeyPrefixValue]) {
            continue;
        }
        id value = values[key];
        if (!NGStoreIsStorableValue(value)) {
            continue;
        }
        NGStoreValues[key] = value;
    }
    NSDictionary<NSString *, id> *snapshot = [NGStoreValues copy];
    [lock unlock];

    NGStoreCommit(snapshot);
}

+ (void)removeAllValues {
    NGStoreEnsureDarwinObserver();
    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreLoadLocked();
    NSArray<NSString *> *keys = NGStoreValues.allKeys;
    [NGStoreValues removeAllObjects];
    [lock unlock];

    NSUserDefaults *defaults = NGStoreDefaults();
    for (NSString *key in keys) {
        [defaults removeObjectForKey:key];
    }
    // The app's own domain too: values migrated out of it are still sitting there, and a
    // reinstall-free "reset everything" that leaves them behind would let them migrate back.
    NSUserDefaults *standard = [NSUserDefaults standardUserDefaults];
    if (standard != defaults) {
        for (NSString *key in NGStoreNetegramKeysOf(standard)) {
            [standard removeObjectForKey:key];
        }
    }

    NGStoreCommit(@{});
}

+ (NSString *)storageDirectory {
    return NGStoreEnsureDirectory();
}

+ (void)flush {
    NSLock *lock = NGStoreLock();
    [lock lock];
    NGStoreLoadLocked();
    NSDictionary<NSString *, id> *snapshot = [NGStoreValues copy];
    [lock unlock];

    NGStoreWriteFile(snapshot);
    [NGStoreDefaults() synchronize];
}

@end
