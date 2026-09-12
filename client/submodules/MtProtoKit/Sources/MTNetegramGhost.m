#import <MtProtoKit/MTNetegramGhost.h>

#import <NetegramStore/NGStore.h>

NSString * const MTNetegramDelayedSendStartedNotification = @"MTNetegramDelayedSendStarted";

// Constructor ids of the functions ghost mode cares about. They are part of the TL schema and
// change only when the schema does; the comments carry the schema name so a mismatch after a
// layer bump is traceable.
static const int32_t MTGhostAccountUpdateStatus = 1713919532;      // account.updateStatus
static const int32_t MTGhostMessagesSetTyping = 1486110434;        // messages.setTyping
static const int32_t MTGhostMessagesReadHistory = 238054714;       // messages.readHistory
static const int32_t MTGhostChannelsReadHistory = -871347913;      // channels.readHistory
static const int32_t MTGhostStoriesReadStories = -1521034552;      // stories.readStories
static const int32_t MTGhostReadMessageContents = 917472119;       // messages.readMessageContents
static const int32_t MTGhostScreenshotNotification = -1589618665;  // messages.sendScreenshotNotification
static const int32_t MTGhostGetSponsoredMessages = -1680673735;    // messages.getSponsoredMessages
static const int32_t MTGhostReadReactions = -1420459918;           // messages.readReactions
static const int32_t MTGhostReadDiscussion = -147740172;           // messages.readDiscussion
static const int32_t MTGhostReadMentions = 921026381;              // messages.readMentions
// Secret chats carry typing over their own encrypted envelope — a call entirely separate from
// messages.setTyping above. Missing this meant the "typing" toggle silently did nothing in
// secret chats, which is exactly backwards for a chat kind chosen for privacy.
static const int32_t MTGhostSetEncryptedTyping = 2031374829;       // messages.setEncryptedTyping

// Outgoing calls that count as "I did something in this chat", for read-on-action. All of
// them are flags:# followed by peer:InputPeer, which is what makes one shared parser enough.
static const int32_t MTGhostSendMessage = -17526942;               // messages.sendMessage
static const int32_t MTGhostSendMedia = 53536639;                  // messages.sendMedia
static const int32_t MTGhostSendMultiMedia = 469278068;            // messages.sendMultiMedia
static const int32_t MTGhostSendReaction = -754091820;             // messages.sendReaction

/// How long after acting in a chat a read receipt is still allowed through. The client issues
/// the read a moment after the send completes, not in the same breath, so the window has to
/// outlast a slow round trip without being wide enough to leak an unrelated chat.
static const NSTimeInterval MTGhostActionWindow = 60.0;

// sendMessageAction constructors, in the order they appear on the ghost screen.
static const int32_t MTGhostActionTyping = 381645902;
static const int32_t MTGhostActionRecordVideo = -1584933265;
static const int32_t MTGhostActionUploadVideo = -378127636;
static const int32_t MTGhostActionRecordAudio = -718310409;
static const int32_t MTGhostActionUploadAudio = -212740181;
static const int32_t MTGhostActionUploadPhoto = -774682074;
static const int32_t MTGhostActionUploadDocument = -1441998364;
static const int32_t MTGhostActionGeoLocation = 393186209;
static const int32_t MTGhostActionChooseContact = 1653390447;
static const int32_t MTGhostActionGamePlay = -580219064;
static const int32_t MTGhostActionRecordRound = -1997373508;
static const int32_t MTGhostActionUploadRound = 608050278;
static const int32_t MTGhostActionSpeakingInGroupCall = -651419003;
static const int32_t MTGhostActionChooseSticker = -1336228175;
static const int32_t MTGhostActionEmojiInteraction = 630664139;
static const int32_t MTGhostActionEmojiInteractionSeen = -1234857938;

// InputPeer constructors — needed to walk past the peer and reach the action in setTyping.
static const int32_t MTGhostInputPeerEmpty = 2134579434;
static const int32_t MTGhostInputPeerSelf = 2107670217;
static const int32_t MTGhostInputPeerChat = 900291769;
static const int32_t MTGhostInputPeerUser = -571955892;
static const int32_t MTGhostInputPeerChannel = 666680316;
static const int32_t MTGhostInputPeerUserFromMessage = -1468331492;
static const int32_t MTGhostInputPeerChannelFromMessage = -1121318848;

/// Keys are mirrored in NetegramGhost (SettingsUI). MTProtoKit sits far below the app's
/// settings modules and cannot import them, so the store is read directly.
///
/// NGStore rather than NSUserDefaults: this code runs inside the notification service and the
/// share extension too, and a preferences domain there is the extension's own — every ghost
/// flag read as NO however the user had set it.
static BOOL MTGhostFlag(NSString *key) {
    return [NGStore boolForKey:key];
}

#pragma mark - Fabricated responses

/// boolTrue#997275b5 — what most "notify the server" calls return on success.
static NSData *MTGhostBoolTrue(void) {
    const uint8_t bytes[] = {0xB5, 0x75, 0x72, 0x99};
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

/// messages.affectedMessages#84d19185 with pts=0, pts_count=0 — "nothing changed".
static NSData *MTGhostAffectedMessages(void) {
    const uint8_t header[] = {0x85, 0x91, 0xD1, 0x84};
    int32_t pts = 0;
    int32_t ptsCount = 0;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:header length:sizeof(header)];
    [data appendBytes:&pts length:sizeof(pts)];
    [data appendBytes:&ptsCount length:sizeof(ptsCount)];
    return data;
}

/// messages.affectedHistory#b45c69d1 with pts=0, pts_count=0, offset=0 — readMentions answers
/// with this shape rather than affectedMessages's, one field longer.
static NSData *MTGhostAffectedHistory(void) {
    const uint8_t header[] = {0xD1, 0x69, 0x5C, 0xB4};
    int32_t pts = 0;
    int32_t ptsCount = 0;
    int32_t offset = 0;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:header length:sizeof(header)];
    [data appendBytes:&pts length:sizeof(pts)];
    [data appendBytes:&ptsCount length:sizeof(ptsCount)];
    [data appendBytes:&offset length:sizeof(offset)];
    return data;
}

/// An empty vector#1cb5c415.
static NSData *MTGhostEmptyVector(void) {
    const uint8_t header[] = {0x15, 0xC4, 0xB5, 0x1C};
    int32_t count = 0;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:header length:sizeof(header)];
    [data appendBytes:&count length:sizeof(count)];
    return data;
}

/// messages.sponsoredMessagesEmpty#1839490f
static NSData *MTGhostSponsoredEmpty(void) {
    const uint8_t header[] = {0x0F, 0x49, 0x39, 0x18};
    return [NSData dataWithBytes:header length:sizeof(header)];
}

#pragma mark - Payload walking

static BOOL MTGhostReadInt32(NSData *data, NSUInteger *offset, int32_t *value) {
    if (*offset + 4 > data.length) {
        return NO;
    }
    [data getBytes:value range:NSMakeRange(*offset, 4)];
    *offset += 4;
    return YES;
}

/// Advances `offset` past an InputPeer. Returns NO if the payload is shorter than the peer
/// claims to be, which means the layout is not what this code expects and the caller must
/// leave the request alone rather than guess.
static BOOL MTGhostSkipInputPeer(NSData *data, NSUInteger *offset) {
    int32_t constructor = 0;
    if (!MTGhostReadInt32(data, offset, &constructor)) {
        return NO;
    }

    NSUInteger extra = 0;
    if (constructor == MTGhostInputPeerEmpty || constructor == MTGhostInputPeerSelf) {
        extra = 0;
    } else if (constructor == MTGhostInputPeerChat) {
        extra = 8;
    } else if (constructor == MTGhostInputPeerUser || constructor == MTGhostInputPeerChannel) {
        extra = 16;
    } else if (constructor == MTGhostInputPeerUserFromMessage || constructor == MTGhostInputPeerChannelFromMessage) {
        // peer, msg_id, then the user/channel id.
        if (!MTGhostSkipInputPeer(data, offset)) {
            return NO;
        }
        extra = 12;
    } else {
        return NO;
    }

    if (*offset + extra > data.length) {
        return NO;
    }
    *offset += extra;
    return YES;
}

/// Identifies a chat across the several InputPeer shapes that can name it.
///
/// Only the id is used, not the access hash: the hash is refreshed by the server from time to
/// time, and a chat that changed its hash between the send and the read would look like a
/// different chat and lose its exemption.
static NSString *MTGhostPeerKey(NSData *data, NSUInteger *offset) {
    NSUInteger start = *offset;
    int32_t constructor = 0;
    if (!MTGhostReadInt32(data, offset, &constructor)) {
        return nil;
    }
    *offset = start;
    if (!MTGhostSkipInputPeer(data, offset)) {
        return nil;
    }
    if (constructor == MTGhostInputPeerEmpty || constructor == MTGhostInputPeerSelf) {
        return nil;
    }
    // The id is the first field of every non-empty InputPeer, right after the constructor.
    if (start + 12 > data.length) {
        return nil;
    }
    int64_t peerId = 0;
    [data getBytes:&peerId range:NSMakeRange(start + 4, 8)];
    return [NSString stringWithFormat:@"%lld", (long long)peerId];
}

/// Chats acted in recently. Small, short-lived, and only touched from the request queue plus
/// whatever thread builds a request — hence the lock.
static NSMutableDictionary<NSString *, NSNumber *> *MTGhostRecentActions(void) {
    static NSMutableDictionary *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dict = [[NSMutableDictionary alloc] init];
    });
    return dict;
}

static NSLock *MTGhostActionsLock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

static void MTGhostNoteAction(NSData *payload) {
    NSUInteger offset = 8; // constructor + flags
    NSString *key = MTGhostPeerKey(payload, &offset);
    if (key == nil) {
        return;
    }
    NSLock *lock = MTGhostActionsLock();
    [lock lock];
    MTGhostRecentActions()[key] = @([NSDate date].timeIntervalSince1970);
    [lock unlock];
}

static BOOL MTGhostActedRecently(NSData *payload) {
    NSUInteger offset = 4; // messages.readHistory has no flags
    NSString *key = MTGhostPeerKey(payload, &offset);
    if (key == nil) {
        return NO;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSLock *lock = MTGhostActionsLock();
    [lock lock];
    NSMutableDictionary *actions = MTGhostRecentActions();
    NSNumber *stamp = actions[key];
    BOOL recent = stamp != nil && (now - stamp.doubleValue) < MTGhostActionWindow;
    // Drop stale entries while we are holding the lock anyway, so the dictionary cannot grow
    // without bound over a long session.
    for (NSString *staleKey in actions.allKeys) {
        if (now - [actions[staleKey] doubleValue] >= MTGhostActionWindow) {
            [actions removeObjectForKey:staleKey];
        }
    }
    [lock unlock];
    return recent;
}

/// Returns the UserDefaults key guarding a given sendMessageAction, or nil if the action is
/// not one ghost mode offers to hide.
static NSString *MTGhostKeyForAction(int32_t actionId) {
    if (actionId == MTGhostActionTyping) return @"netegram.ghost.typing";
    if (actionId == MTGhostActionRecordVideo) return @"netegram.ghost.recordVideo";
    if (actionId == MTGhostActionUploadVideo) return @"netegram.ghost.uploadVideo";
    if (actionId == MTGhostActionRecordAudio) return @"netegram.ghost.recordVoice";
    if (actionId == MTGhostActionUploadAudio) return @"netegram.ghost.uploadVoice";
    if (actionId == MTGhostActionUploadPhoto) return @"netegram.ghost.uploadPhoto";
    if (actionId == MTGhostActionUploadDocument) return @"netegram.ghost.uploadFile";
    if (actionId == MTGhostActionGeoLocation) return @"netegram.ghost.chooseLocation";
    if (actionId == MTGhostActionChooseContact) return @"netegram.ghost.chooseContact";
    if (actionId == MTGhostActionGamePlay) return @"netegram.ghost.playGame";
    if (actionId == MTGhostActionRecordRound) return @"netegram.ghost.recordRound";
    if (actionId == MTGhostActionUploadRound) return @"netegram.ghost.uploadRound";
    if (actionId == MTGhostActionSpeakingInGroupCall) return @"netegram.ghost.speaking";
    if (actionId == MTGhostActionChooseSticker) return @"netegram.ghost.chooseSticker";
    if (actionId == MTGhostActionEmojiInteraction) return @"netegram.ghost.emojiInteraction";
    if (actionId == MTGhostActionEmojiInteractionSeen) return @"netegram.ghost.emojiSeen";
    return nil;
}

/// The sendMessageAction a fake-activity kind goes out as. Mirrors NetegramFakeActivityKind
/// (SettingsUI) and the PeerInputActivity each kind maps to there.
static int32_t MTGhostActionForFakeKind(NSString *kind) {
    if ([kind isEqualToString:@"typing"]) return MTGhostActionTyping;
    if ([kind isEqualToString:@"recordingVoice"]) return MTGhostActionRecordAudio;
    if ([kind isEqualToString:@"uploadingVoice"]) return MTGhostActionUploadDocument;
    if ([kind isEqualToString:@"recordingRound"]) return MTGhostActionRecordRound;
    if ([kind isEqualToString:@"uploadingRound"]) return MTGhostActionUploadRound;
    if ([kind isEqualToString:@"uploadingPhoto"]) return MTGhostActionUploadPhoto;
    if ([kind isEqualToString:@"uploadingVideo"]) return MTGhostActionUploadVideo;
    if ([kind isEqualToString:@"uploadingFile"]) return MTGhostActionUploadDocument;
    if ([kind isEqualToString:@"choosingSticker"]) return MTGhostActionChooseSticker;
    if ([kind isEqualToString:@"playingGame"]) return MTGhostActionGamePlay;
    return 0;
}

/// True when this setTyping is the fake activity the user asked for, which ghost mode must not
/// swallow: hiding "typing" everywhere and showing it to one chosen person on purpose are both
/// the user's instructions, and the specific one wins.
///
/// Matched on the chat and the exact action, so a real action of another kind to the same
/// person is still hidden as ghost mode says. Ids are the bare Telegram ids SettingsUI writes
/// next to the peer list.
static BOOL MTGhostIsFakeActivity(NSString *peerKey, int32_t actionId) {
    if (peerKey == nil || ![NGStore boolForKey:@"netegram.fake.activityEnabled"]) {
        return NO;
    }
    NSString *kind = [NGStore stringForKey:@"netegram.fake.activityKind"];
    if (kind == nil) {
        kind = @"typing";
    }
    if (MTGhostActionForFakeKind(kind) != actionId) {
        return NO;
    }
    return [[NGStore stringArrayForKey:@"netegram.fake.activityRawIds"] containsObject:peerKey];
}

/// True when the chat is on the "read without opening" list, whose reads must reach the
/// sender even while ghost mode hides read receipts elsewhere.
static BOOL MTGhostIsFakeRead(NSString *peerKey) {
    if (peerKey == nil || ![NGStore boolForKey:@"netegram.fake.readEnabled"]) {
        return NO;
    }
    return [[NGStore stringArrayForKey:@"netegram.fake.readRawIds"] containsObject:peerKey];
}

/// channels.readHistory names its chat with an InputChannel rather than an InputPeer. Only the
/// plain inputChannel#f35aec28 carries the id directly; anything else is left unmatched.
static NSString *MTGhostChannelKey(NSData *payload) {
    NSUInteger offset = 4;
    int32_t constructor = 0;
    if (!MTGhostReadInt32(payload, &offset, &constructor)) {
        return nil;
    }
    if ((uint32_t)constructor != 0xf35aec28 || offset + 8 > payload.length) {
        return nil;
    }
    int64_t channelId = 0;
    [payload getBytes:&channelId range:NSMakeRange(offset, 8)];
    return [NSString stringWithFormat:@"%lld", (long long)channelId];
}

/// account.updateStatus#6628562c offline:Bool
///
/// The client sends offline=true when it stops being in the foreground and offline=false when
/// it comes back. Hiding the online status means suppressing the "I am back" call; staying
/// always online means suppressing the "I am away" one. They are opposites, which is why the
/// two switches cannot both be on.
static BOOL MTGhostShouldBlockUpdateStatus(NSData *payload) {
    if (payload.length < 8) {
        return NO;
    }
    int32_t offlineFlag = 0;
    [payload getBytes:&offlineFlag range:NSMakeRange(payload.length - 4, 4)];
    // boolTrue#997275b5 reads as -1720552011 when taken as a signed int32.
    BOOL goingOffline = (uint32_t)offlineFlag == 0x997275b5;

    if (goingOffline) {
        return MTGhostFlag(@"netegram.ghost.alwaysOnline");
    }
    return MTGhostFlag(@"netegram.ghost.hideOnline");
}

static BOOL MTGhostShouldBlockSetTyping(NSData *payload) {
    NSUInteger offset = 4;
    int32_t flags = 0;
    if (!MTGhostReadInt32(payload, &offset, &flags)) {
        return NO;
    }
    NSUInteger peerOffset = offset;
    NSString *peerKey = MTGhostPeerKey(payload, &peerOffset);
    if (!MTGhostSkipInputPeer(payload, &offset)) {
        return NO;
    }
    if ((flags & (1 << 0)) != 0) {
        offset += 4; // top_msg_id
    }
    int32_t actionId = 0;
    if (!MTGhostReadInt32(payload, &offset, &actionId)) {
        return NO;
    }
    if (MTGhostIsFakeActivity(peerKey, actionId)) {
        return NO;
    }
    NSString *key = MTGhostKeyForAction(actionId);
    return key != nil && MTGhostFlag(key);
}

/// Bumped by every cancel. A send scheduled in an older generation gives up when it wakes.
///
/// A counter rather than a list of pending sends: cancelling means "not the ones in flight",
/// and comparing one integer needs no bookkeeping that could leak or go stale.
static NSInteger MTGhostSendGeneration = 0;

@implementation MTNetegramGhost

+ (NSTimeInterval)sendDelayForPayload:(NSData *)payload {
    if (payload.length < 4) {
        return 0.0;
    }
    if (!MTGhostFlag(@"netegram.ghost.delayedSend")) {
        return 0.0;
    }

    int32_t functionId = 0;
    [payload getBytes:&functionId length:4];
    if (functionId != MTGhostSendMessage && functionId != MTGhostSendMedia && functionId != MTGhostSendMultiMedia) {
        return 0.0;
    }

    NSInteger seconds = [NGStore integerForKey:@"netegram.ghost.delayedSendSeconds"];
    if (seconds <= 0) {
        seconds = 5;
    }
    return (NSTimeInterval)seconds;
}

+ (void)cancelDelayedSends {
    @synchronized (self) {
        MTGhostSendGeneration += 1;
    }
}

+ (BOOL)isDelayedSendCancelled:(NSInteger)generation {
    @synchronized (self) {
        return generation != MTGhostSendGeneration;
    }
}

+ (NSInteger)currentDelayedSendGeneration {
    @synchronized (self) {
        return MTGhostSendGeneration;
    }
}

+ (nullable NSData *)fakeResponseForPayload:(NSData *)payload {
    if (payload.length < 4) {
        return nil;
    }

    int32_t functionId = 0;
    [payload getBytes:&functionId length:4];

    if (functionId == MTGhostGetSponsoredMessages) {
        return MTGhostFlag(@"netegram.ghost.noAds") ? MTGhostSponsoredEmpty() : nil;
    }

    if (functionId == MTGhostAccountUpdateStatus) {
        return MTGhostShouldBlockUpdateStatus(payload) ? MTGhostBoolTrue() : nil;
    }
    if (functionId == MTGhostMessagesSetTyping) {
        return MTGhostShouldBlockSetTyping(payload) ? MTGhostBoolTrue() : nil;
    }
    if (functionId == MTGhostSetEncryptedTyping) {
        // Secret chats only ever send the plain typing signal — there is no per-action
        // breakdown to parse here, unlike the ordinary setTyping call above.
        return MTGhostFlag(@"netegram.ghost.typing") ? MTGhostBoolTrue() : nil;
    }
    if (functionId == MTGhostSendMessage || functionId == MTGhostSendMedia ||
        functionId == MTGhostSendMultiMedia || functionId == MTGhostSendReaction) {
        // Never blocked — only remembered, so a later read in the same chat can be let through.
        MTGhostNoteAction(payload);
        return nil;
    }
    if (functionId == MTGhostMessagesReadHistory) {
        if (!MTGhostFlag(@"netegram.ghost.readReceipts")) {
            return nil;
        }
        NSUInteger peerOffset = 4; // messages.readHistory has no flags
        if (MTGhostIsFakeRead(MTGhostPeerKey(payload, &peerOffset))) {
            return nil;
        }
        // Answering someone and then leaving their message on one tick is a stranger signal
        // than the tick itself, so acting in a chat lifts the block for that chat.
        if (MTGhostFlag(@"netegram.ghost.readOnAction") && MTGhostActedRecently(payload)) {
            return nil;
        }
        return MTGhostAffectedMessages();
    }
    if (functionId == MTGhostChannelsReadHistory) {
        if (!MTGhostFlag(@"netegram.ghost.readReceipts")) {
            return nil;
        }
        if (MTGhostIsFakeRead(MTGhostChannelKey(payload))) {
            return nil;
        }
        return MTGhostBoolTrue();
    }
    if (functionId == MTGhostReadDiscussion) {
        return MTGhostFlag(@"netegram.ghost.readReceipts") ? MTGhostBoolTrue() : nil;
    }
    if (functionId == MTGhostReadMentions) {
        // A separate call from readHistory: opening a chat can clear the @-mention badge
        // without the rest of the history being marked read, or the other way round, so this
        // needs its own switch rather than riding on the general read-receipts one.
        return MTGhostFlag(@"netegram.ghost.readMentions") ? MTGhostAffectedHistory() : nil;
    }
    if (functionId == MTGhostReadReactions) {
        return MTGhostFlag(@"netegram.ghost.readReceipts") ? MTGhostAffectedMessages() : nil;
    }
    if (functionId == MTGhostStoriesReadStories) {
        return MTGhostFlag(@"netegram.ghost.storyViews") ? MTGhostEmptyVector() : nil;
    }
    if (functionId == MTGhostReadMessageContents) {
        return MTGhostFlag(@"netegram.ghost.viewOnce") ? MTGhostAffectedMessages() : nil;
    }
    if (functionId == MTGhostScreenshotNotification) {
        return MTGhostFlag(@"netegram.ghost.screenshots") ? MTGhostBoolTrue() : nil;
    }

    return nil;
}

@end
