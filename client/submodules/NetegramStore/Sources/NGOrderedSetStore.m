#import <NetegramStore/NGOrderedSetStore.h>
#import <NetegramStore/NGStore.h>

/// How long appends are gathered before they reach the disk. Deletions arrive in bursts —
/// a channel clearing a day of posts is one difference — and each burst should cost one write,
/// not one per message. Short enough that a crash loses at most a moment of marks.
static const NSTimeInterval NGOrderedSetStoreSaveDelay = 1.0;

@interface NGOrderedSetStore () {
    NSString *_name;
    NSUInteger _limit;

    NSLock *_lock;
    /// Oldest first. Guarded by _lock, as is _members and _isDirty.
    NSMutableArray<NSString *> *_order;
    NSMutableSet<NSString *> *_members;
    BOOL _didLoad;
    BOOL _isDirty;

    dispatch_queue_t _queue;
}

@end

@implementation NGOrderedSetStore

- (instancetype)initWithName:(NSString *)name limit:(NSUInteger)limit {
    self = [super init];
    if (self != nil) {
        _name = [name copy];
        _limit = limit > 0 ? limit : 1;
        _lock = [[NSLock alloc] init];
        _order = [NSMutableArray array];
        _members = [NSMutableSet set];
        _queue = dispatch_queue_create("org.netegram.orderedSetStore", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Disk

- (NSString *)filePath {
    NSString *directory = [NGStore storageDirectory];
    if (directory == nil) {
        return nil;
    }
    return [directory stringByAppendingPathComponent:[_name stringByAppendingPathExtension:@"json"]];
}

/// Oldest first, so trimming takes from the front.
- (NSArray<NSString *> *)readFile {
    NSString *path = [self filePath];
    if (path == nil) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSArray class]]) {
        return nil;
    }
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id element in (NSArray *)object) {
        if ([element isKindOfClass:[NSString class]]) {
            [result addObject:(NSString *)element];
        }
    }
    return result;
}

- (void)writeFile:(NSArray<NSString *> *)values {
    NSString *path = [self filePath];
    if (path == nil) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:values options:0 error:NULL];
    if (data == nil) {
        return;
    }
    NSDataWritingOptions options = NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
    [data writeToFile:path options:options error:NULL];
}

#pragma mark - State

/// Call with the lock held.
- (void)loadLocked {
    if (_didLoad) {
        return;
    }
    _didLoad = YES;
    NSArray<NSString *> *stored = [self readFile];
    for (NSString *value in stored) {
        if (![_members containsObject:value]) {
            [_members addObject:value];
            [_order addObject:value];
        }
    }
    [self trimLocked];
}

/// Call with the lock held.
- (void)trimLocked {
    while (_order.count > _limit) {
        NSString *oldest = _order.firstObject;
        [_order removeObjectAtIndex:0];
        if (oldest != nil) {
            [_members removeObject:oldest];
        }
    }
}

#pragma mark - API

- (BOOL)containsObject:(NSString *)value {
    if (value == nil) {
        return NO;
    }
    [_lock lock];
    [self loadLocked];
    BOOL result = [_members containsObject:value];
    [_lock unlock];
    return result;
}

- (void)addObjects:(NSArray<NSString *> *)values {
    if (values.count == 0) {
        return;
    }

    [_lock lock];
    [self loadLocked];
    BOOL changed = NO;
    for (NSString *value in values) {
        if (![value isKindOfClass:[NSString class]] || [_members containsObject:value]) {
            continue;
        }
        [_members addObject:value];
        [_order addObject:value];
        changed = YES;
    }
    if (!changed) {
        [_lock unlock];
        return;
    }
    [self trimLocked];
    BOOL wasDirty = _isDirty;
    _isDirty = YES;
    [_lock unlock];

    // One timer per dirty period rather than one per call: a burst of deletions schedules a
    // single save, and the flag is cleared by whoever performs it.
    if (!wasDirty) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NGOrderedSetStoreSaveDelay * NSEC_PER_SEC)), _queue, ^{
            [self save];
        });
    }
}

- (void)flush {
    dispatch_sync(_queue, ^{
        [self save];
    });
}

/// Runs on _queue, so two saves never interleave.
///
/// Re-reads before writing and keeps the union: the notification service appends to this same
/// file while the app holds its own copy in memory, and replacing the file wholesale would
/// drop whatever the other process recorded. Order is taken from the file first so that the
/// oldest entries — whichever process wrote them — are the ones trimming removes.
- (void)save {
    [_lock lock];
    if (!_isDirty) {
        [_lock unlock];
        return;
    }
    _isDirty = NO;
    [self loadLocked];
    NSArray<NSString *> *mine = [_order copy];
    [_lock unlock];

    NSArray<NSString *> *stored = [self readFile];
    NSMutableArray<NSString *> *merged = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSArray<NSString *> *source in @[stored ?: @[], mine]) {
        for (NSString *value in source) {
            if (![seen containsObject:value]) {
                [seen addObject:value];
                [merged addObject:value];
            }
        }
    }
    while (merged.count > _limit) {
        [merged removeObjectAtIndex:0];
    }

    [self writeFile:merged];

    // Adopt the merged view, so entries the other process contributed are visible here without
    // waiting for a relaunch.
    [_lock lock];
    [_order setArray:merged];
    [_members setSet:[NSSet setWithArray:merged]];
    [_lock unlock];
}

@end
