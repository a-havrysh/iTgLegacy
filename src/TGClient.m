#import "TGClient+Private.h"
#import "TGClient+Notifications.h"
#import "TGClient+Stories.h"
#import "TGCall.h"
#import "TGBackgroundSession.h"
#import "TGDiskCache.h"
#import "TGRemoteImageView.h"
#import "AppDelegate.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include "api_id.h"



static NSDictionary *TGFlattenMessage(NSDictionary *m);
static NSDictionary *TGUserStatusInfo(NSDictionary *status);
static NSString *TGMessagePreview(NSDictionary *message);

static NSString *TGActiveUsername(NSDictionary *user) {
	NSArray *active = user[@"usernames"][@"active_usernames"];
	if (![active isKindOfClass:NSArray.class] || !active.count)
		return nil;
	NSString *name = [active objectAtIndex:0];
	return [name isKindOfClass:NSString.class] ? name : nil;
}

/// TDLib ships `bytes` fields as base64 text. iOS 6 has no public decoder
/// (-initWithBase64EncodedString:options: arrived in iOS 7), so decode by hand.
/// A missing or wrong-typed value answers empty data, never nil.
static NSData *TGCliBase64(id value) {
	NSString *encoded = [value isKindOfClass:NSString.class] ? value : nil;
	if (!encoded.length)
		return [NSData data];

	static signed char table[256];
	static BOOL ready = NO;
	if (!ready){
		static const char *alphabet =
				"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 256; i++)
			table[i] = -1;
		for (int i = 0; i < 64; i++)
			table[(unsigned char)alphabet[i]] = (signed char)i;
		table[(unsigned char)'-'] = 62;
		table[(unsigned char)'_'] = 63;
		ready = YES;
	}

	NSMutableData *out = nil;
	@autoreleasepool {
		NSData *ascii = [encoded dataUsingEncoding:NSASCIIStringEncoding];
		const unsigned char *src = ascii.bytes;
		NSUInteger length = ascii.length;
		out = [[NSMutableData alloc] initWithCapacity:(length / 4) * 3 + 3];
		unsigned char chunk[3072];
		NSUInteger filled = 0;
		unsigned int accumulator = 0;
		int bits = 0;
		for (NSUInteger i = 0; i < length; i++){
			signed char decoded = table[src[i]];
			if (decoded < 0)
				continue;
			accumulator = (accumulator << 6) | (unsigned int)decoded;
			bits += 6;
			if (bits >= 8){
				bits -= 8;
				chunk[filled++] = (unsigned char)((accumulator >> bits) & 0xFF);
				if (filled == sizeof(chunk)){
					[out appendBytes:chunk length:filled];
					filled = 0;
				}
			}
		}
		if (filled)
			[out appendBytes:chunk length:filled];
	}
	return out;
}

static const NSTimeInterval TGRequestDeadline = 300.0;
static const NSTimeInterval TGRequestSweepInterval = 30.0;

@interface TGClient ()
@property (nonatomic, assign) NSTimeInterval lastPendingSweep;
@end

@implementation TGClient

+ (instancetype)shared {
	static TGClient *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		s = [[TGClient alloc] init];
		s.chatsById = [NSMutableDictionary dictionary];
		s.usersById = [NSMutableDictionary dictionary];
		s.userPhotosById = [NSMutableDictionary dictionary];
		s.forumSupergroups = [NSMutableDictionary dictionary];
		s.archivedChats = @[];
		s.folders = @[];
		s.chats = @[];
		s.outbox = [NSMutableArray array];
		s.pendingRequests = [NSMutableDictionary dictionary];
		s.fileWaiters = [NSMutableDictionary dictionary];
		s.outboxLock = [[NSLock alloc] init];
	});
	return s;
}

#pragma mark - lifecycle

- (BOOL)start {
	if (self.running)
		return self.available;

	NSString *path = [[NSBundle mainBundle].bundlePath
			stringByAppendingPathComponent:@"libtdjson.dylib"];

	TGMemMark(@"before dlopen tdjson");
	self.handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
	TGMemMark(@"after dlopen tdjson");
	if (!self.handle){
		NSLog(@"TGClient: dlopen failed: %s", dlerror());
		return NO;
	}

	td_create_fn create = dlsym(self.handle, "td_json_client_create");
	td_exec_fn   exec   = dlsym(self.handle, "td_json_client_execute");
	self.td_send = dlsym(self.handle, "td_json_client_send");
	self.td_recv = dlsym(self.handle, "td_json_client_receive");
	if (!create || !self.td_send || !self.td_recv){
		NSLog(@"TGClient: missing td_json_client_* symbols");
		return NO;
	}

	if (exec)
		exec(NULL, "{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":1}");

	[[TGBackgroundSession shared] attachToTDLibHandle:self.handle];

	self.client = create();
	TGMemMark(@"after td_json_client_create");
	if (!self.client){
		NSLog(@"TGClient: td_json_client_create returned NULL");
		return NO;
	}

	self.available = YES;
	self.running = YES;
	[self watchApplicationState];

	// The single-threaded ClientManager creates its scheduler lazily, on the
	// first request - without this nothing ever runs and no update arrives.
	// Queued before the thread starts so it goes out on the receive thread.
	[self send:@{@"@type" : @"getAuthorizationState"}];

	// TDLib runs single-threaded on armv7 (no thread-local storage), so its
	// scheduler only advances while we are inside td_json_client_receive.
	// Keep one thread parked in it.
	[NSThread detachNewThreadSelector:@selector(receiveLoop) toTarget:self withObject:nil];

	NSLog(@"TGClient: started");
	return YES;
}

- (void)watchApplicationState {
	__weak typeof(self) weakSelf = self;
	NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
	[centre addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *__unused note){
		weakSelf.idlePolling = YES;
	}];
	[centre addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *__unused note){
		weakSelf.idlePolling = NO;
	}];
}

- (void)receiveLoop {
	dispatch_semaphore_t slots = dispatch_semaphore_create(48);

	while (self.running){
		@autoreleasepool {
			[self drainOutbox];

			const char *res = self.td_recv(self.client, self.idlePolling ? 1.0 : 0.05);
			if (!res)
				continue;

			[[TGBackgroundSession shared] noteDataReceived];

			NSData *data = [NSData dataWithBytes:res length:strlen(res)];
			NSError *err = nil;
			NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data
															   options:0
																 error:&err];
			if (![obj isKindOfClass:NSDictionary.class]){
				NSLog(@"TGClient: bad JSON: %@", err);
				continue;
			}

			dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
			dispatch_async(dispatch_get_main_queue(), ^{
				@autoreleasepool {
					[self handleUpdate:obj];
				}
				dispatch_semaphore_signal(slots);
			});
		}
	}
}

#pragma mark - sending

// The single-threaded ClientManager requires send and receive on the SAME
// thread: sending from elsewhere while the receive loop holds the scheduler
// guard aborts on `Scheduler.cpp:126 Check !scheduler_->has_guard_ failed`.
// So callers only enqueue here, and the receive thread does the sending.
- (BOOL)requestSurvivesUninitialised:(NSDictionary *)request {
	NSString *type = request[@"@type"];
	return [type isEqualToString:@"setTdlibParameters"] ||
		   [type isEqualToString:@"getAuthorizationState"] ||
		   [type isEqualToString:@"setLogVerbosityLevel"] ||
		   [type isEqualToString:@"setLogStream"];
}

- (void)sendUnguarded:(NSDictionary *)request {
	NSError *err = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&err];
	if (!data){
		NSLog(@"TGClient: cannot encode %@: %@", request, err);
		return;
	}

	NSMutableData *z = [[NSMutableData alloc] initWithCapacity:data.length + 1];
	[z appendData:data];
	[z appendBytes:"\0" length:1];

	[self.outboxLock lock];
	[self.outbox addObject:z];
	[self.outboxLock unlock];
}

- (void)send:(NSDictionary *)request {
	if (!self.parametersSent && ![self requestSurvivesUninitialised:request]){
		if (!self.preInitRequests)
			self.preInitRequests = [NSMutableArray array];
		[self.preInitRequests addObject:request];
		return;
	}

	NSError *err = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&err];
	if (!data){
		NSLog(@"TGClient: cannot encode %@: %@", request, err);
		return;
	}

	NSMutableData *z = [[NSMutableData alloc] initWithCapacity:data.length + 1];
	[z appendData:data];
	[z appendBytes:"\0" length:1];

	[self.outboxLock lock];
	[self.outbox addObject:z];
	[self.outboxLock unlock];
}

/// Runs on the receive thread only.
- (void)drainOutbox {
	if (!self.available)
		return;

	NSArray *pending = nil;
	[self.outboxLock lock];
	if (self.outbox.count){
		pending = [self.outbox copy];
		[self.outbox removeAllObjects];
	}
	[self.outboxLock unlock];
	if (!pending)
		return;

	for (NSData *d in pending)
		self.td_send(self.client, d.bytes);
}

- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
	if (!completion){
		[self send:request];
		return;
	}
	NSString *extra = [NSString stringWithFormat:@"r%lu", (unsigned long)(++self.requestSeq)];
	self.pendingRequests[extra] = @{
		@"block"    : [completion copy],
		@"deadline" : @([NSDate timeIntervalSinceReferenceDate] + TGRequestDeadline),
	};

	NSMutableDictionary *withExtra = [request mutableCopy];
	withExtra[@"@extra"] = extra;
	[self send:withExtra];
}

#pragma mark - updates

- (void)failPendingRequests:(NSString *)reason {
	if (!self.pendingRequests.count)
		return;
	NSArray *entries = [self.pendingRequests allValues];
	[self.pendingRequests removeAllObjects];
	NSDictionary *error = @{@"@type"   : @"error",
							@"code"    : @(500),
							@"message" : reason ?: @"request abandoned"};
	for (NSDictionary *entry in entries){
		void (^completion)(NSDictionary *) = entry[@"block"];
		if (completion)
			completion(error);
	}
}

- (void)sweepPendingRequests {
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.lastPendingSweep < TGRequestSweepInterval)
		return;
	self.lastPendingSweep = now;
	if (!self.pendingRequests.count)
		return;

	NSMutableArray *expired = [NSMutableArray array];
	for (NSString *key in [self.pendingRequests allKeys]){
		NSDictionary *entry = self.pendingRequests[key];
		if ([entry[@"deadline"] doubleValue] > now)
			continue;
		[expired addObject:entry];
		[self.pendingRequests removeObjectForKey:key];
	}
	if (!expired.count)
		return;

	NSDictionary *error = @{@"@type"   : @"error",
							@"code"    : @(500),
							@"message" : @"request timed out"};
	for (NSDictionary *entry in expired){
		void (^completion)(NSDictionary *) = entry[@"block"];
		if (completion)
			completion(error);
	}
}

- (void)handleUpdate:(NSDictionary *)obj {
	[self sweepPendingRequests];

	// A reply to one of our requests: route it and stop.
	NSString *extra = obj[@"@extra"];
	if ([extra isKindOfClass:NSString.class]){
		NSDictionary *entry = self.pendingRequests[extra];
		void (^completion)(NSDictionary *) = entry[@"block"];
		if (completion){
			[self.pendingRequests removeObjectForKey:extra];
			completion(obj);
			return;
		}
	}
	NSString *type = obj[@"@type"];

	// Log each response kind once - enough to see what TDLib actually sends
	// without dumping the user's messages into the log.
	static NSMutableSet *seen = nil;
	if (!seen) seen = [NSMutableSet set];
	if (type && ![seen containsObject:type]){
		[seen addObject:type];
		NSLog(@"TGClient: first %@", type);
	}

	if ([type hasPrefix:@"updateNotification"] ||
		[type isEqualToString:@"updateActiveNotifications"] ||
		[type isEqualToString:@"updateHavePendingNotifications"] ||
		[type isEqualToString:@"updateChatNotificationSettings"] ||
		[type isEqualToString:@"updateScopeNotificationSettings"] ||
		[type isEqualToString:@"updateChatReadInbox"] ||
		[type isEqualToString:@"updateUnreadMessageCount"]){
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGNotificationUpdateNotification object:obj];
	}

	if ([type isEqualToString:@"updateAuthorizationState"]){
		[self handleAuthState:obj[@"authorization_state"]];
		return;
	}
	// Answer to getMe. updateUser also carries our own record, but the direct
	// reply is the one that always has the phone number.
	if ([type isEqualToString:@"user"] && obj[@"phone_number"]){
		[self handleMeUser:obj];
		return;
	}
	if ([type isEqualToString:@"updateUser"]){
		[self handleUpdateUser:obj];
		return;
	}

	// Live message updates - without these a chat only refreshes when reopened.
	if ([type isEqualToString:@"updateNewMessage"]){
		[self handleUpdateNewMessage:obj];
		return;
	}
	if ([type isEqualToString:@"updateMessageContent"] ||
		[type isEqualToString:@"updateMessageEdited"]){
		[self handleUpdateMessageContent:obj];
		return;
	}
	if ([type isEqualToString:@"updateMessageSendSucceeded"] ||
		[type isEqualToString:@"updateMessageSendFailed"]){
		[self handleUpdateMessageSent:obj];
		return;
	}
	if ([type isEqualToString:@"updateDeleteMessages"]){
		[self handleUpdateDeleteMessages:obj];
		return;
	}
	if ([type isEqualToString:@"updateNewChat"]){
		[self mergeChat:obj[@"chat"]];
		return;
	}
	if ([type isEqualToString:@"updateChatLastMessage"] ||
		[type isEqualToString:@"updateChatPosition"] ||
		[type isEqualToString:@"updateChatTitle"] ||
		[type isEqualToString:@"updateChatPhoto"] ||
		[type isEqualToString:@"updateChatReadInbox"] ||
		[type isEqualToString:@"updateChatReadOutbox"] ||
		[type isEqualToString:@"updateChatDraftMessage"] ||
		[type isEqualToString:@"updateChatIsMarkedAsUnread"] ||
		[type isEqualToString:@"updateChatNotificationSettings"]){
		[self applyChatUpdate:obj];
		return;
	}
	if ([type isEqualToString:@"updateConnectionState"]){
		[self handleUpdateConnectionState:obj];
		return;
	}
	if ([type isEqualToString:@"updateNewCallSignalingData"]){
		NSData *data = TGCliBase64(obj[@"data"]);
		[[TGCall shared] handleSignalingData:data];
		return;
	}

	if ([type isEqualToString:@"updateCall"]){
		// TDLib signals the call; TGCall owns the audio.
		[[TGCall shared] handleUpdate:obj[@"call"]];
		return;
	}

	if ([type isEqualToString:@"updateFile"]){
		[self handleUpdateFile:obj];
		return;
	}

	if ([type hasPrefix:@"updateStory"] ||
		[type isEqualToString:@"updateChatActiveStories"]){
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGStoryUpdateNotification object:obj];
		return;
	}

	if ([type isEqualToString:@"updateChatAction"]){
		[self handleUpdateChatAction:obj];
		return;
	}

	if ([type isEqualToString:@"updateSupergroup"]){
		[self handleUpdateSupergroup:obj];
		return;
	}

	if ([type isEqualToString:@"updateUserStatus"]){
		[self handleUpdateUserStatus:obj];
		return;
	}

	if ([type isEqualToString:@"updateChatFolders"]){
		[self handleUpdateChatFolders:obj];
		return;
	}
	if ([type isEqualToString:@"updateUnreadChatCount"]){
		NSLog(@"TGClient: %@ total=%@ list=%@", type, obj[@"total_count"],
				obj[@"chat_list"][@"@type"]);
		return;
	}
	if ([type isEqualToString:@"error"]){
		[self handleErrorObject:obj];
		return;
	}
}

- (void)handleMeUser:(NSDictionary *)obj {
	self.me = @{
		@"id"         : obj[@"id"] ?: @(0),
		@"first_name" : obj[@"first_name"] ?: @"",
		@"username"   : TGActiveUsername(obj) ?: (obj[@"username"] ?: @""),
		@"phone"      : obj[@"phone_number"] ?: @"",
		@"is_premium" : obj[@"is_premium"] ?: @NO,
	};
	NSLog(@"TGClient: signed in as +%@", self.me[@"phone"]);
}

- (void)handleUpdateUser:(NSDictionary *)obj {
	NSDictionary *u = obj[@"user"];
	NSString *name = [[NSString stringWithFormat:@"%@ %@",
			u[@"first_name"] ?: @"", u[@"last_name"] ?: @""]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (!name.length)
		name = TGActiveUsername(u) ?: @"";
	if (u[@"id"] && name.length)
		self.usersById[u[@"id"]] = name;
	[self cacheProfilePhoto:u];
}

- (void)handleUpdateNewMessage:(NSDictionary *)obj {
	NSDictionary *m = obj[@"message"];
	if (self.onMessage && m)
		self.onMessage([m[@"chat_id"] longLongValue], TGFlattenMessage(m), 0);
}

- (void)handleUpdateMessageSent:(NSDictionary *)obj {
	NSDictionary *m = obj[@"message"];
	int64_t oldId = [obj[@"old_message_id"] longLongValue];
	if (!m || !self.onMessage)
		return;
	self.onMessage([m[@"chat_id"] longLongValue], TGFlattenMessage(m), oldId);
}

// Content changed in place (a photo finished uploading, a text edited).
- (void)handleUpdateMessageContent:(NSDictionary *)obj {
	if (self.onMessage)
		self.onMessage([obj[@"chat_id"] longLongValue], nil, 0);
}

- (void)handleUpdateDeleteMessages:(NSDictionary *)obj {
	if ([obj[@"is_permanent"] boolValue] && self.onMessage){
		int64_t chatId = [obj[@"chat_id"] longLongValue];
		for (NSNumber *mid in obj[@"message_ids"])
			self.onMessage(chatId, nil, [mid longLongValue]);
	}
}

- (void)handleUpdateConnectionState:(NSDictionary *)obj {
	NSString *st = obj[@"state"][@"@type"];
	NSLog(@"TGClient: connection %@", st);

	TGConnectionState state = TGConnectionStateUnknown;
	NSString *text = nil;
	if ([st isEqualToString:@"connectionStateWaitingForNetwork"]){
		state = TGConnectionStateWaitingForNetwork; text = @"Waiting for network";
	} else if ([st isEqualToString:@"connectionStateConnecting"] ||
			   [st isEqualToString:@"connectionStateConnectingToProxy"]){
		state = TGConnectionStateConnecting; text = @"Connecting";
	} else if ([st isEqualToString:@"connectionStateUpdating"]){
		state = TGConnectionStateUpdating; text = @"Updating";
	} else if ([st isEqualToString:@"connectionStateReady"]){
		state = TGConnectionStateReady; text = nil;
	}

	self.connectionState = state;
	if (state == TGConnectionStateReady)
		[[TGBackgroundSession shared] noteConnectionReady];
	if (self.onConnectionState)
		self.onConnectionState(state, text);
}

// Big files take long enough on a 4S that silence looks like a hang.
- (void)handleUpdateFile:(NSDictionary *)obj {
	NSDictionary *file = obj[@"file"];
	NSDictionary *local = file[@"local"];
	if (self.onFileProgress && [local[@"is_downloading_active"] boolValue]){
		double expected = [file[@"expected_size"] doubleValue];
		double got = [local[@"downloaded_size"] doubleValue];
		if (expected > 0)
			self.onFileProgress([file[@"id"] integerValue], (float)(got / expected));
	}
	NSDictionary *remote = file[@"remote"];
	if ([remote[@"is_uploading_active"] boolValue] ||
		[remote[@"is_uploading_completed"] boolValue]){
		[[NSNotificationCenter defaultCenter]
				postNotificationName:TGStoryUpdateNotification object:obj];
	}
}

// TDLib names the action; the client turns it into the phrase every
// other client shows.
- (void)handleUpdateChatAction:(NSDictionary *)obj {
	NSString *kind = obj[@"action"][@"@type"];
	NSString *phrase = nil;
	if ([kind isEqualToString:@"chatActionTyping"])
		phrase = @"typing...";
	else if ([kind isEqualToString:@"chatActionRecordingVoiceNote"])
		phrase = @"recording audio...";
	else if ([kind isEqualToString:@"chatActionRecordingVideoNote"] ||
			 [kind isEqualToString:@"chatActionRecordingVideo"])
		phrase = @"recording video...";
	else if ([kind isEqualToString:@"chatActionUploadingPhoto"])
		phrase = @"sending a photo...";
	else if ([kind hasPrefix:@"chatActionUploading"])
		phrase = @"sending a file...";
	// chatActionCancel and anything unknown clear it.
	int64_t actingChat = [obj[@"chat_id"] longLongValue];
	// The chat list shows this in place of the preview, so it has to live
	// on the chat rather than only reach whichever chat is open.
	NSMutableDictionary *acting = self.chatsById[@(actingChat)];
	if (acting){
		acting[@"action"] = phrase ?: @"";
		[self rebuildChats];
	}
	if (self.onChatAction)
		self.onChatAction(actingChat, phrase);
}

// Whether a supergroup is a forum is a property of the supergroup, not of
// the chat, and it arrives in an update of its own. Chats already built
// from that supergroup have to be told.
- (void)handleUpdateSupergroup:(NSDictionary *)obj {
	NSDictionary *group = obj[@"supergroup"];
	NSNumber *groupId = group[@"id"];
	if (!groupId)
		return;
	BOOL isForum = [group[@"is_forum"] boolValue];
	if ([self.forumSupergroups[groupId] boolValue] == isForum &&
		self.forumSupergroups[groupId])
		return;
	self.forumSupergroups[groupId] = @(isForum);

	BOOL changed = NO;
	for (NSMutableDictionary *chat in self.chatsById.allValues){
		if (![chat[@"supergroupId"] isEqual:groupId])
			continue;
		chat[@"isForum"] = @(isForum);
		changed = YES;
	}
	if (changed)
		[self rebuildChats];
}

// A private chat's id is the user's id, so presence lands straight on the
// chat the list is drawing.
- (void)handleUpdateUserStatus:(NSDictionary *)obj {
	NSDictionary *status = TGUserStatusInfo(obj[@"status"]);
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGUserStatusDidChangeNotification
						  object:self
						userInfo:@{@"userId" : obj[@"user_id"] ?: @(0), @"status" : status}];

	NSMutableDictionary *chat = self.chatsById[obj[@"user_id"]];
	if (!chat)
		return;
	BOOL online = [status[@"isOnline"] boolValue];
	if ([chat[@"isOnline"] boolValue] == online)
		return;
	chat[@"isOnline"] = @(online);
	[self rebuildChats];
}

- (void)handleUpdateChatFolders:(NSDictionary *)obj {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *f in obj[@"chat_folders"]){
		// chatFolderInfo.name is chatFolderName{text:formattedText}, so the
		// plain string sits two levels down: name.text.text.
		id nameText = f[@"name"][@"text"][@"text"];
		[out addObject:@{@"id"    : f[@"id"] ?: @(0),
						 @"title" : [nameText isKindOfClass:[NSString class]] ? nameText : @""}];
	}
	self.folders = out;
	NSLog(@"TGClient: %lu folders", (unsigned long)out.count);
	[self saveCachedFolders];
}

- (void)handleErrorObject:(NSDictionary *)obj {
	NSString *msg = obj[@"message"] ?: @"unknown error";
	NSLog(@"TGClient: ERROR code=%@ msg=%@", obj[@"code"], msg);
	if ([obj[@"code"] intValue] == 404)
		return;
	NSLog(@"TGClient: error: %@", obj);
	if (self.authState != TGAuthStateWaitPhoneNumber &&
		self.authState != TGAuthStateWaitCode &&
		self.authState != TGAuthStateWaitPassword &&
		self.authState != TGAuthStateWaitRegistration)
		return;
	if (self.onError)
		self.onError(msg);
}

- (void)handleAuthState:(NSDictionary *)state {
	NSString *type = state[@"@type"];
	NSLog(@"TGClient: auth state %@", type);

	TGAuthState s = TGAuthStateUnknown;

	if ([type isEqualToString:@"authorizationStateWaitTdlibParameters"]){
		[self sendTdlibParameters];
		[self flushPreInitRequests];
		return;                       // not a user-visible state
	} else if ([type isEqualToString:@"authorizationStateWaitPhoneNumber"]){
		s = TGAuthStateWaitPhoneNumber;
	} else if ([type isEqualToString:@"authorizationStateWaitCode"]){
		s = TGAuthStateWaitCode;
	} else if ([type isEqualToString:@"authorizationStateWaitPassword"]){
		s = TGAuthStateWaitPassword;
	} else if ([type isEqualToString:@"authorizationStateWaitRegistration"]){
		s = TGAuthStateWaitRegistration;
	} else if ([type isEqualToString:@"authorizationStateReady"]){
		s = TGAuthStateReady;
	} else if ([type isEqualToString:@"authorizationStateLoggingOut"]){
		s = TGAuthStateLoggingOut;
	} else if ([type isEqualToString:@"authorizationStateClosed"]){
		s = TGAuthStateClosed;
		self.running = NO;
		[self failPendingRequests:@"client closed"];
	} else {
		return;                       // encryption-key states etc.
	}

	self.authState = s;
	if (s == TGAuthStateReady){
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"tgWasSignedIn"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[self send:@{@"@type" : @"getMe"}];
		[self loadChats];
	}
	if (s == TGAuthStateWaitPhoneNumber || s == TGAuthStateLoggingOut ||
		s == TGAuthStateWaitRegistration){
		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"tgWasSignedIn"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[self clearCachedChats];
		[TGDiskCache clearImages];
		[TGRemoteImageView tgPurgeMemoryCache];
		[self.chatsById removeAllObjects];
		[self.chatsConfirmedByServer removeAllObjects];
		[self rebuildChats];
	}
	if (s == TGAuthStateWaitPhoneNumber)
		[self flushPendingPhoneNumber];
	if (self.onAuthState)
		self.onAuthState(s);
}

- (void)flushPreInitRequests {
	NSArray *held = self.preInitRequests;
	self.preInitRequests = nil;
	for (NSDictionary *request in held)
		[self send:request];
}

- (void)sendTdlibParameters {
	NSString *db = [TGDiskCache databaseDirectory];

	int SETUP_API_ID(apiId)
	char * SETUP_API_HASH(apiHash)

	UIDevice *dev = [UIDevice currentDevice];

	self.parametersSent = YES;
	[self sendUnguarded:@{
		@"@type"                  : @"setTdlibParameters",
		@"database_directory"     : db,
		@"files_directory"        : [db stringByAppendingPathComponent:@"files"],
		@"use_file_database"      : @YES,
		@"use_chat_info_database" : @YES,
		@"use_message_database"   : @YES,
		@"use_secret_chats"       : @NO,
		@"api_id"                 : @(apiId),
		@"api_hash"               : [NSString stringWithUTF8String:apiHash],
		@"system_language_code"   : @"en",
		@"device_model"           : dev.model ?: @"iPhone",
		@"system_version"         : dev.systemVersion ?: @"7.1.2",
		@"application_version"    : @"1.16.48",
	}];
}

#pragma mark - authorization steps

- (void)sendPhoneNumber:(NSString *)phoneNumber {
	// Arriving before TDLib is ready is normal - the number can be handed in
	// milliseconds after launch, while the client is still starting - and
	// send: silently drops anything sent too early. Hold it and flush once
	// the state machine actually asks for a number.
	self.pendingPhoneNumber = phoneNumber;
	if (self.available && self.authState == TGAuthStateWaitPhoneNumber)
		[self flushPendingPhoneNumber];
}

- (void)flushPendingPhoneNumber {
	if (!self.pendingPhoneNumber.length)
		return;
	NSString *number = self.pendingPhoneNumber;
	self.pendingPhoneNumber = nil;
	[self send:@{
		@"@type"        : @"setAuthenticationPhoneNumber",
		@"phone_number" : number,
	}];
}

- (void)sendCode:(NSString *)code {
	[self send:@{
		@"@type" : @"checkAuthenticationCode",
		@"code"  : code ?: @"",
	}];
}

- (void)sendPassword:(NSString *)password {
	[self send:@{
		@"@type"    : @"checkAuthenticationPassword",
		@"password" : password ?: @"",
	}];
}

#pragma mark - files

- (void)downloadFile:(NSInteger)fileId completion:(void (^)(NSString *))completion {
	if (fileId <= 0){
		if (completion) completion(nil);
		return;
	}

	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"downloadFile",
		@"file_id"     : @(fileId),
		@"priority"    : @(1),
		@"offset"      : @(0),
		@"limit"       : @(0),
		@"synchronous" : @YES,     // reply only once the file is on disk
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		(void)me;
		NSString *path = result[@"local"][@"path"];
		BOOL done = [result[@"local"][@"is_downloading_completed"] boolValue];
		if (completion)
			completion((done && path.length) ? path : nil);
	}];
}

#pragma mark - messages

/// Reactions as one short line: emoji and count, most used first. Custom
/// emoji have no character to draw, so they are counted but not named.
static NSString *TGReactionSummary(NSDictionary *m) {
	NSArray *reactions = m[@"interaction_info"][@"reactions"][@"reactions"];
	if (![reactions isKindOfClass:NSArray.class] || !reactions.count)
		return nil;

	NSMutableArray *parts = [NSMutableArray array];
	for (NSDictionary *r in reactions){
		NSString *emoji = r[@"type"][@"emoji"];
		NSInteger count = [r[@"total_count"] integerValue];
		[parts addObject:[NSString stringWithFormat:@"%@ %ld",
				emoji.length ? emoji : @"\U00002B50", (long)count]];
	}
	return [parts componentsJoinedByString:@"  "];
}

/// "messageVideoChatStarted" -> "Video chat started". TDLib's type names are
/// already the sentence, written in camel case, and turning them back is a
/// better answer for a content type nobody has written a branch for than
/// either an empty bubble or the word "unsupported".
NSString *const TGUserStatusDidChangeNotification = @"TGUserStatusDidChangeNotification";

static NSDictionary *TGUserStatusInfo(NSDictionary *status) {
	NSString *type = status[@"@type"];
	if ([type isEqualToString:@"userStatusOnline"])
		return @{@"isOnline" : @YES, @"text" : @"online", @"rank" : @(4000000000LL)};
	if ([type isEqualToString:@"userStatusOffline"]){
		int64_t wasOnline = [status[@"was_online"] longLongValue];
		NSDate *date = [NSDate dateWithTimeIntervalSince1970:wasOnline];
		NSDate *now = [NSDate date];

		static NSCalendar *cal = nil;
		static NSDateFormatter *timeFmt = nil;
		static NSDateFormatter *dayFmt = nil;
		static NSDateFormatter *dateFmt = nil;
		if (!cal){
			cal = [NSCalendar currentCalendar];
			timeFmt = [NSDateFormatter new];
			timeFmt.dateFormat = @"HH:mm";
			dayFmt = [NSDateFormatter new];
			dayFmt.dateFormat = @"EEEE";
			dateFmt = [NSDateFormatter new];
			dateFmt.dateFormat = @"dd.MM.yyyy";
		}

		NSString *time = [timeFmt stringFromDate:date];

		NSUInteger dayUnits = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
		NSDate *dateOnly = [cal dateFromComponents:[cal components:dayUnits fromDate:date]];
		NSDate *nowOnly  = [cal dateFromComponents:[cal components:dayUnits fromDate:now]];
		NSInteger dayDelta = [cal components:NSCalendarUnitDay
									 fromDate:dateOnly
									   toDate:nowOnly
									  options:0].day;

		NSString *when;
		if (dayDelta == 0){
			when = [NSString stringWithFormat:@"today at %@", time];
		} else if (dayDelta == 1){
			when = [NSString stringWithFormat:@"yesterday at %@", time];
		} else if (dayDelta > 1 && dayDelta < 7){
			when = [NSString stringWithFormat:@"on %@ at %@",
					[dayFmt stringFromDate:date], time];
		} else {
			when = [NSString stringWithFormat:@"%@ at %@",
					[dateFmt stringFromDate:date], time];
		}
		return @{@"isOnline" : @NO,
				 @"text" : [NSString stringWithFormat:@"last seen %@", when],
				 @"rank" : @(wasOnline)};
	}
	if ([type isEqualToString:@"userStatusRecently"])
		return @{@"isOnline" : @NO, @"text" : @"last seen recently", @"rank" : @(3)};
	if ([type isEqualToString:@"userStatusLastWeek"])
		return @{@"isOnline" : @NO, @"text" : @"last seen within a week", @"rank" : @(2)};
	if ([type isEqualToString:@"userStatusLastMonth"])
		return @{@"isOnline" : @NO, @"text" : @"last seen within a month", @"rank" : @(1)};
	return @{@"isOnline" : @NO, @"text" : @"last seen a long time ago", @"rank" : @(0)};
}

static NSString *TGPhraseFromTypeName(NSString *ctype) {
	NSString *rest = [ctype hasPrefix:@"message"] ? [ctype substringFromIndex:7] : ctype;
	if (!rest.length)
		return @"Message";

	NSMutableString *out = [NSMutableString stringWithCapacity:rest.length + 8];
	for (NSUInteger i = 0; i < rest.length; i++){
		unichar c = [rest characterAtIndex:i];
		if (i > 0 && c >= 'A' && c <= 'Z'){
			[out appendString:@" "];
			[out appendFormat:@"%C", (unichar)(c - 'A' + 'a')];
		} else {
			[out appendFormat:@"%C", c];
		}
	}
	return out;
}

static NSArray *TGPhotoSizeList(NSArray *sizes) {
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:sizes.count];
	for (NSDictionary *size in sizes){
		NSNumber *fileId = size[@"photo"][@"id"];
		NSNumber *width  = size[@"width"];
		NSNumber *height = size[@"height"];
		if (![fileId isKindOfClass:NSNumber.class] || [fileId integerValue] == 0)
			continue;
		if ([width intValue] < 1 || [height intValue] < 1)
			continue;
		[out addObject:@{@"id" : fileId, @"w" : width, @"h" : height}];
	}
	[out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
		int wa = [a[@"w"] intValue], wb = [b[@"w"] intValue];
		if (wa == wb)
			return NSOrderedSame;
		return wa < wb ? NSOrderedAscending : NSOrderedDescending;
	}];
	return out;
}

/// Flatten a TDLib message into what the UI needs.
static NSDictionary *TGFlattenMessage(NSDictionary *m) {
	NSDictionary *content = m[@"content"];
	NSString *ctype = content[@"@type"];
	NSNumber *photoFileId = nil;   // an image to show in the bubble
	NSNumber *docFileId   = nil;   // a file to play or offer for download
	NSString *docName     = nil;
	NSString *extra       = nil;   // text the content itself carries
	NSNumber *latitude = nil, *longitude = nil;
	NSNumber *duration = nil;
	NSData *waveform = nil;
	BOOL isService = NO;
	BOOL serviceNamesAuthor = NO;
	NSString *callState = nil;     // "missed" or "answered" on a call message
	NSString *audioTitle = nil, *audioPerformer = nil;
	NSNumber *photoW = nil, *photoH = nil;
	NSArray *photoSizes = nil;
	NSDictionary *minithumb = nil;

	int64_t actorId = [m[@"sender_id"][@"user_id"] longLongValue];
	NSString *knownActor = [[TGClient shared] nameForUserId:actorId];
	BOOL namedActor = knownActor.length > 0;
	NSString *actorName = namedActor ? knownActor : @"Someone";

	if ([ctype isEqualToString:@"messagePhoto"]){
		// sizes run small to large; take the largest present
		NSArray *sizes = content[@"photo"][@"sizes"];
		if (sizes.count){
			photoFileId = [sizes lastObject][@"photo"][@"id"];
			photoW = [sizes lastObject][@"width"];
			photoH = [sizes lastObject][@"height"];
			photoSizes = TGPhotoSizeList(sizes);
		}
		minithumb = content[@"photo"][@"minithumbnail"];

	} else if ([ctype isEqualToString:@"messageVideo"]){
		photoFileId = content[@"video"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"video"][@"video"][@"id"];
		docName     = content[@"video"][@"file_name"];
		photoW      = content[@"video"][@"width"];
		photoH      = content[@"video"][@"height"];
		duration    = content[@"video"][@"duration"];
		minithumb   = content[@"video"][@"minithumbnail"];

	} else if ([ctype isEqualToString:@"messageVideoNote"]){
		photoFileId = content[@"video_note"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"video_note"][@"video"][@"id"];

	} else if ([ctype isEqualToString:@"messageAnimation"]){
		// Telegram GIFs are MP4, so they play like any video.
		photoFileId = content[@"animation"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"animation"][@"animation"][@"id"];
		docName     = content[@"animation"][@"file_name"];
		photoW      = content[@"animation"][@"width"];
		photoH      = content[@"animation"][@"height"];
		minithumb   = content[@"animation"][@"minithumbnail"];

	} else if ([ctype isEqualToString:@"messageSticker"] ||
			   [ctype isEqualToString:@"messageAnimatedEmoji"]){
		NSDictionary *sticker = [ctype isEqualToString:@"messageSticker"]
			? content[@"sticker"]
			: content[@"animated_emoji"][@"sticker"];
		NSString *format = sticker[@"format"][@"@type"];

		if ([format isEqualToString:@"stickerFormatTgs"]){
			// Lottie vector animation - TGLottieView plays it. The thumbnail
			// is kept as what to show until the file arrives.
			docFileId   = sticker[@"sticker"][@"id"];
			photoFileId = sticker[@"thumbnail"][@"file"][@"id"];
			docName     = @"tgs";
		} else if ([format isEqualToString:@"stickerFormatWebp"]){
			photoFileId = sticker[@"sticker"][@"id"];
		} else {
			// .webm is VP9, which this device cannot decode - thumbnail only.
			photoFileId = sticker[@"thumbnail"][@"file"][@"id"];
		}

		photoW = sticker[@"width"];
		photoH = sticker[@"height"];

		extra = content[@"emoji"] ?: sticker[@"emoji"];

	} else if ([ctype isEqualToString:@"messageDocument"]){
		photoFileId = content[@"document"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"document"][@"document"][@"id"];
		docName     = content[@"document"][@"file_name"];
		NSNumber *size = content[@"document"][@"document"][@"size"];
		extra = size.longLongValue > 0
			? [NSString stringWithFormat:@"%@\n%.1f KB", docName ?: @"Document",
					size.doubleValue / 1024.0]
			: (docName ?: @"Document");

	} else if ([ctype isEqualToString:@"messageVoiceNote"]){
		docFileId = content[@"voice_note"][@"voice"][@"id"];
		duration  = content[@"voice_note"][@"duration"];
		// Telegram sends the shape of the sound with the message: five bits
		// per sample, which is what the bars in the bubble are drawn from.
		waveform  = TGCliBase64(content[@"voice_note"][@"waveform"]);
		extra = @"";

	} else if ([ctype isEqualToString:@"messageAudio"]){
		docFileId = content[@"audio"][@"audio"][@"id"];
		docName   = content[@"audio"][@"file_name"];
		duration  = content[@"audio"][@"duration"];
		NSString *title = content[@"audio"][@"title"];
		NSString *performer = content[@"audio"][@"performer"];
		audioTitle     = [title isKindOfClass:NSString.class] ? title : nil;
		audioPerformer = [performer isKindOfClass:NSString.class] ? performer : nil;
		if (!audioTitle.length)
			audioTitle = docName.length ? docName.lastPathComponent : @"Audio";
		NSInteger seconds = [duration integerValue];
		NSMutableString *lines = [NSMutableString stringWithString:audioTitle];
		if (audioPerformer.length)
			[lines appendFormat:@"\n%@", audioPerformer];
		if (seconds > 0)
			[lines appendFormat:@"%@%ld:%02ld", audioPerformer.length ? @", " : @"\n",
					(long)(seconds / 60), (long)(seconds % 60)];
		extra = lines;

	} else if ([ctype isEqualToString:@"messageContact"]){
		NSDictionary *c = content[@"contact"];
		NSString *name = [[NSString stringWithFormat:@"%@ %@",
				c[@"first_name"] ?: @"", c[@"last_name"] ?: @""]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		extra = [NSString stringWithFormat:@"%@\n%@", name, c[@"phone_number"] ?: @""];

	} else if ([ctype isEqualToString:@"messageVenue"]){
		NSDictionary *v = content[@"venue"];
		extra = [NSString stringWithFormat:@"%@\n%@",
				v[@"title"] ?: @"", v[@"address"] ?: @""];
		latitude  = v[@"location"][@"latitude"];
		longitude = v[@"location"][@"longitude"];

	} else if ([ctype isEqualToString:@"messageChatAddMembers"]){
		NSArray *added = content[@"member_user_ids"];
		if (added.count == 1 && [added[0] longLongValue] == actorId){
			extra = [NSString stringWithFormat:@"%@ joined the group", actorName];
		} else {
			NSMutableArray *names = [NSMutableArray array];
			for (NSNumber *uid in added)
				[names addObject:[[TGClient shared] nameForUserId:uid.longLongValue]
						?: @"someone"];
			extra = [NSString stringWithFormat:@"%@ invited %@", actorName,
					[names componentsJoinedByString:@", "]];
		}
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatDeleteMember"]){
		int64_t goneId = [content[@"user_id"] longLongValue];
		if (goneId == actorId){
			extra = [NSString stringWithFormat:@"%@ left the group", actorName];
		} else {
			NSString *who = [[TGClient shared] nameForUserId:goneId] ?: @"someone";
			extra = [NSString stringWithFormat:@"%@ removed %@", actorName, who];
		}
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatJoinByLink"] ||
			   [ctype isEqualToString:@"messageChatJoinByRequest"]){
		extra = [NSString stringWithFormat:@"%@ joined the group via invite link",
				actorName];
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatChangeTitle"]){
		NSString *newTitle = content[@"title"] ?: @"";
		extra = namedActor
			? [NSString stringWithFormat:@"%@ changed group name to \"%@\"",
					actorName, newTitle]
			: [NSString stringWithFormat:@"Channel renamed to \"%@\"", newTitle];
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatChangePhoto"]){
		extra = namedActor
			? [NSString stringWithFormat:@"%@ changed group photo", actorName]
			: @"Channel photo updated";
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatDeletePhoto"]){
		extra = namedActor
			? [NSString stringWithFormat:@"%@ removed group photo", actorName]
			: @"Channel photo removed";
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messagePinMessage"]){
		extra = [NSString stringWithFormat:@"%@ pinned a message", actorName];
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageBasicGroupChatCreate"] ||
			   [ctype isEqualToString:@"messageSupergroupChatCreate"]){
		NSString *title = content[@"title"];
		extra = title.length
			? [NSString stringWithFormat:@"%@ created the group \"%@\"",
					actorName, title]
			: [NSString stringWithFormat:@"%@ created a group", actorName];
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatUpgradeTo"] ||
			   [ctype isEqualToString:@"messageChatUpgradeFrom"]){
		extra = @"Group upgraded to a supergroup";
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageChatSetTheme"]){
		NSString *theme = content[@"theme_name"];
		BOOL mine = [m[@"is_outgoing"] boolValue];
		if (!theme.length)
			extra = mine ? @"You disabled chat theme"
						 : [NSString stringWithFormat:@"%@ disabled chat theme", actorName];
		else
			extra = mine
				? [NSString stringWithFormat:@"You changed chat theme to %@", theme]
				: [NSString stringWithFormat:@"%@ changed chat theme to %@",
						actorName, theme];
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageScreenshotTaken"]){
		extra = [m[@"is_outgoing"] boolValue]
			? @"You took a screenshot!"
			: [NSString stringWithFormat:@"%@ took a screenshot!", actorName];
		isService = YES;
		serviceNamesAuthor = YES;

	} else if ([ctype isEqualToString:@"messageCall"]){
		// A call is a row of its own, not a service line: it says which way it
		// went and whether it was answered, and it can be returned with a tap.
		NSNumber *dur = content[@"duration"];
		NSString *reason = content[@"discard_reason"][@"@type"];
		BOOL missed = [reason isEqualToString:@"callDiscardReasonMissed"] ||
					  [reason isEqualToString:@"callDiscardReasonDeclined"];
		BOOL outgoing = [m[@"is_outgoing"] boolValue];

		extra = missed
			? (outgoing ? @"Cancelled call" : @"Missed call")
			: (outgoing ? @"Outgoing call" : @"Incoming call");
		if (!missed && dur.integerValue > 0)
			extra = [NSString stringWithFormat:@"%@, %ld:%02ld", extra,
					(long)(dur.integerValue / 60), (long)(dur.integerValue % 60)];
		callState = missed ? @"missed" : @"answered";
		isService = NO;

	} else if ([ctype isEqualToString:@"messageDice"]){
		extra = [NSString stringWithFormat:@"%@  %@",
				content[@"emoji"] ?: @"Dice", content[@"value"] ?: @""];

	} else if ([ctype isEqualToString:@"messageGame"]){
		extra = [NSString stringWithFormat:@"Game: %@",
				content[@"game"][@"title"] ?: @""];

	} else if ([ctype isEqualToString:@"messageUnsupported"]){
		extra = @"This message is not supported on your version of Telegram. "
				 "Please update to the latest version.";
		isService = NO;

	} else if ([ctype isEqualToString:@"messagePoll"]){
		// Rendered by the chat as a question with its options and their share
		// of the vote; the flattened form carries them as one block of text.
		NSDictionary *poll = content[@"poll"];
		NSMutableString *lines = [NSMutableString stringWithFormat:@"%@\n",
				poll[@"question"][@"text"] ?: poll[@"question"] ?: @"Poll"];
		NSInteger total = [poll[@"total_voter_count"] integerValue];
		for (NSDictionary *option in poll[@"options"]){
			[lines appendFormat:@"%@  %@%ld%%\n",
					[option[@"is_chosen"] boolValue] ? @"\u25c9" : @"\u25cb",
					option[@"text"][@"text"] ?: option[@"text"] ?: @"",
					(long)[option[@"vote_percentage"] integerValue]];
		}
		[lines appendFormat:@"%ld voted", (long)total];
		extra = lines;
		isService = NO;

	} else if ([ctype isEqualToString:@"messageLocation"]){
		NSDictionary *loc = content[@"location"];
		extra = @"Location";
		latitude  = loc[@"latitude"];
		longitude = loc[@"longitude"];

	} else if ([ctype isEqualToString:@"messageLiveLocation"]){
		// The same card as a fixed point, said differently: a live location is
		// a place that keeps changing, and the map is still worth drawing.
		NSDictionary *loc = content[@"location"];
		extra = @"Live location";
		latitude  = loc[@"latitude"];
		longitude = loc[@"longitude"];

	} else if ([ctype isEqualToString:@"messageInvoice"]){
		NSInteger amount = [content[@"total_amount"] integerValue];
		NSString *currency = content[@"currency"] ?: @"";
		extra = amount > 0
			? [NSString stringWithFormat:@"%@\n%.2f %@", content[@"product_info"][@"title"]
					?: content[@"title"] ?: @"Invoice", amount / 100.0, currency]
			: (content[@"product_info"][@"title"] ?: @"Invoice");

	} else if ([ctype isEqualToString:@"messageStory"]){
		extra = @"Story";

	} else if ([ctype isEqualToString:@"messagePaidMedia"]){
		extra = [NSString stringWithFormat:@"Paid media, %@ stars",
				content[@"star_count"] ?: @0];

	} else if ([ctype isEqualToString:@"messageChecklist"]){
		NSDictionary *list = content[@"checklist"];
		NSMutableString *lines = [NSMutableString stringWithFormat:@"%@\n",
				list[@"title"][@"text"] ?: @"Checklist"];
		for (NSDictionary *task in list[@"tasks"])
			[lines appendFormat:@"%@ %@\n",
					task[@"completed_by_user_id"] ? @"☑" : @"☐",
					task[@"text"][@"text"] ?: @""];
		extra = [lines stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	} else if ([ctype hasPrefix:@"messageExpired"]){
		// A self-destructing photo that has gone. Saying so is the whole
		// content; an empty bubble would look like a bug.
		extra = @"Expired media";
		isService = YES;

	}

	// A caption wins; then whatever the content itself says; and for a plain
	// picture, nothing at all - the image speaks for itself.
	NSString *caption = content[@"caption"][@"text"];
	NSString *text;
	if (caption.length)      text = caption;
	else if (extra.length)   text = extra;
	else if (photoFileId)    text = @"";
	else                     text = TGMessagePreview(m);

	// TDLib has over a hundred content types and gains more with every
	// release, most of them one-line notices nobody has written a branch for.
	// Anything that would otherwise be an empty bubble says what it is instead:
	// messageVideoChatStarted reads as "Video chat started". Only content with
	// nothing at all to show reaches this - text and media have already spoken.
	if (!text.length && !photoFileId && !docFileId && !latitude){
		text = TGPhraseFromTypeName(ctype);
		isService = YES;
		serviceNamesAuthor = YES;
	}

	// Reply, forward and edit state - three things a chat is unreadable
	// without, because a bare answer loses what it answers.
	NSDictionary *replyTo = m[@"reply_to"];
	NSNumber *replyId = nil;
	NSString *replyText = nil;
	if ([replyTo[@"@type"] isEqualToString:@"messageReplyToMessage"]){
		replyId = replyTo[@"message_id"];
		// Newer TDLib carries the quoted text inline; otherwise the chat view
		// fetches the original by id.
		replyText = replyTo[@"quote"][@"text"][@"text"] ?: replyTo[@"quote"][@"text"];
	}

	NSString *forwardFrom = nil;
	NSDictionary *forwardInfo = m[@"forward_info"];
	NSDictionary *origin = forwardInfo[@"origin"];
	NSString *originType = origin[@"@type"];
	int64_t forwardUserId = 0;
	int64_t forwardChatId = 0;
	int64_t forwardMessageId = 0;
	BOOL forwardIsChannel = NO;
	if ([originType isEqualToString:@"messageOriginUser"]){
		forwardUserId = [origin[@"sender_user_id"] longLongValue];
		forwardFrom = [[TGClient shared] nameForUserId:forwardUserId] ?: @"a user";
	}
	else if ([originType isEqualToString:@"messageOriginHiddenUser"])
		forwardFrom = origin[@"sender_name"];
	else if ([originType isEqualToString:@"messageOriginChannel"]){
		NSString *signature = origin[@"author_signature"];
		forwardFrom = signature.length ? signature : @"a channel";
		forwardChatId    = [origin[@"chat_id"] longLongValue];
		forwardMessageId = [origin[@"message_id"] longLongValue];
		forwardIsChannel = YES;
	}
	else if ([originType isEqualToString:@"messageOriginChat"]){
		forwardFrom = origin[@"author_signature"] ?: @"a chat";
		forwardChatId = [origin[@"sender_chat_id"] longLongValue];
	}

	NSDictionary *forwardSource = forwardInfo[@"source"];
	if ([forwardSource isKindOfClass:NSDictionary.class] && !forwardMessageId){
		int64_t sourceChat = [forwardSource[@"chat_id"] longLongValue];
		int64_t sourceMessage = [forwardSource[@"message_id"] longLongValue];
		if (sourceChat && sourceMessage &&
			(!forwardChatId || forwardChatId == sourceChat)){
			forwardChatId    = sourceChat;
			forwardMessageId = sourceMessage;
		}
	}

	static NSData *emptyWaveform = nil;
	if (!emptyWaveform)
		emptyWaveform = [NSData data];

	NSDictionary *flat = @{
		@"id"        : m[@"id"] ?: @(0),
		@"text"      : text,
		@"replyId"   : replyId    ?: [NSNull null],
		@"replyText" : replyText  ?: @"",
		@"forward"   : forwardFrom ?: @"",
		@"forwardUserId"    : [NSNumber numberWithLongLong:forwardUserId],
		@"forwardChatId"    : [NSNumber numberWithLongLong:forwardChatId],
		@"forwardMessageId" : [NSNumber numberWithLongLong:forwardMessageId],
		@"forwardIsChannel" : @(forwardIsChannel),
		@"edited"    : @([m[@"edit_date"] doubleValue] > 0),
		@"kind"      : ctype ?: @"",
		@"date"      : m[@"date"] ?: @(0),
		@"outgoing"  : m[@"is_outgoing"] ?: @NO,
		@"photoId"   : photoFileId ?: [NSNull null],
		@"photoWidth"  : photoW ?: [NSNull null],
		@"photoHeight" : photoH ?: [NSNull null],
		@"photoSizes"  : photoSizes ?: @[],
		@"minithumbnail" : ([minithumb isKindOfClass:NSDictionary.class]
							? minithumb : (id)[NSNull null]),
		@"docId"     : docFileId   ?: [NSNull null],
		@"docName"   : docName     ?: @"",
		@"audioTitle"     : audioTitle     ?: @"",
		@"audioPerformer" : audioPerformer ?: @"",
		@"service"   : @(isService),
		@"serviceNamesAuthor" : @(serviceNamesAuthor),
		// Several photos sent together share an album id; the chat draws them
		// as one block rather than as unrelated messages.
		@"albumId"   : m[@"media_album_id"] ?: @"",
		// "\U0001F44D 3" per reaction, joined - enough to show under a bubble.
		@"reactions" : TGReactionSummary(m) ?: @"",
		@"duration"  : duration ?: @0,
		@"waveform"  : waveform ?: emptyWaveform,
		@"senderId"  : m[@"sender_id"][@"user_id"] ?: @(0),
		@"channelPost" : m[@"is_channel_post"] ?: @NO,
		@"signature" : ([m[@"author_signature"] isKindOfClass:NSString.class]
						? m[@"author_signature"] : @""),
		@"views"     : m[@"interaction_info"][@"view_count"] ?: @(0),
		@"lat"       : latitude    ?: [NSNull null],
		@"lon"       : longitude   ?: [NSNull null],
		@"callState" : callState   ?: @"",
	};

	NSDictionary *poll = content[@"poll"];
	if (![poll isKindOfClass:NSDictionary.class])
		return flat;

	NSArray *rawOptions = poll[@"options"];
	NSMutableArray *options = [NSMutableArray arrayWithCapacity:rawOptions.count];
	for (NSDictionary *option in rawOptions){
		id optionText = option[@"text"];
		if ([optionText isKindOfClass:NSDictionary.class])
			optionText = @{@"text" : optionText[@"text"] ?: @""};
		[options addObject:@{
			@"text"            : optionText ?: @"",
			@"vote_percentage" : option[@"vote_percentage"] ?: @0,
			@"is_chosen"       : option[@"is_chosen"] ?: @NO,
		}];
	}

	NSMutableDictionary *withPoll = [flat mutableCopy];
	withPoll[@"pollOptions"]   = options;
	withPoll[@"pollQuestion"]  = poll[@"question"][@"text"] ?: @"";
	withPoll[@"pollTotal"]     = poll[@"total_voter_count"] ?: @0;
	withPoll[@"pollClosed"]    = poll[@"is_closed"] ?: @NO;
	withPoll[@"pollAnonymous"] = poll[@"is_anonymous"] ?: @YES;
	return [withPoll copy];
}

- (void)historyForChat:(int64_t)chatId
                thread:(int64_t)threadId
                 limit:(NSInteger)limit
             onlyLocal:(BOOL)onlyLocal
            completion:(void (^)(NSArray *))completion {
	[self historyForChat:chatId thread:threadId limit:limit onlyLocal:onlyLocal
				progress:nil completion:completion];
}

- (void)historyForChat:(int64_t)chatId
                thread:(int64_t)threadId
                 limit:(NSInteger)limit
             onlyLocal:(BOOL)onlyLocal
              progress:(void (^)(NSArray *))progress
            completion:(void (^)(NSArray *))completion {
	if (threadId == 0){
		[self historyForChat:chatId limit:limit onlyLocal:onlyLocal
					progress:progress completion:completion];
		return;
	}
	if (onlyLocal){
		if (completion)
			completion(@[]);
		return;
	}
	[self historyForChat:chatId thread:threadId limit:limit completion:completion];
}

- (void)historyForChat:(int64_t)chatId
                thread:(int64_t)threadId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *))completion {
	if (threadId == 0){
		[self historyForChat:chatId limit:limit completion:completion];
		return;
	}

	// A topic is a message thread, and threads have their own history call.
	[self request:@{
		@"@type"           : @"getMessageThreadHistory",
		@"chat_id"         : @(chatId),
		@"message_id"      : @(threadId),
		@"from_message_id" : @(0),
		@"offset"          : @(0),
		@"limit"           : @(limit),
	} completion:^(NSDictionary *result){
		NSArray *msgs = result[@"messages"];
		if (![msgs isKindOfClass:NSArray.class]){
			NSLog(@"TGClient: thread history -> %@", result[@"@type"]);
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:msgs.count];
		for (NSDictionary *m in [[msgs reverseObjectEnumerator] allObjects])
			[out addObject:TGFlattenMessage(m)];
		if (completion) completion(out);
	}];
}

- (void)searchMessages:(NSString *)query completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"  : @"searchMessages",
		@"query"  : query ?: @"",
		@"limit"  : @(50),
		@"offset" : @"",
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSMutableDictionary *flat = [TGFlattenMessage(m) mutableCopy];
			if (!flat) continue;
			int64_t chatId = [m[@"chat_id"] longLongValue];
			flat[@"chatId"] = @(chatId);
			flat[@"chatTitle"] = [me titleForChat:chatId] ?: @"";
			[out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

- (void)searchInChat:(int64_t)chatId query:(NSString *)query
          completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : query ?: @"",
		@"from_message_id" : @(0),
		@"offset"          : @(0),
		@"limit"           : @(50),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSDictionary *flat = TGFlattenMessage(m);
			if (flat) [out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

/// Title of a chat we already know about, for search results that name it.
- (NSString *)titleForChat:(int64_t)chatId {
	for (NSDictionary *c in self.chats)
		if ([c[@"id"] longLongValue] == chatId)
			return c[@"title"];
	for (NSDictionary *c in self.archivedChats)
		if ([c[@"id"] longLongValue] == chatId)
			return c[@"title"];
	return nil;
}

- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
            completion:(void (^)(NSArray *))completion {
	// getChatHistory returns only what TDLib already holds, and picks the
	// batch size itself - a first call on a cold chat often answers with one
	// message. Walk backwards from the newest until we have enough or the
	// chat runs out.
	[self historyForChat:chatId limit:limit onlyLocal:NO completion:completion];
}

- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
             onlyLocal:(BOOL)onlyLocal
            completion:(void (^)(NSArray *))completion {
	[self historyForChat:chatId limit:limit onlyLocal:onlyLocal
				progress:nil completion:completion];
}

- (void)historyForChat:(int64_t)chatId
                 limit:(NSInteger)limit
             onlyLocal:(BOOL)onlyLocal
              progress:(void (^)(NSArray *))progress
            completion:(void (^)(NSArray *))completion {
	NSMutableArray *collected = [NSMutableArray array];
	[self fetchHistoryChunkForChat:chatId
					 fromMessageId:0
							 limit:limit
						 onlyLocal:onlyLocal
						 collected:collected
						  progress:progress
						completion:completion];
}

- (void)fetchHistoryChunkForChat:(int64_t)chatId
                   fromMessageId:(int64_t)fromMessageId
                           limit:(NSInteger)limit
                       onlyLocal:(BOOL)onlyLocal
                       collected:(NSMutableArray *)collected
                        progress:(void (^)(NSArray *))progress
                      completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"getChatHistory",
		@"chat_id"         : @(chatId),
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(0),
		@"limit"           : @(limit),
		@"only_local"      : @(onlyLocal),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSArray *msgs = result[@"messages"];

		TGMarkOpenStage([NSString stringWithFormat:@"getChatHistory(%@) chunk of %lu",
				onlyLocal ? @"local" : @"net",
				(unsigned long)([msgs isKindOfClass:NSArray.class] ? msgs.count : 0)]);

		if (!me || ![msgs isKindOfClass:NSArray.class] || msgs.count == 0){
			// End of the chat, or an error - hand back what we have, oldest
			// first, which is the order a chat view wants.
			if (completion)
				completion([[collected reverseObjectEnumerator] allObjects]);
			return;
		}

		for (NSDictionary *m in msgs)
			[collected addObject:TGFlattenMessage(m)];

		int64_t oldest = [[msgs lastObject][@"id"] longLongValue];
		if ((NSInteger)collected.count >= limit || oldest == 0){
			if (completion)
				completion([[collected reverseObjectEnumerator] allObjects]);
			return;
		}

		NSArray *soFar = progress ? [[collected reverseObjectEnumerator] allObjects] : nil;
		[me fetchHistoryChunkForChat:chatId
					   fromMessageId:oldest
							   limit:limit - collected.count
						   onlyLocal:onlyLocal
						   collected:collected
							progress:progress
						  completion:completion];
		if (progress)
			progress(soFar);
	}];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId {
	[self sendText:text toChat:chatId thread:0];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId thread:(int64_t)threadId {
	[self sendText:text toChat:chatId thread:threadId replyTo:0];
}

- (void)sendText:(NSString *)text toChat:(int64_t)chatId
          thread:(int64_t)threadId replyTo:(int64_t)replyToId {
	NSMutableDictionary *request = [@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""},
		},
	} mutableCopy];

	if (replyToId != 0)
		request[@"reply_to"] = @{@"@type" : @"inputMessageReplyToMessage",
								 @"message_id" : @(replyToId)};

	[self send:request];
}

- (void)forwardMessages:(NSArray *)messageIds
               fromChat:(int64_t)fromChatId
                 toChat:(int64_t)toChatId {
	[self send:@{
		@"@type"        : @"forwardMessages",
		@"chat_id"      : @(toChatId),
		@"from_chat_id" : @(fromChatId),
		@"message_ids"  : messageIds ?: @[],
	}];
}

- (void)editMessage:(int64_t)messageId inChat:(int64_t)chatId text:(NSString *)text {
	[self send:@{
		@"@type"                : @"editMessageText",
		@"chat_id"              : @(chatId),
		@"message_id"           : @(messageId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""},
		},
	}];
}

- (void)messageWithId:(int64_t)messageId
               inChat:(int64_t)chatId
           completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMessage",
					@"chat_id" : @(chatId),
					@"message_id" : @(messageId)}
	   completion:^(NSDictionary *m){
		if (completion)
			completion([m[@"@type"] isEqualToString:@"message"]
					? TGFlattenMessage(m) : nil);
	}];
}


- (void)recentStickersWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getRecentStickers", @"is_attached" : @NO}
	   completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sticker in result[@"stickers"]){
			NSNumber *fileId = sticker[@"sticker"][@"id"];
			if (!fileId)
				continue;
			NSString *format = sticker[@"format"][@"@type"] ?: @"";
			[out addObject:@{
				@"fileId"     : fileId,
				@"emoji"      : sticker[@"emoji"] ?: @"",
				// .tgs and .webm cannot be drawn as a thumbnail cheaply, so the
				// panel falls back to the emoji for those.
				@"isAnimated" : @(![format isEqualToString:@"stickerFormatWebp"]),
				@"thumbId"    : sticker[@"thumbnail"][@"file"][@"id"] ?: @0,
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)sendStickerWithFileId:(NSInteger)fileId toChat:(int64_t)chatId thread:(int64_t)threadId {
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type"   : @"inputMessageSticker",
			@"sticker" : @{
				@"@type"   : @"inputSticker",
				@"sticker" : @{@"@type" : @"inputFileId", @"id" : @(fileId)},
			},
		},
	}];
}

- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
                 toChat:(int64_t)chatId thread:(int64_t)threadId {
	if (!path.length)
		return;

	NSDictionary *attributes = [[NSFileManager defaultManager]
			attributesOfItemAtPath:path error:nil];
	NSLog(@"TGClient: sending voice %@ (%llu bytes, %lds) to %lld",
			path.lastPathComponent, [attributes fileSize], (long)seconds, chatId);

	// Answered rather than fire-and-forget: a rejected voice note is silent
	// otherwise, and the file it points at lives in a temporary directory.
	[self request:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type"      : @"inputMessageVoiceNote",
			@"voice_note" : @{
				@"@type"      : @"inputVoiceNote",
				@"voice_note" : @{@"@type" : @"inputFileLocal", @"path" : path},
				@"duration"   : @(seconds),
				@"waveform"   : @"",
			},
		},
	} completion:^(NSDictionary *result){
		if ([result[@"@type"] isEqualToString:@"error"])
			NSLog(@"TGClient: voice rejected: %@ %@",
					result[@"code"], result[@"message"]);
		else
			NSLog(@"TGClient: voice accepted, message %@", result[@"id"]);
	}];
}

- (void)sendVideoAtPath:(NSString *)path toChat:(int64_t)chatId {
	if (!path.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type" : @"inputMessageVideo",
			@"video" : @{
				@"@type" : @"inputVideo",
				@"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
			},
		},
	}];
}

- (void)sendLocation:(double)latitude longitude:(double)longitude toChat:(int64_t)chatId {
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type"    : @"inputMessageLocation",
			@"location" : @{
				@"@type"     : @"location",
				@"latitude"  : @(latitude),
				@"longitude" : @(longitude),
			},
		},
	}];
}

- (void)sendContactNamed:(NSString *)name phone:(NSString *)phone toChat:(int64_t)chatId {
	if (!phone.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type"   : @"inputMessageContact",
			@"contact" : @{
				@"@type"        : @"contact",
				@"phone_number" : phone,
				@"first_name"   : name ?: @"",
				@"user_id"      : @(0),
			},
		},
	}];
}

- (void)sendPhotoAtPath:(NSString *)path toChat:(int64_t)chatId {
	if (!path.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type" : @"inputMessagePhoto",
			@"photo" : @{
				@"@type" : @"inputPhoto",
				@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
			},
		},
	}];
}

- (void)votePoll:(int64_t)messageId inChat:(int64_t)chatId options:(NSArray *)optionIds {
	[self send:@{
		@"@type"      : @"setPollAnswer",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"option_ids" : optionIds ?: @[],
	}];
}

- (void)reactTo:(int64_t)messageId inChat:(int64_t)chatId emoji:(NSString *)emoji {
	[self send:@{
		@"@type"      : @"addMessageReaction",
		@"chat_id"    : @(chatId),
		@"message_id" : @(messageId),
		@"reaction_type" : @{@"@type" : @"reactionTypeEmoji", @"emoji" : emoji},
		@"is_big"     : @NO,
		@"update_recent_reactions" : @YES,
	}];
}

- (void)deleteMessage:(int64_t)messageId inChat:(int64_t)chatId {
	[self send:@{
		@"@type"        : @"deleteMessages",
		@"chat_id"      : @(chatId),
		@"message_ids"  : @[@(messageId)],
		@"revoke"       : @YES,
	}];
}

- (void)markRead:(NSArray *)messageIds inChat:(int64_t)chatId {
	if (!messageIds.count)
		return;
	[self send:@{
		@"@type"       : @"viewMessages",
		@"chat_id"     : @(chatId),
		@"message_ids" : messageIds,
		@"force_read"  : @YES,
	}];
}

#pragma mark - contacts

- (void)contactsWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getContacts"} completion:^(NSDictionary *result){
		NSArray *ids = result[@"user_ids"];
		if (![ids isKindOfClass:NSArray.class]){
			if (completion) completion(@[]);
			return;
		}

		// Fetch each user; finish when the last one answers.
		NSMutableArray *users = [NSMutableArray array];
		__block NSUInteger left = ids.count;
		if (!left){
			if (completion) completion(@[]);
			return;
		}
		for (NSNumber *uid in ids){
			[weakSelf request:@{@"@type" : @"getUser", @"user_id" : uid}
				   completion:^(NSDictionary *u){
				if ([u[@"@type"] isEqualToString:@"user"]){
					// The photo id travels with the row, so the list can show a
					// face rather than a letter for everyone who has one.
					[weakSelf cacheProfilePhoto:u];
					NSDictionary *status = TGUserStatusInfo(u[@"status"]);
					[users addObject:@{
						@"id"          : u[@"id"] ?: @(0),
						@"first_name"  : u[@"first_name"] ?: @"",
						@"last_name"   : u[@"last_name"] ?: @"",
						@"phone"       : u[@"phone_number"] ?: @"",
						@"username"    : TGActiveUsername(u) ?: @"",
						@"photoFileId" : u[@"profile_photo"][@"small"][@"id"] ?: [NSNull null],
						@"photoUniqueId" : u[@"profile_photo"][@"small"][@"remote"][@"unique_id"] ?: [NSNull null],
						@"isOnline"    : status[@"isOnline"],
						@"statusText"  : status[@"text"],
						@"statusRank"  : status[@"rank"],
					}];
				}
				if (--left == 0 && completion)
					completion(users);
			}];
		}
	}];
}

- (void)addContactWithPhone:(NSString *)phone
				   firstName:(NSString *)firstName
					lastName:(NSString *)lastName
				  completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"importContacts",
		@"contacts" : @[@{
			@"@type"     : @"contact",
			@"phone_number" : phone ?: @"",
			@"first_name"   : firstName ?: @"",
			@"last_name"    : lastName ?: @"",
			@"user_id"      : @(0),
		}],
	} completion:^(NSDictionary *result){
		BOOL ok = [result[@"@type"] isEqualToString:@"importedContacts"];
		if (completion) completion(ok);
	}];
}

- (void)privateChatWithUser:(int64_t)userId completion:(void (^)(int64_t))completion {
	[self request:@{
		@"@type"   : @"createPrivateChat",
		@"user_id" : @(userId),
		@"force"   : @NO,
	} completion:^(NSDictionary *chat){
		if (completion)
			completion([chat[@"id"] longLongValue]);
	}];
}

- (void)userForPhone:(NSString *)phone completion:(void (^)(NSDictionary *))completion {
	if (!phone.length){
		if (completion) completion(nil);
		return;
	}
	[self request:@{
		@"@type"        : @"searchUserByPhoneNumber",
		@"phone_number" : phone,
	} completion:^(NSDictionary *u){
		if (![u[@"@type"] isEqualToString:@"user"]){
			if (completion) completion(nil);
			return;
		}
		if (completion) completion(@{
			@"id"         : u[@"id"] ?: @(0),
			@"first_name" : u[@"first_name"] ?: @"",
			@"last_name"  : u[@"last_name"] ?: @"",
			@"phone"      : u[@"phone_number"] ?: @"",
			@"username"   : TGActiveUsername(u) ?: @"",
		});
	}];
}

#pragma mark - maintenance

#pragma mark - people

- (void)setUser:(int64_t)userId blocked:(BOOL)blocked {
	[self send:@{
		@"@type"      : @"setMessageSenderBlockList",
		@"sender_id"  : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
		// A null block list is how TDLib spells "not blocked".
		@"block_list" : blocked ? @{@"@type" : @"blockListMain"} : [NSNull null],
	}];
}

- (void)isUserBlocked:(int64_t)userId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *full){
		if (completion)
			completion([full[@"block_list"][@"@type"] isEqualToString:@"blockListMain"]);
	}];
}

- (void)giftsForUser:(int64_t)userId completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"    : @"getReceivedGifts",
		@"owner_id" : @{@"@type" : @"messageSenderUser", @"user_id" : @(userId)},
		@"offset"   : @"",
		@"limit"    : @(20),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *entry in result[@"gifts"]){
			NSDictionary *gift = entry[@"gift"][@"gift"] ?: entry[@"gift"];
			[out addObject:@{
				@"title"     : gift[@"title"] ?: @"Gift",
				@"starCount" : gift[@"star_count"] ?: @0,
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)premiumStateWithCompletion:(void (^)(NSString *))completion {
	if (![self.me[@"is_premium"] boolValue]){
		if (completion) completion(nil);
		return;
	}
	[self request:@{@"@type" : @"getOption", @"name" : @"premium_expiration_date"}
	   completion:^(NSDictionary *option){
		double until = [option[@"value"] doubleValue];
		if (until <= 0){
			if (completion) completion(@"Active");
			return;
		}
		static NSDateFormatter *fmt = nil;
		if (!fmt){
			fmt = [[NSDateFormatter alloc] init];
			[fmt setDateFormat:@"d MMM yyyy"];
		}
		if (completion)
			completion([NSString stringWithFormat:@"Until %@", [fmt stringFromDate:
					[NSDate dateWithTimeIntervalSince1970:until]]]);
	}];
}

#pragma mark - storage

- (void)storageStatsWithCompletion:(void (^)(long long, NSInteger))completion {
	[self request:@{@"@type" : @"getStorageStatisticsFast"}
	   completion:^(NSDictionary *stats){
		if (completion)
			completion([stats[@"files_size"] longLongValue],
					   [stats[@"file_count"] integerValue]);
	}];
}

- (void)clearCacheOfTypes:(NSArray *)kinds completion:(void (^)(long long))completion {
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *kind in kinds)
		[types addObject:@{@"@type" : kind}];

	// count/ttl/size of -1 mean "no limit of that sort", so only the file
	// types listed decide what goes.
	[self request:@{
		@"@type"          : @"optimizeStorage",
		@"size"           : @(-1),
		@"ttl"            : @(-1),
		@"count"          : @(-1),
		@"immunity_delay" : @(0),
		@"file_types"     : types,
		@"chat_ids"       : @[],
		@"exclude_chat_ids" : @[],
		@"return_deleted_file_statistics" : @YES,
		@"chat_limit"     : @(0),
	} completion:^(NSDictionary *stats){
		long long freed = 0;
		for (NSDictionary *byChat in stats[@"by_chat"])
			for (NSDictionary *byType in byChat[@"by_file_type"])
				freed += [byType[@"size"] longLongValue];
		if (completion) completion(freed);
	}];
}

#pragma mark - account

- (void)sessionsWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getActiveSessions"} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *session in result[@"sessions"]){
			[out addObject:@{
				@"id"         : session[@"id"] ?: @0,
				@"name"       : session[@"application_name"] ?: @"",
				@"platform"   : [NSString stringWithFormat:@"%@ %@",
						session[@"platform"] ?: @"", session[@"system_version"] ?: @""],
				@"ip"         : session[@"ip_address"] ?: session[@"ip"] ?: @"",
				@"isCurrent"  : session[@"is_current"] ?: @NO,
				@"lastActive" : session[@"last_active_date"] ?: @0,
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)terminateSession:(long long)sessionId {
	[self send:@{@"@type" : @"terminateSession", @"session_id" : @(sessionId)}];
}

- (void)setName:(NSString *)firstName last:(NSString *)lastName {
	[self send:@{
		@"@type"      : @"setName",
		@"first_name" : firstName ?: @"",
		@"last_name"  : lastName ?: @"",
	}];
}

- (void)setBio:(NSString *)bio {
	[self send:@{@"@type" : @"setBio", @"bio" : bio ?: @""}];
}

- (void)setUsername:(NSString *)username completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"setUsername", @"username" : username ?: @""}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(![result[@"@type"] isEqualToString:@"error"]);
	}];
}

- (void)clearLocalDatabase {
	// Wipes cached chats/messages but keeps the session.
	[self send:@{@"@type" : @"optimizeStorage", @"chat_limit" : @(0)}];
	[self.chatsById removeAllObjects];
	[self rebuildChats];
}

#pragma mark - chats

- (void)loadChats {
	// TDLib only emits updateNewChat/updateChatPosition after the list is
	// asked for; without loadChats nothing about chats ever arrives. It also
	// loads in batches - one call is one batch, and it answers with error 404
	// once everything is loaded - so this has to be repeated until the list
	// stops growing.
	if (self.chatListComplete)
		return;
	self.chatsAtLastLoad = self.chatsById.count;
	NSLog(@"TGClient: loadChats attempt %lu (have %lu)",
			(unsigned long)self.loadChatsAttempts + 1,
			(unsigned long)self.chatsById.count);
	__weak typeof(self) weakLoader = self;
	[self request:@{
		@"@type"     : @"loadChats",
		@"chat_list" : @{@"@type" : @"chatListMain"},
		@"limit"     : @(50),
	} completion:^(NSDictionary *result){
		TGClient *loader = weakLoader;
		if (!loader)
			return;
		if ([result[@"@type"] isEqualToString:@"error"] &&
			[result[@"code"] intValue] == 404){
			loader.chatListComplete = YES;
			NSLog(@"TGClient: chat list complete (%lu)",
					(unsigned long)loader.chatsById.count);
			[loader dropChatsMissingFromServerList];
		}
	}];
	[self request:@{
		@"@type"     : @"loadChats",
		@"chat_list" : @{@"@type" : @"chatListArchive"},
		@"limit"     : @(50),
	} completion:^(NSDictionary *result){ (void)result; }];

	// A batch beyond the first needs a server round trip, so silence for a
	// second or two means nothing. Keep asking on a timer and stop only when
	// TDLib says 404 (everything loaded) or after a sane number of tries.
	self.loadChatsAttempts++;
	if (self.loadChatsAttempts > 12)
		return;

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		TGClient *me = weakSelf;
		if (me && !me.chatListComplete)
			[me loadChats];
	});
}

/// Preview text for a chat's last message. TDLib nests the content by type.
static NSString *TGMessagePreview(NSDictionary *message) {
	NSDictionary *content = message[@"content"];
	NSString *ctype = content[@"@type"];

	if ([ctype isEqualToString:@"messageText"])
		return content[@"text"][@"text"] ?: @"";

	NSString *caption = content[@"caption"][@"text"];
	if ([caption isKindOfClass:NSString.class] && caption.length)
		return caption;

	if ([ctype isEqualToString:@"messagePhoto"])
		return @"Photo";
	if ([ctype isEqualToString:@"messageVideo"])
		return @"Video";
	if ([ctype isEqualToString:@"messageVoiceNote"])
		return @"Voice message";
	if ([ctype isEqualToString:@"messageVideoNote"])
		return @"Video message";
	if ([ctype isEqualToString:@"messageSticker"])
		return @"Sticker";
	if ([ctype isEqualToString:@"messageDocument"]){
		NSString *name = content[@"document"][@"file_name"];
		return ([name isKindOfClass:NSString.class] && name.length) ? name : @"Document";
	}
	if ([ctype isEqualToString:@"messageAudio"]){
		NSString *title = content[@"audio"][@"title"];
		return ([title isKindOfClass:NSString.class] && title.length) ? title : @"Audio";
	}
	if ([ctype isEqualToString:@"messageAnimation"])
		return @"GIF";
	if ([ctype isEqualToString:@"messageAnimatedEmoji"])
		return content[@"emoji"] ?: @"Emoji";
	if ([ctype isEqualToString:@"messageContact"])
		return @"Contact";
	if ([ctype isEqualToString:@"messageVenue"])
		return @"Venue";
	if ([ctype isEqualToString:@"messageLocation"])
		return @"Location";
	if ([ctype isEqualToString:@"messageLiveLocation"])
		return @"Live location";
	if ([ctype isEqualToString:@"messageCall"])
		return @"Call";
	if ([ctype isEqualToString:@"messageChatJoinByLink"] ||
		[ctype isEqualToString:@"messageChatJoinByRequest"])
		return @"joined the group";
	if ([ctype isEqualToString:@"messageChatAddMembers"])
		return @"added a member";
	if ([ctype isEqualToString:@"messageChatDeleteMember"])
		return @"left the group";
	if ([ctype isEqualToString:@"messageChatChangeTitle"])
		return @"renamed the group";
	if ([ctype isEqualToString:@"messageChatChangePhoto"])
		return @"changed the group photo";
	if ([ctype isEqualToString:@"messagePinMessage"])
		return @"pinned a message";
	if ([ctype isEqualToString:@"messagePoll"])
		return @"Poll";
	// Everything else reads as its own type name turned back into a sentence,
	// the same way the chat itself renders it.
	return ctype.length ? TGPhraseFromTypeName(ctype) : @"";
}

static NSString *TGDraftText(id draftMessage) {
	if (![draftMessage isKindOfClass:NSDictionary.class])
		return @"";
	id text = ((NSDictionary *)draftMessage)[@"content"][@"text"][@"text"];
	return [text isKindOfClass:NSString.class] ? text : @"";
}

/// Chats are ordered by the "order" of their position in a list. It is an
/// int64 sent as a string, so it must not be compared as a string.
static int64_t TGOrderInList(NSArray *positions, NSString *listType) {
	for (NSDictionary *p in positions){
		NSDictionary *list = p[@"list"];
		if ([list[@"@type"] isEqualToString:listType])
			return (int64_t)[p[@"order"] longLongValue];
	}
	return 0;
}

static BOOL TGPinnedInMain(NSArray *positions) {
	for (NSDictionary *p in positions)
		if ([p[@"list"][@"@type"] isEqualToString:@"chatListMain"])
			return [p[@"is_pinned"] boolValue];
	return NO;
}

static int64_t TGMainListOrder(NSArray *positions) {
	return TGOrderInList(positions, @"chatListMain");
}

static int64_t TGArchiveOrder(NSArray *positions) {
	return TGOrderInList(positions, @"chatListArchive");
}

/// Small profile photo of a user, so a group message can show who wrote it.
- (void)cacheProfilePhoto:(NSDictionary *)user {
	NSNumber *fileId = user[@"profile_photo"][@"small"][@"id"];
	if (user[@"id"] && fileId)
		self.userPhotosById[user[@"id"]] = fileId;
}

- (int64_t)savedMessagesChatId {
	return [self.me[@"id"] longLongValue];
}

- (void)statusForUser:(int64_t)userId completion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *user){
		if (completion) completion(TGUserStatusInfo(user[@"status"])[@"text"]);
	}];
}

- (NSNumber *)photoFileIdForUserId:(int64_t)userId {
	return self.userPhotosById[@(userId)];
}

- (void)membersOfChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSDictionary *type = chat[@"type"];
		NSString *kind = type[@"@type"];

		void (^collect)(NSArray *) = ^(NSArray *members){
			TGClient *me = weakSelf;
			NSMutableArray *out = [NSMutableArray array];
			for (NSDictionary *member in members){
				int64_t userId = [member[@"member_id"][@"user_id"] longLongValue];
				if (!userId)
					continue;
				[out addObject:@{
					@"id"   : @(userId),
					@"name" : [me nameForUserId:userId] ?: @"",
				}];
			}
			if (completion) completion(out);
		};

		if ([kind isEqualToString:@"chatTypeBasicGroup"]){
			[weakSelf request:@{
				@"@type"          : @"getBasicGroupFullInfo",
				@"basic_group_id" : type[@"basic_group_id"],
			} completion:^(NSDictionary *full){ collect(full[@"members"]); }];
			return;
		}
		if ([kind isEqualToString:@"chatTypeSupergroup"]){
			[weakSelf request:@{
				@"@type"        : @"getSupergroupMembers",
				@"supergroup_id": type[@"supergroup_id"],
				@"filter"       : @{@"@type" : @"supergroupMembersFilterRecent"},
				@"offset"       : @(0),
				@"limit"        : @(50),
			} completion:^(NSDictionary *result){ collect(result[@"members"]); }];
			return;
		}
		if (completion) completion(@[]);
	}];
}

- (void)canSendInChat:(int64_t)chatId completion:(void (^)(BOOL, BOOL))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSDictionary *type = chat[@"type"];
		BOOL isChannel = [type[@"@type"] isEqualToString:@"chatTypeSupergroup"] &&
						 [type[@"is_channel"] boolValue];
		// TDLib answers this directly; permissions alone would miss the case
		// where the user is not a member at all.
		BOOL canSend = [chat[@"permissions"][@"can_send_basic_messages"] boolValue];
		if (isChannel)
			canSend = [chat[@"can_be_edited"] boolValue] ||
					  [chat[@"permissions"][@"can_send_basic_messages"] boolValue];
		if (completion) completion(canSend, isChannel);
	}];
}

- (void)deleteChat:(int64_t)chatId {
	// A group has to be left as well, or it comes straight back on the next
	// message.
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSString *kind = chat[@"type"][@"@type"];
		BOOL isMembership = [kind isEqualToString:@"chatTypeSupergroup"] ||
							[kind isEqualToString:@"chatTypeBasicGroup"];
		[self send:@{
			@"@type"       : @"deleteChatHistory",
			@"chat_id"     : @(chatId),
			@"remove_from_chat_list" : @YES,
			@"revoke"      : @NO,
		}];
		if (isMembership)
			[self send:@{@"@type" : @"leaveChat", @"chat_id" : @(chatId)}];
	}];
}

- (void)setChat:(int64_t)chatId joined:(BOOL)joined {
	[self send:@{@"@type" : joined ? @"joinChat" : @"leaveChat", @"chat_id" : @(chatId)}];
}

- (void)pinnedMessageForChat:(int64_t)chatId
                  completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getChatPinnedMessage", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *m){
		if (completion)
			completion([m[@"@type"] isEqualToString:@"message"] ? TGFlattenMessage(m) : nil);
	}];
}

- (void)setChat:(int64_t)chatId pinned:(BOOL)pinned {
	[self send:@{
		@"@type"     : @"toggleChatIsPinned",
		@"chat_list" : @{@"@type" : @"chatListMain"},
		@"chat_id"   : @(chatId),
		@"is_pinned" : @(pinned),
	}];
}

/// A folder is a chat list of its own in TDLib, so this is getChats against
/// that list; the rows themselves are the ones the client already holds.
- (void)chatsInFolder:(NSInteger)folderId completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"     : @"getChats",
		@"chat_list" : @{@"@type" : @"chatListFolder",
						 @"chat_folder_id" : @(folderId)},
		@"limit"     : @(100),
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		if (!me){
			if (completion) completion(@[]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (NSNumber *chatId in result[@"chat_ids"]){
			NSDictionary *info = me.chatsById[chatId];
			if (info)
				[out addObject:info];
		}
		NSLog(@"TGClient: folder %ld holds %lu chats",
				(long)folderId, (unsigned long)out.count);
		if (completion) completion(out);
	}];
}

/// A forum keeps several threads in one chat; each topic reads like a chat row.
- (void)forumTopicsForChat:(int64_t)chatId completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"                    : @"getForumTopics",
		@"chat_id"                  : @(chatId),
		@"query"                    : @"",
		@"offset_date"              : @(0),
		@"offset_message_id"        : @(0),
		@"offset_forum_topic_id"    : @(0),
		@"limit"                    : @(100),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *topic in result[@"topics"]){
			NSDictionary *info = topic[@"info"];
			NSDictionary *last = topic[@"last_message"];
			[out addObject:@{
				@"threadId" : info[@"forum_topic_id"] ?: @(0),
				@"name"     : info[@"name"] ?: @"",
				@"text"     : [last isKindOfClass:NSDictionary.class]
								? (TGMessagePreview(last) ?: @"") : @"",
				@"unread"   : topic[@"unread_count"] ?: @(0),
				@"date"     : last[@"date"] ?: @(0),
			}];
		}
		NSLog(@"TGClient: %lu forum topics", (unsigned long)out.count);
		if (completion) completion(out);
	}];
}

- (void)userProfile:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getUserFullInfo", @"user_id" : @(userId)}
	   completion:^(NSDictionary *full){
		NSDictionary *birth = full[@"birthdate"];
		NSString *birthday = @"";
		if ([birth[@"day"] integerValue] > 0){
			static NSArray *months = nil;
			if (!months) months = @[@"", @"January", @"February", @"March", @"April",
					@"May", @"June", @"July", @"August", @"September", @"October",
					@"November", @"December"];
			NSInteger month = [birth[@"month"] integerValue];
			birthday = [NSString stringWithFormat:@"%@ %@",
					(month > 0 && month < 13) ? months[month] : @"", birth[@"day"]];
		}
		if (completion) completion(@{
			@"bio"          : full[@"bio"][@"text"] ?: @"",
			@"commonGroups" : full[@"group_in_common_count"] ?: @0,
			@"birthday"     : birthday,
			// A user who has calls turned off should not be offered one.
			@"canCall"      : full[@"can_be_called"] ?: @NO,
			@"canVideoCall" : full[@"supports_video_calls"] ?: @NO,
		});
	}];
}

- (void)chatProfile:(int64_t)chatId completion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSString *kind = chat[@"type"][@"@type"];
		void (^answer)(NSDictionary *) = ^(NSDictionary *full){
			if (completion) completion(@{
				@"description" : full[@"description"] ?: @"",
				@"members"     : full[@"member_count"] ?: @([full[@"members"] count]),
				@"admins"      : full[@"administrator_count"] ?: @0,
				@"inviteLink"  : full[@"invite_link"][@"invite_link"] ?: @"",
			});
		};

		if ([kind isEqualToString:@"chatTypeSupergroup"]){
			[weakSelf request:@{@"@type" : @"getSupergroupFullInfo",
								@"supergroup_id" : chat[@"type"][@"supergroup_id"]}
				   completion:answer];
		} else if ([kind isEqualToString:@"chatTypeBasicGroup"]){
			[weakSelf request:@{@"@type" : @"getBasicGroupFullInfo",
								@"basic_group_id" : chat[@"type"][@"basic_group_id"]}
				   completion:answer];
		} else {
			answer(@{});
		}
	}];
}

- (BOOL)isChatMuted:(int64_t)chatId {
	return [self.chatsById[@(chatId)][@"isMuted"] boolValue];
}

- (void)clearHistoryInChat:(int64_t)chatId {
	// Without remove_from_chat_list this empties the chat and leaves it there,
	// which is what "clear history" means as opposed to "delete chat".
	[self send:@{
		@"@type"                 : @"deleteChatHistory",
		@"chat_id"               : @(chatId),
		@"remove_from_chat_list" : @NO,
		@"revoke"                : @NO,
	}];
}

- (void)setChat:(int64_t)chatId autoDeleteSeconds:(NSInteger)seconds {
	[self send:@{
		@"@type"   : @"setChatMessageAutoDeleteTime",
		@"chat_id" : @(chatId),
		@"message_auto_delete_time" : @(seconds),
	}];
}

#pragma mark - account settings

/// TDLib names the three scopes; the app names them shortly.
static NSString *TGScopeType(NSString *scope) {
	if ([scope isEqualToString:@"groups"])   return @"notificationSettingsScopeGroupChats";
	if ([scope isEqualToString:@"channels"]) return @"notificationSettingsScopeChannelChats";
	return @"notificationSettingsScopePrivateChats";
}

- (void)notificationsMutedForScope:(NSString *)scope
                        completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"getScopeNotificationSettings",
		@"scope" : @{@"@type" : TGScopeType(scope)},
	} completion:^(NSDictionary *settings){
		// There is no flag: a very large mute_for is how muting is expressed.
		if (completion) completion([settings[@"mute_for"] integerValue] > 0);
	}];
}

- (void)setScope:(NSString *)scope muted:(BOOL)muted {
	[self send:@{
		@"@type" : @"setScopeNotificationSettings",
		@"scope" : @{@"@type" : TGScopeType(scope)},
		@"notification_settings" : @{
			@"@type"        : @"scopeNotificationSettings",
			@"mute_for"     : @(muted ? 365 * 24 * 3600 : 0),
			@"sound_id"     : @(0),
			@"show_preview" : @YES,
		},
	}];
}

- (void)privacyRule:(NSString *)setting completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"   : @"getUserPrivacySettingRules",
		@"setting" : @{@"@type" : [@"userPrivacySetting" stringByAppendingString:setting]},
	} completion:^(NSDictionary *rules){
		// The rules are a list, most specific first. The three answers a client
		// offers are the shapes of the first rule; anything more elaborate,
		// set from another client, reads as the closest of the three.
		NSString *first = [rules[@"rules"] firstObject][@"@type"];
		NSString *value = @"nobody";
		if ([first isEqualToString:@"userPrivacySettingRuleAllowAll"])
			value = @"everybody";
		else if ([first isEqualToString:@"userPrivacySettingRuleAllowContacts"])
			value = @"contacts";
		if (completion) completion(value);
	}];
}

- (void)setPrivacyRule:(NSString *)setting to:(NSString *)value {
	NSString *rule = @"userPrivacySettingRuleRestrictAll";
	if ([value isEqualToString:@"everybody"])
		rule = @"userPrivacySettingRuleAllowAll";
	else if ([value isEqualToString:@"contacts"])
		rule = @"userPrivacySettingRuleAllowContacts";

	[self send:@{
		@"@type"   : @"setUserPrivacySettingRules",
		@"setting" : @{@"@type" : [@"userPrivacySetting" stringByAppendingString:setting]},
		@"rules"   : @{@"@type" : @"userPrivacySettingRules",
					   @"rules" : @[@{@"@type" : rule}]},
	}];
}

- (void)blockedUsersWithCompletion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"       : @"getBlockedMessageSenders",
		@"block_list"  : @{@"@type" : @"blockListMain"},
		@"offset"      : @(0),
		@"limit"       : @(100),
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *sender in result[@"senders"]){
			NSNumber *userId = sender[@"user_id"];
			if (!userId)
				continue;
			[out addObject:@{
				@"id"   : userId,
				@"name" : [weakSelf nameForUserId:userId.longLongValue] ?: @"",
			}];
		}
		if (completion) completion(out);
	}];
}

- (void)accountTtlWithCompletion:(void (^)(NSInteger))completion {
	[self request:@{@"@type" : @"getAccountTtl"} completion:^(NSDictionary *ttl){
		if (completion) completion([ttl[@"days"] integerValue]);
	}];
}

- (void)setAccountTtlDays:(NSInteger)days {
	[self send:@{
		@"@type" : @"setAccountTtl",
		@"ttl"   : @{@"@type" : @"accountTtl", @"days" : @(days)},
	}];
}

static NSArray *TGPacksFrom(NSDictionary *target) {
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *pack in target[@"language_packs"]){
		if (![pack[@"id"] length])
			continue;
		[out addObject:@{@"id"   : pack[@"id"],
						 @"name" : pack[@"native_name"] ?: pack[@"name"] ?: pack[@"id"]}];
	}
	return out;
}

- (void)languagesWithCompletion:(void (^)(NSArray *, NSString *))completion {
	__weak typeof(self) weakSelf = self;

	void (^answer)(NSArray *) = ^(NSArray *packs){
		[weakSelf request:@{@"@type" : @"getOption",
							@"name"  : @"language_pack_id"}
			   completion:^(NSDictionary *option){
			NSString *current = option[@"value"] ?: @"en";
			NSArray *list = packs;
			// With no list at all, say what is in use rather than nothing:
			// an empty screen looks broken and tells you less than one row.
			if (!list.count)
				list = @[@{@"id" : current, @"name" : current}];
			if (completion) completion(list, current);
		}];
	};

	// The full list comes from Telegram's servers, and they answer 404 to an
	// api_id with no language packs of its own - which is this app's case. The
	// local query still knows about the packs already on the device.
	[self request:@{@"@type" : @"getLocalizationTargetInfo",
					@"only_local" : @NO}
	   completion:^(NSDictionary *target){
		NSArray *packs = TGPacksFrom(target);
		if (packs.count){
			answer(packs);
			return;
		}
		[weakSelf request:@{@"@type" : @"getLocalizationTargetInfo",
							@"only_local" : @YES}
			   completion:^(NSDictionary *local){
			answer(TGPacksFrom(local));
		}];
	}];
}

- (void)setLanguage:(NSString *)packId {
	// The strings themselves are the official client's; this app is written in
	// English throughout. Setting it still matters: TDLib uses it for the text
	// it generates, and other clients on the account follow it.
	[self send:@{
		@"@type" : @"setOption",
		@"name"  : @"language_pack_id",
		@"value" : @{@"@type" : @"optionValueString", @"value" : packId ?: @"en"},
	}];
}

- (void)chatWithUsername:(NSString *)username
              completion:(void (^)(int64_t, NSString *))completion {
	// searchPublicChat resolves the name and puts the chat in the local
	// database in one step, which is what a link or a QR code needs.
	[self request:@{
		@"@type"    : @"searchPublicChat",
		@"username" : username ?: @"",
	} completion:^(NSDictionary *chat){
		if (completion)
			completion([chat[@"id"] longLongValue], chat[@"title"]);
	}];
}

/// Archiving is a move between the two chat lists, not a flag on the chat.
/// TDLib answers with updateChatPosition, so the list rebuilds itself.
- (void)setChat:(int64_t)chatId archived:(BOOL)archived {
	[self send:@{
		@"@type"     : @"addChatToList",
		@"chat_id"   : @(chatId),
		@"chat_list" : @{@"@type" : (archived ? @"chatListArchive" : @"chatListMain")},
	}];
}

- (void)setChat:(int64_t)chatId muted:(BOOL)muted {
	// A very large mute_for is how TDLib expresses "muted", there is no flag.
	[self send:@{
		@"@type" : @"setChatNotificationSettings",
		@"chat_id" : @(chatId),
		@"notification_settings" : @{
			@"@type"                : @"chatNotificationSettings",
			@"use_default_mute_for" : @NO,
			@"mute_for"             : @(muted ? 365 * 24 * 3600 : 0),
		},
	}];
}

- (NSNumber *)photoFileIdForChat:(int64_t)chatId {
	for (NSArray *list in @[self.chats, self.archivedChats])
		for (NSDictionary *c in list)
			if ([c[@"id"] longLongValue] == chatId)
				return c[@"photoFileId"];
	return nil;
}

- (void)userInfo:(int64_t)userId completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *u){
		if (completion) completion([u[@"@type"] isEqualToString:@"user"] ? u : nil);
	}];
}

- (void)mediaInChat:(int64_t)chatId filter:(NSString *)filter
         completion:(void (^)(NSArray *))completion {
	[self request:@{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(chatId),
		@"query"           : @"",
		@"from_message_id" : @(0),
		@"offset"          : @(0),
		@"limit"           : @(60),
		@"filter"          : @{@"@type" : filter},
	} completion:^(NSDictionary *result){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *m in result[@"messages"]){
			NSDictionary *flat = TGFlattenMessage(m);
			if (flat) [out addObject:flat];
		}
		if (completion) completion(out);
	}];
}

- (NSString *)nameForUserId:(int64_t)userId {
	return self.usersById[@(userId)];
}

/// Member count for a group, so the chat header can carry a subtitle.
- (void)memberCountForChat:(int64_t)chatId completion:(void (^)(NSInteger count))completion {
	[self request:@{@"@type" : @"getChat", @"chat_id" : @(chatId)}
	   completion:^(NSDictionary *chat){
		NSDictionary *type = chat[@"type"];
		NSString *t = type[@"@type"];
		if ([t isEqualToString:@"chatTypeBasicGroup"]){
			[self request:@{@"@type" : @"getBasicGroupFullInfo",
							@"basic_group_id" : type[@"basic_group_id"]}
			   completion:^(NSDictionary *full){
				if (completion) completion([full[@"members"] count]);
			}];
		} else if ([t isEqualToString:@"chatTypeSupergroup"]){
			[self request:@{@"@type" : @"getSupergroupFullInfo",
							@"supergroup_id" : type[@"supergroup_id"]}
			   completion:^(NSDictionary *full){
				if (completion) completion([full[@"member_count"] integerValue]);
			}];
		} else if (completion){
			completion(0);
		}
	}];
}

- (void)ensureUserName:(int64_t)userId completion:(void (^)(void))completion {
	if (userId == 0 || self.usersById[@(userId)]){
		if (completion) completion();
		return;
	}
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getUser", @"user_id" : @(userId)}
	   completion:^(NSDictionary *u){
		TGClient *me = weakSelf;
		if (me && [u[@"@type"] isEqualToString:@"user"]){
			NSString *name = [[NSString stringWithFormat:@"%@ %@",
					u[@"first_name"] ?: @"", u[@"last_name"] ?: @""]
					stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (!name.length)
				name = TGActiveUsername(u) ?: @"";
			if (name.length)
				me.usersById[@(userId)] = name;
			[me cacheProfilePhoto:u];
		}
		if (completion) completion();
	}];
}

// A forum keeps several threads in one chat, so it opens on a topic list
// rather than a merged stream. The flag is on the supergroup, not here:
// the chat only names which supergroup it is, and reading is_forum off the
// chat - which has no such field - meant no forum was ever recognised.
- (void)mergeForumFlagFromChat:(NSDictionary *)chat
                          into:(NSMutableDictionary *)info
                        chatId:(NSNumber *)chatId {
	NSNumber *supergroupId = chat[@"type"][@"supergroup_id"];
	if (!supergroupId)
		return;

	info[@"supergroupId"] = supergroupId;
	NSNumber *known = self.forumSupergroups[supergroupId];
	if (known){
		info[@"isForum"] = known;
		return;
	}

	// Not seen yet: ask, and the answer updates the row in place.
	__weak typeof(self) weakSelf = self;
	[self request:@{@"@type" : @"getSupergroup",
					@"supergroup_id" : supergroupId}
	   completion:^(NSDictionary *group){
		TGClient *me = weakSelf;
		if (!me || !group[@"id"])
			return;
		me.forumSupergroups[group[@"id"]] = @([group[@"is_forum"] boolValue]);
		NSMutableDictionary *row = me.chatsById[chatId];
		row[@"isForum"] = @([group[@"is_forum"] boolValue]);
		[me rebuildChats];
	}];
}

- (void)mergeChat:(NSDictionary *)chat {
	if (![chat isKindOfClass:NSDictionary.class])
		return;

	NSNumber *chatId = chat[@"id"];
	if (!chatId)
		return;

	if (!self.chatsConfirmedByServer)
		self.chatsConfirmedByServer = [NSMutableSet set];
	[self.chatsConfirmedByServer addObject:chatId];

	NSMutableDictionary *info = self.chatsById[chatId];
	if (!info){
		info = [NSMutableDictionary dictionary];
		self.chatsById[chatId] = info;
	}

	info[@"id"] = chatId;
	if (chat[@"title"])
		info[@"title"] = chat[@"title"];

	// The chat with yourself is Saved Messages everywhere in Telegram, not a
	// conversation under your own name and photo.
	if ([chatId longLongValue] == [self savedMessagesChatId] &&
		[self savedMessagesChatId] != 0){
		info[@"title"] = @"Saved Messages";
		info[@"isSaved"] = @YES;
		[info removeObjectForKey:@"photoFileId"];
	}
	if (chat[@"unread_count"])
		info[@"unread"] = chat[@"unread_count"];
	if (chat[@"is_marked_as_unread"])
		info[@"markedUnread"] = @([chat[@"is_marked_as_unread"] boolValue]);

	NSString *chatType = chat[@"type"][@"@type"];
	if (chatType){
		BOOL isSupergroup = [chatType isEqualToString:@"chatTypeSupergroup"];
		BOOL isChannel = isSupergroup && [chat[@"type"][@"is_channel"] boolValue];
		info[@"isGroup"] = @(![chatType isEqualToString:@"chatTypePrivate"] &&
							 ![chatType isEqualToString:@"chatTypeSecret"]);
		info[@"isChannel"] = @(isChannel);
		info[@"isPrivate"] = @([chatType isEqualToString:@"chatTypePrivate"]);
	}

	[self mergeForumFlagFromChat:chat into:info chatId:chatId];

	NSArray *chatPositions = [chat[@"positions"] isKindOfClass:NSArray.class]
			? chat[@"positions"] : nil;
	if (chatPositions.count){
		info[@"order"] = @(TGMainListOrder(chatPositions));
		info[@"archiveOrder"] = @(TGArchiveOrder(chatPositions));
		info[@"isPinned"] = @(TGPinnedInMain(chatPositions));
	}
	if (chat[@"notification_settings"])
		info[@"isMuted"] = @([chat[@"notification_settings"][@"mute_for"] integerValue] > 0);

	// Small avatar, if the chat has one. Downloaded lazily; the id is enough
	NSNumber *photoFile = chat[@"photo"][@"small"][@"id"];
	if (photoFile)
		info[@"photoFileId"] = photoFile;
	NSString *photoKey = chat[@"photo"][@"small"][@"remote"][@"unique_id"];
	if ([photoKey isKindOfClass:NSString.class] && photoKey.length)
		info[@"photoKey"] = photoKey;
	else if (photoFile)
		[info removeObjectForKey:@"photoKey"];
	NSString *photoMini = chat[@"photo"][@"minithumbnail"][@"data"];
	if ([photoMini isKindOfClass:NSString.class] && photoMini.length)
		info[@"photoMini"] = photoMini;

	info[@"draft"] = TGDraftText(chat[@"draft_message"]);

	if (chat[@"last_read_outbox_message_id"])
		info[@"lastReadOutboxId"] = chat[@"last_read_outbox_message_id"];

	NSDictionary *last = chat[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = [self previewForLastMessage:last inChat:info];
		info[@"date"] = last[@"date"] ?: @(0);
		[self mergeOutgoingStateFromMessage:last into:info];
	}

	[self rebuildChats];
}

- (void)mergeOutgoingStateFromMessage:(NSDictionary *)last into:(NSMutableDictionary *)info {
	info[@"lastMessageId"] = last[@"id"] ?: @(0);

	BOOL hasReader = ![info[@"isSaved"] boolValue] && ![info[@"isChannel"] boolValue];
	BOOL onItsWay = [last[@"sending_state"] isKindOfClass:NSDictionary.class];
	info[@"outgoing"] = @([last[@"is_outgoing"] boolValue] && hasReader && !onItsWay);

	[self refreshOutgoingReadStateIn:info];
}

- (void)refreshOutgoingReadStateIn:(NSMutableDictionary *)info {
	long long lastId = [info[@"lastMessageId"] longLongValue];
	info[@"outgoingRead"] = @(lastId != 0 &&
							  [info[@"lastReadOutboxId"] longLongValue] >= lastId);
}

/// In a group the list shows who spoke last - "Назар: text" - which is the
/// only way to tell a busy group apart at a glance.
- (NSString *)previewForLastMessage:(NSDictionary *)last inChat:(NSDictionary *)info {
	NSString *text = TGMessagePreview(last);
	if (![info[@"isGroup"] boolValue] || [last[@"is_outgoing"] boolValue])
		return text;

	int64_t sender = [last[@"sender_id"][@"user_id"] longLongValue];
	NSString *who = [self nameForUserId:sender];
	if (!who.length){
		// not known yet - fetch, then rebuild so the row fills in
		__weak typeof(self) weakSelf = self;
		[self ensureUserName:sender completion:^{ [weakSelf rebuildChats]; }];
		return text;
	}
	return [NSString stringWithFormat:@"%@: %@", who, text];
}

- (void)applyChatUpdate:(NSDictionary *)update {
	NSNumber *chatId = update[@"chat_id"];
	if (!chatId)
		return;

	if (!self.chatsConfirmedByServer)
		self.chatsConfirmedByServer = [NSMutableSet set];
	[self.chatsConfirmedByServer addObject:chatId];

	NSMutableDictionary *info = self.chatsById[chatId];
	if (!info){
		info = [NSMutableDictionary dictionary];
		info[@"id"] = chatId;
		self.chatsById[chatId] = info;
	}

	NSString *updateType = update[@"@type"];

	if (update[@"title"])
		info[@"title"] = update[@"title"];
	if (update[@"unread_count"])
		info[@"unread"] = update[@"unread_count"];
	if (update[@"is_marked_as_unread"])
		info[@"markedUnread"] = @([update[@"is_marked_as_unread"] boolValue]);

	if (update[@"last_read_outbox_message_id"]){
		info[@"lastReadOutboxId"] = update[@"last_read_outbox_message_id"];
		[self refreshOutgoingReadStateIn:info];
	}

	if ([updateType isEqualToString:@"updateChatPhoto"]){
		NSNumber *photoFile = update[@"photo"][@"small"][@"id"];
		if (photoFile && ![info[@"isSaved"] boolValue])
			info[@"photoFileId"] = photoFile;
		else
			[info removeObjectForKey:@"photoFileId"];
	}

	if ([updateType isEqualToString:@"updateChatDraftMessage"])
		info[@"draft"] = TGDraftText(update[@"draft_message"]);

	NSDictionary *last = update[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = [self previewForLastMessage:last inChat:info];
		info[@"date"] = last[@"date"] ?: @(0);
		[self mergeOutgoingStateFromMessage:last into:info];
	} else if ([updateType isEqualToString:@"updateChatLastMessage"]){
		info[@"text"] = @"";
		info[@"date"] = @(0);
		info[@"lastMessageId"] = @(0);
		info[@"outgoing"] = @NO;
		info[@"outgoingRead"] = @NO;
	}

	if (update[@"notification_settings"])
		info[@"isMuted"] = @([update[@"notification_settings"][@"mute_for"] integerValue] > 0);
	NSArray *updatePositions = [update[@"positions"] isKindOfClass:NSArray.class]
			? update[@"positions"] : nil;
	if (updatePositions.count){
		info[@"order"] = @(TGMainListOrder(updatePositions));
		info[@"archiveOrder"] = @(TGArchiveOrder(updatePositions));
		info[@"isPinned"] = @(TGPinnedInMain(updatePositions));
	}
	NSDictionary *position = update[@"position"];
	if ([position isKindOfClass:NSDictionary.class]){
		NSString *listType = position[@"list"][@"@type"];
		if ([listType isEqualToString:@"chatListArchive"]){
			info[@"archiveOrder"] = @(TGArchiveOrder(@[position]));
		} else if ([listType isEqualToString:@"chatListMain"]){
			info[@"order"] = @(TGMainListOrder(@[position]));
			info[@"isPinned"] = @(TGPinnedInMain(@[position]));
		}
	}

	[self rebuildChats];
}

- (void)rebuildChats {
	NSArray *all = self.chatsById.allValues;

	NSComparator byOrder = ^NSComparisonResult(id a, id b){
		int64_t oa = [a[@"order"] longLongValue];
		int64_t ob = [b[@"order"] longLongValue];
		if (oa == ob) return NSOrderedSame;
		return oa > ob ? NSOrderedAscending : NSOrderedDescending;   // newest first
	};

	// A chat sits in exactly one of the two lists, told apart by which
	// position carries a non-zero order.
	NSMutableArray *main = [NSMutableArray array], *archived = [NSMutableArray array];
	for (NSDictionary *c in all){
		if ([c[@"archiveOrder"] longLongValue] > 0)
			[archived addObject:c];
		else if ([c[@"order"] longLongValue] > 0)
			[main addObject:c];
	}

	self.chats = [main sortedArrayUsingComparator:byOrder];
	self.archivedChats = [archived sortedArrayUsingComparator:
			^NSComparisonResult(id a, id b){
		int64_t oa = [a[@"archiveOrder"] longLongValue];
		int64_t ob = [b[@"archiveOrder"] longLongValue];
		if (oa == ob) return NSOrderedSame;
		return oa > ob ? NSOrderedAscending : NSOrderedDescending;
	}];

	[self scheduleChatsChanged];
}

- (void)scheduleChatsChanged {
	if (self.chatsNotifyScheduled)
		return;
	self.chatsNotifyScheduled = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		TGClient *me = weakSelf;
		if (!me)
			return;
		me.chatsNotifyScheduled = NO;
		if (me.onChatsChanged)
			me.onChatsChanged();
		if (me.onArchiveChanged)
			me.onArchiveChanged();
		[me saveCachedChatsThrottled];
	});
}

#pragma mark - chat list snapshot

static NSString *const TGChatSnapshotName = @"chatlist";
static const NSUInteger TGChatSnapshotLimit = 200;
static const NSTimeInterval TGChatSnapshotInterval = 4.0;

static NSDictionary *TGPlistSafeChat(NSDictionary *chat) {
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:chat.count];
	for (NSString *key in chat){
		id value = chat[key];
		if (![key isKindOfClass:NSString.class])
			continue;
		if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])
			out[key] = value;
	}
	return [out[@"id"] isKindOfClass:NSNumber.class] ? out : nil;
}

static NSString *const TGFolderSnapshotName = @"folders";

- (void)saveCachedFolders {
	NSMutableArray *rows = [NSMutableArray array];
	for (NSDictionary *folder in self.folders ?: @[]){
		id folderId = folder[@"id"];
		id title = folder[@"title"];
		if ([folderId isKindOfClass:NSNumber.class] && [title isKindOfClass:NSString.class])
			[rows addObject:@{@"id" : folderId, @"title" : title}];
	}
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:rows
			format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
	if (!data.length)
		return;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		[TGDiskCache writeData:data toProtectedPath:
				[TGDiskCache snapshotPathForName:TGFolderSnapshotName]];
	});
}

- (void)loadCachedFolders {
	if (self.folders.count)
		return;
	NSData *data = [NSData dataWithContentsOfFile:
			[TGDiskCache snapshotPathForName:TGFolderSnapshotName]];
	if (!data.length)
		return;
	id plist = [NSPropertyListSerialization propertyListWithData:data
														 options:NSPropertyListImmutable
														  format:NULL
														   error:NULL];
	if ([plist isKindOfClass:NSArray.class] && [(NSArray *)plist count])
		self.folders = plist;
}

- (void)loadCachedChats {
	if (self.cachedChatsLoaded || self.chatsById.count)
		return;
	self.cachedChatsLoaded = YES;
	[self loadCachedFolders];

	NSData *data = [NSData dataWithContentsOfFile:
			[TGDiskCache snapshotPathForName:TGChatSnapshotName]];
	if (!data.length)
		return;

	id plist = [NSPropertyListSerialization propertyListWithData:data
														 options:NSPropertyListImmutable
														  format:NULL
														   error:NULL];
	if (![plist isKindOfClass:NSArray.class])
		return;

	for (id entry in (NSArray *)plist){
		if (![entry isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *chat = TGPlistSafeChat(entry);
		NSNumber *chatId = chat[@"id"];
		if (!chatId || self.chatsById[chatId])
			continue;
		NSMutableDictionary *restored = [chat mutableCopy];
		[restored removeObjectForKey:@"photoFileId"];
		self.chatsById[chatId] = restored;
	}
	NSLog(@"TGClient: %lu chats restored from disk", (unsigned long)self.chatsById.count);
	[self rebuildChats];
}

- (void)saveCachedChatsThrottled {
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - self.lastChatSnapshotSave < TGChatSnapshotInterval)
		return;
	[self saveCachedChats];
}

- (void)saveCachedChats {
	if (self.authState != TGAuthStateReady)
		return;
	self.lastChatSnapshotSave = [NSDate timeIntervalSinceReferenceDate];

	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *list in @[self.chats ?: @[], self.archivedChats ?: @[]]){
		for (NSDictionary *chat in list){
			if (rows.count >= TGChatSnapshotLimit)
				break;
			NSDictionary *safe = TGPlistSafeChat(chat);
			if (safe)
				[rows addObject:safe];
		}
	}
	if (!rows.count)
		return;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		@autoreleasepool {
			NSData *data = [NSPropertyListSerialization dataWithPropertyList:rows
					format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
			if (data.length)
				[TGDiskCache writeData:data toProtectedPath:
						[TGDiskCache snapshotPathForName:TGChatSnapshotName]];
		}
	});
}

- (void)clearCachedChats {
	self.lastChatSnapshotSave = 0;
	[[NSFileManager defaultManager] removeItemAtPath:
			[TGDiskCache snapshotPathForName:TGChatSnapshotName] error:NULL];
}

- (void)dropChatsMissingFromServerList {
	if (!self.chatsConfirmedByServer.count)
		return;
	NSMutableArray *stale = [NSMutableArray array];
	for (NSNumber *chatId in self.chatsById)
		if (![self.chatsConfirmedByServer containsObject:chatId])
			[stale addObject:chatId];
	if (!stale.count)
		return;
	[self.chatsById removeObjectsForKeys:stale];
	NSLog(@"TGClient: dropped %lu chats the server no longer lists",
			(unsigned long)stale.count);
	[self rebuildChats];
}

- (void)logOut {
	[self send:@{@"@type" : @"logOut"}];
}

@end

// vim:ft=objc
