#import "TGClient.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include "api_id.h"

typedef void *(*td_create_fn)(void);
typedef void  (*td_send_fn)(void *client, const char *request);
typedef const char *(*td_recv_fn)(void *client, double timeout);
typedef const char *(*td_exec_fn)(void *client, const char *request);

@interface TGClient ()
@property (nonatomic, assign) void *handle;
@property (nonatomic, assign) void *client;
@property (nonatomic, assign) td_send_fn td_send;
@property (nonatomic, assign) td_recv_fn td_recv;
@property (nonatomic, assign) TGAuthState authState;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, copy)   NSString *pendingPhoneNumber;
@property (nonatomic, strong) NSMutableDictionary *chatsById;   // id -> mutable info
@property (nonatomic, strong) NSMutableDictionary *usersById;   // id -> display name
@property (nonatomic, strong) NSMutableDictionary *userPhotosById; // id -> photo file id
@property (nonatomic, strong) NSArray *archivedChats;
@property (nonatomic, strong) NSArray *folders;
@property (nonatomic, strong) NSArray *chats;
@property (nonatomic, strong) NSMutableArray *outbox;   // JSON strings awaiting send
@property (nonatomic, strong) NSLock *outboxLock;
@property (nonatomic, assign) NSUInteger chatsAtLastLoad;
@property (nonatomic, assign) BOOL chatListComplete;
@property (nonatomic, assign) NSUInteger loadChatsAttempts;
@property (nonatomic, strong) NSDictionary *me;
@property (nonatomic, assign) TGConnectionState connectionState;
@property (nonatomic, strong) NSMutableDictionary *pendingRequests;  // @extra -> completion
@property (nonatomic, assign) NSUInteger requestSeq;
@property (nonatomic, strong) NSMutableDictionary *fileWaiters;      // fileId -> completions
@end

static NSDictionary *TGFlattenMessage(NSDictionary *m);

@implementation TGClient

+ (instancetype)shared {
	static TGClient *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		s = [[TGClient alloc] init];
		s.chatsById = [NSMutableDictionary dictionary];
		s.usersById = [NSMutableDictionary dictionary];
		s.userPhotosById = [NSMutableDictionary dictionary];
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

	self.handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);
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

	self.client = create();
	if (!self.client){
		NSLog(@"TGClient: td_json_client_create returned NULL");
		return NO;
	}

	self.available = YES;
	self.running = YES;

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

- (void)receiveLoop {
	while (self.running){
		@autoreleasepool {
			[self drainOutbox];

			const char *res = self.td_recv(self.client, 1.0);
			if (!res)
				continue;

			NSData *data = [NSData dataWithBytes:res length:strlen(res)];
			NSError *err = nil;
			NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data
															   options:0
																 error:&err];
			if (![obj isKindOfClass:NSDictionary.class]){
				NSLog(@"TGClient: bad JSON: %@", err);
				continue;
			}

			dispatch_async(dispatch_get_main_queue(), ^{
				[self handleUpdate:obj];
			});
		}
	}
}

#pragma mark - sending

// The single-threaded ClientManager requires send and receive on the SAME
// thread: sending from elsewhere while the receive loop holds the scheduler
// guard aborts on `Scheduler.cpp:126 Check !scheduler_->has_guard_ failed`.
// So callers only enqueue here, and the receive thread does the sending.
- (void)send:(NSDictionary *)request {
	NSError *err = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&err];
	if (!data){
		NSLog(@"TGClient: cannot encode %@: %@", request, err);
		return;
	}

	NSMutableData *z = [data mutableCopy];   // td_json_client_send wants a C string
	[z appendBytes:"\0" length:1];

	[self.outboxLock lock];
	[self.outbox addObject:z];
	[self.outboxLock unlock];
}

/// Runs on the receive thread only.
- (void)drainOutbox {
	if (!self.available)
		return;

	NSArray *pending;
	[self.outboxLock lock];
	pending = [self.outbox copy];
	[self.outbox removeAllObjects];
	[self.outboxLock unlock];

	for (NSData *d in pending)
		self.td_send(self.client, d.bytes);
}

- (void)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
	if (!completion){
		[self send:request];
		return;
	}
	NSString *extra = [NSString stringWithFormat:@"r%lu", (unsigned long)(++self.requestSeq)];
	self.pendingRequests[extra] = [completion copy];

	NSMutableDictionary *withExtra = [request mutableCopy];
	withExtra[@"@extra"] = extra;
	[self send:withExtra];
}

#pragma mark - updates

- (void)handleUpdate:(NSDictionary *)obj {
	// A reply to one of our requests: route it and stop.
	NSString *extra = obj[@"@extra"];
	if ([extra isKindOfClass:NSString.class]){
		void (^completion)(NSDictionary *) = self.pendingRequests[extra];
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

	if ([type isEqualToString:@"updateAuthorizationState"]){
		[self handleAuthState:obj[@"authorization_state"]];
		return;
	}
	// Answer to getMe. updateUser also carries our own record, but the direct
	// reply is the one that always has the phone number.
	if ([type isEqualToString:@"user"] && obj[@"phone_number"]){
		self.me = @{
			@"id"         : obj[@"id"] ?: @(0),
			@"first_name" : obj[@"first_name"] ?: @"",
			@"username"   : obj[@"usernames"][@"active_usernames"][0] ?: (obj[@"username"] ?: @""),
			@"phone"      : obj[@"phone_number"] ?: @"",
		};
		NSLog(@"TGClient: signed in as +%@", self.me[@"phone"]);
		return;
	}
	if ([type isEqualToString:@"updateUser"]){
		NSDictionary *u = obj[@"user"];
		NSString *name = [[NSString stringWithFormat:@"%@ %@",
				u[@"first_name"] ?: @"", u[@"last_name"] ?: @""]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!name.length)
			name = u[@"usernames"][@"active_usernames"][0] ?: @"";
		if (u[@"id"] && name.length)
			self.usersById[u[@"id"]] = name;
		[self cacheProfilePhoto:u];
		return;
	}

	// Live message updates - without these a chat only refreshes when reopened.
	if ([type isEqualToString:@"updateNewMessage"]){
		NSDictionary *m = obj[@"message"];
		if (self.onMessage && m)
			self.onMessage([m[@"chat_id"] longLongValue], TGFlattenMessage(m), 0);
		return;
	}
	if ([type isEqualToString:@"updateMessageContent"]){
		// Content changed in place (a photo finished uploading, a text edited).
		if (self.onMessage)
			self.onMessage([obj[@"chat_id"] longLongValue], nil, 0);
		return;
	}
	if ([type isEqualToString:@"updateDeleteMessages"]){
		if ([obj[@"is_permanent"] boolValue] && self.onMessage){
			int64_t chatId = [obj[@"chat_id"] longLongValue];
			for (NSNumber *mid in obj[@"message_ids"])
				self.onMessage(chatId, nil, [mid longLongValue]);
		}
		return;
	}
	if ([type isEqualToString:@"updateNewChat"]){
		[self mergeChat:obj[@"chat"]];
		return;
	}
	if ([type isEqualToString:@"updateChatLastMessage"] ||
		[type isEqualToString:@"updateChatPosition"] ||
		[type isEqualToString:@"updateChatTitle"] ||
		[type isEqualToString:@"updateChatReadInbox"] ||
		[type isEqualToString:@"updateChatNotificationSettings"]){
		[self applyChatUpdate:obj];
		return;
	}
	if ([type isEqualToString:@"updateConnectionState"]){
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
		if (self.onConnectionState)
			self.onConnectionState(state, text);
		return;
	}
	if ([type isEqualToString:@"updateFile"]){
		// Big files take long enough on a 4S that silence looks like a hang.
		NSDictionary *file = obj[@"file"];
		NSDictionary *local = file[@"local"];
		if (self.onFileProgress && [local[@"is_downloading_active"] boolValue]){
			double expected = [file[@"expected_size"] doubleValue];
			double got = [local[@"downloaded_size"] doubleValue];
			if (expected > 0)
				self.onFileProgress([file[@"id"] integerValue], (float)(got / expected));
		}
		return;
	}

	if ([type isEqualToString:@"updateChatAction"]){
		// TDLib names the action; the client turns it into the phrase every
		// other client shows.
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
		if (self.onChatAction)
			self.onChatAction([obj[@"chat_id"] longLongValue], phrase);
		return;
	}

	if ([type isEqualToString:@"updateChatFolders"]){
		NSMutableArray *out = [NSMutableArray array];
		for (NSDictionary *f in obj[@"chat_folders"])
			[out addObject:@{@"id"    : f[@"id"] ?: @(0),
							 @"title" : f[@"title"][@"text"] ?: f[@"name"][@"text"] ?: f[@"title"] ?: @""}];
		self.folders = out;
		NSLog(@"TGClient: %lu folders", (unsigned long)out.count);
		return;
	}
	if ([type isEqualToString:@"updateUnreadChatCount"]){
		NSLog(@"TGClient: %@ total=%@ list=%@", type, obj[@"total_count"],
				obj[@"chat_list"][@"@type"]);
		return;
	}
	if ([type isEqualToString:@"error"]){
		NSString *msg = obj[@"message"] ?: @"unknown error";
		NSLog(@"TGClient: ERROR code=%@ msg=%@", obj[@"code"], msg);
		if ([obj[@"code"] intValue] == 404){
			// loadChats answers 404 when the whole list is loaded
			self.chatListComplete = YES;
			NSLog(@"TGClient: chat list complete (%lu)",
					(unsigned long)self.chatsById.count);
			return;
		}
		NSLog(@"TGClient: error: %@", obj);
		if (self.onError)
			self.onError(msg);
		return;
	}
}

- (void)handleAuthState:(NSDictionary *)state {
	NSString *type = state[@"@type"];
	NSLog(@"TGClient: auth state %@", type);

	TGAuthState s = TGAuthStateUnknown;

	if ([type isEqualToString:@"authorizationStateWaitTdlibParameters"]){
		[self sendTdlibParameters];
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
	} else {
		return;                       // encryption-key states etc.
	}

	self.authState = s;
	if (s == TGAuthStateReady){
		[self loadChats];
		[self send:@{@"@type" : @"getMe"}];
	}
	if (s == TGAuthStateWaitPhoneNumber)
		[self flushPendingPhoneNumber];
	if (self.onAuthState)
		self.onAuthState(s);
}

- (void)sendTdlibParameters {
	NSString *docs = [NSSearchPathForDirectoriesInDomains(
			NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *db = [docs stringByAppendingPathComponent:@"tdlib"];

	int SETUP_API_ID(apiId)
	char * SETUP_API_HASH(apiHash)

	UIDevice *dev = [UIDevice currentDevice];

	[self send:@{
		@"@type"                  : @"setTdlibParameters",
		@"database_directory"     : db,
		@"files_directory"        : [db stringByAppendingPathComponent:@"files"],
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

/// Flatten a TDLib message into what the UI needs.
static NSDictionary *TGFlattenMessage(NSDictionary *m) {
	NSDictionary *content = m[@"content"];
	NSString *ctype = content[@"@type"];
	NSNumber *photoFileId = nil;   // an image to show in the bubble
	NSNumber *docFileId   = nil;   // a file to play or offer for download
	NSString *docName     = nil;
	NSString *extra       = nil;   // text the content itself carries
	NSNumber *latitude = nil, *longitude = nil;
	BOOL isService = NO;

	if ([ctype isEqualToString:@"messagePhoto"]){
		// sizes run small to large; take the largest present
		NSArray *sizes = content[@"photo"][@"sizes"];
		if (sizes.count)
			photoFileId = [sizes lastObject][@"photo"][@"id"];

	} else if ([ctype isEqualToString:@"messageVideo"]){
		photoFileId = content[@"video"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"video"][@"video"][@"id"];
		docName     = content[@"video"][@"file_name"];

	} else if ([ctype isEqualToString:@"messageVideoNote"]){
		photoFileId = content[@"video_note"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"video_note"][@"video"][@"id"];

	} else if ([ctype isEqualToString:@"messageAnimation"]){
		// Telegram GIFs are MP4, so they play like any video.
		photoFileId = content[@"animation"][@"thumbnail"][@"file"][@"id"];
		docFileId   = content[@"animation"][@"animation"][@"id"];
		docName     = content[@"animation"][@"file_name"];

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
		NSNumber *dur = content[@"voice_note"][@"duration"];
		extra = [NSString stringWithFormat:@"Voice message  %ld:%02ld",
				(long)(dur.integerValue / 60), (long)(dur.integerValue % 60)];

	} else if ([ctype isEqualToString:@"messageAudio"]){
		docFileId = content[@"audio"][@"audio"][@"id"];
		docName   = content[@"audio"][@"file_name"];
		NSString *title = content[@"audio"][@"title"];
		extra = title.length ? title : (docName ?: @"Audio");

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
		NSMutableArray *names = [NSMutableArray array];
		for (NSNumber *uid in content[@"member_user_ids"])
			[names addObject:[[TGClient shared] nameForUserId:uid.longLongValue] ?: @"someone"];
		extra = [NSString stringWithFormat:@"%@ joined the group",
				[names componentsJoinedByString:@", "]];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatDeleteMember"]){
		NSString *who = [[TGClient shared] nameForUserId:
				[content[@"user_id"] longLongValue]] ?: @"someone";
		extra = [NSString stringWithFormat:@"%@ left the group", who];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatJoinByLink"] ||
			   [ctype isEqualToString:@"messageChatJoinByRequest"]){
		extra = @"joined the group via invite link";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatChangeTitle"]){
		extra = [NSString stringWithFormat:@"Group renamed to \"%@\"",
				content[@"title"] ?: @""];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatChangePhoto"]){
		extra = @"Group photo changed";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatDeletePhoto"]){
		extra = @"Group photo removed";
		isService = YES;

	} else if ([ctype isEqualToString:@"messagePinMessage"]){
		extra = @"pinned a message";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageBasicGroupChatCreate"] ||
			   [ctype isEqualToString:@"messageSupergroupChatCreate"]){
		extra = [NSString stringWithFormat:@"Group \"%@\" created",
				content[@"title"] ?: @""];
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatUpgradeTo"] ||
			   [ctype isEqualToString:@"messageChatUpgradeFrom"]){
		extra = @"Group upgraded to a supergroup";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageChatSetTheme"]){
		extra = @"Chat theme changed";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageScreenshotTaken"]){
		extra = @"Screenshot taken";
		isService = YES;

	} else if ([ctype isEqualToString:@"messageCall"]){
		NSNumber *dur = content[@"duration"];
		extra = dur.integerValue > 0
			? [NSString stringWithFormat:@"Call, %ld:%02ld",
					(long)(dur.integerValue / 60), (long)(dur.integerValue % 60)]
			: @"Call";
		isService = YES;

	} else if ([ctype isEqualToString:@"messagePoll"]){
		NSDictionary *poll = content[@"poll"];
		NSMutableString *lines = [NSMutableString stringWithFormat:@"%@",
				poll[@"question"][@"text"] ?: poll[@"question"] ?: @"Poll"];
		for (NSDictionary *opt in poll[@"options"])
			[lines appendFormat:@"\n  %@  %@%%",
					opt[@"text"][@"text"] ?: opt[@"text"] ?: @"",
					opt[@"vote_percentage"] ?: @0];
		extra = lines;

	} else if ([ctype isEqualToString:@"messageDice"]){
		extra = [NSString stringWithFormat:@"%@  %@",
				content[@"emoji"] ?: @"Dice", content[@"value"] ?: @""];

	} else if ([ctype isEqualToString:@"messageGame"]){
		extra = [NSString stringWithFormat:@"Game: %@",
				content[@"game"][@"title"] ?: @""];

	} else if ([ctype isEqualToString:@"messageUnsupported"]){
		extra = @"Message not supported on this client";
		isService = YES;

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
	}

	// A caption wins; then whatever the content itself says; and for a plain
	// picture, nothing at all - the image speaks for itself.
	NSString *caption = content[@"caption"][@"text"];
	NSString *text;
	if (caption.length)      text = caption;
	else if (extra.length)   text = extra;
	else if (photoFileId)    text = @"";
	else                     text = TGMessagePreview(m);

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
	NSDictionary *origin = m[@"forward_info"][@"origin"];
	NSString *originType = origin[@"@type"];
	if ([originType isEqualToString:@"messageOriginUser"])
		forwardFrom = [[TGClient shared] nameForUserId:
				[origin[@"sender_user_id"] longLongValue]] ?: @"a user";
	else if ([originType isEqualToString:@"messageOriginHiddenUser"])
		forwardFrom = origin[@"sender_name"];
	else if ([originType isEqualToString:@"messageOriginChannel"]){
		NSString *signature = origin[@"author_signature"];
		forwardFrom = signature.length ? signature : @"a channel";
	}
	else if ([originType isEqualToString:@"messageOriginChat"])
		forwardFrom = origin[@"author_signature"] ?: @"a chat";

	return @{
		@"id"        : m[@"id"] ?: @(0),
		@"text"      : text,
		@"replyId"   : replyId    ?: [NSNull null],
		@"replyText" : replyText  ?: @"",
		@"forward"   : forwardFrom ?: @"",
		@"edited"    : @([m[@"edit_date"] doubleValue] > 0),
		@"kind"      : ctype ?: @"",
		@"date"      : m[@"date"] ?: @(0),
		@"outgoing"  : m[@"is_outgoing"] ?: @NO,
		@"photoId"   : photoFileId ?: [NSNull null],
		@"docId"     : docFileId   ?: [NSNull null],
		@"docName"   : docName     ?: @"",
		@"service"   : @(isService),
		// Several photos sent together share an album id; the chat draws them
		// as one block rather than as unrelated messages.
		@"albumId"   : m[@"media_album_id"] ?: @"",
		// "\U0001F44D 3" per reaction, joined - enough to show under a bubble.
		@"reactions" : TGReactionSummary(m) ?: @"",
		// Options of a poll, so tapping one can vote.
		@"pollOptions" : m[@"content"][@"poll"][@"options"] ?: @[],
		@"senderId"  : m[@"sender_id"][@"user_id"] ?: @(0),
		@"lat"       : latitude    ?: [NSNull null],
		@"lon"       : longitude   ?: [NSNull null],
	};
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
	NSMutableArray *collected = [NSMutableArray array];
	[self fetchHistoryChunkForChat:chatId
					 fromMessageId:0
							 limit:limit
						 collected:collected
						completion:completion];
}

- (void)fetchHistoryChunkForChat:(int64_t)chatId
                   fromMessageId:(int64_t)fromMessageId
                           limit:(NSInteger)limit
                       collected:(NSMutableArray *)collected
                      completion:(void (^)(NSArray *))completion {
	__weak typeof(self) weakSelf = self;
	[self request:@{
		@"@type"           : @"getChatHistory",
		@"chat_id"         : @(chatId),
		@"from_message_id" : @(fromMessageId),
		@"offset"          : @(0),
		@"limit"           : @(limit),
		@"only_local"      : @NO,
	} completion:^(NSDictionary *result){
		TGClient *me = weakSelf;
		NSArray *msgs = result[@"messages"];

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

		[me fetchHistoryChunkForChat:chatId
					   fromMessageId:oldest
							   limit:limit - collected.count
						   collected:collected
						  completion:completion];
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
			@"sticker" : @{@"@type" : @"inputFileId", @"id" : @(fileId)},
		},
	}];
}

- (void)sendVoiceAtPath:(NSString *)path duration:(NSInteger)seconds
                 toChat:(int64_t)chatId thread:(int64_t)threadId {
	if (!path.length)
		return;
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"message_thread_id"    : @(threadId),
		@"input_message_content": @{
			@"@type"      : @"inputMessageVoiceNote",
			@"voice_note" : @{@"@type" : @"inputFileLocal", @"path" : path},
			@"duration"   : @(seconds),
		},
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
			@"video" : @{@"@type" : @"inputFileLocal", @"path" : path},
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
			@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
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
					[users addObject:@{
						@"id"         : u[@"id"] ?: @(0),
						@"first_name" : u[@"first_name"] ?: @"",
						@"last_name"  : u[@"last_name"] ?: @"",
						@"phone"      : u[@"phone_number"] ?: @"",
						@"username"   : u[@"usernames"][@"active_usernames"][0] ?: @"",
					}];
				}
				if (--left == 0 && completion)
					completion(users);
			}];
		}
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
			@"username"   : u[@"usernames"][@"active_usernames"][0] ?: @"",
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
			completion([full[@"block_list"] isKindOfClass:NSDictionary.class]);
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
	[self request:@{@"@type" : @"getPremiumState"} completion:^(NSDictionary *state){
		NSDictionary *me = self.me;
		if (![me[@"is_premium"] boolValue]){
			if (completion) completion(nil);
			return;
		}
		// The state carries what is active; a date is the useful part of it.
		NSNumber *until = state[@"state"][@"expiration_date"] ?: state[@"expiration_date"];
		if (!until.doubleValue){
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
					[NSDate dateWithTimeIntervalSince1970:until.doubleValue]]]);
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
	[self send:@{
		@"@type"     : @"loadChats",
		@"chat_list" : @{@"@type" : @"chatListMain"},
		@"limit"     : @(50),
	}];
	[self send:@{
		@"@type"     : @"loadChats",
		@"chat_list" : @{@"@type" : @"chatListArchive"},
		@"limit"     : @(50),
	}];

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
	if ([ctype isEqualToString:@"messageDocument"])
		return @"Document";
	if ([ctype isEqualToString:@"messageAudio"])
		return @"Audio";
	if ([ctype isEqualToString:@"messageAnimation"])
		return @"GIF";
	if ([ctype isEqualToString:@"messageVideoNote"])
		return @"Video message";
	if ([ctype isEqualToString:@"messageAnimatedEmoji"])
		return content[@"emoji"] ?: @"Emoji";
	if ([ctype isEqualToString:@"messageContact"])
		return @"Contact";
	if ([ctype isEqualToString:@"messageVenue"])
		return @"Venue";
	if ([ctype isEqualToString:@"messageLocation"])
		return @"Location";
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
	// Unknown kinds read better without the "message" prefix than raw.
	if ([ctype hasPrefix:@"message"])
		return [ctype substringFromIndex:7];
	return ctype ?: @"";
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
		NSDictionary *status = user[@"status"];
		NSString *kind = status[@"@type"];
		NSString *text = nil;

		if ([kind isEqualToString:@"userStatusOnline"]){
			text = @"online";
		} else if ([kind isEqualToString:@"userStatusRecently"]){
			text = @"last seen recently";
		} else if ([kind isEqualToString:@"userStatusLastWeek"]){
			text = @"last seen within a week";
		} else if ([kind isEqualToString:@"userStatusLastMonth"]){
			text = @"last seen within a month";
		} else if ([kind isEqualToString:@"userStatusOffline"]){
			NSTimeInterval was = [status[@"was_online"] doubleValue];
			static NSDateFormatter *fmt = nil;
			if (!fmt){
				fmt = [[NSDateFormatter alloc] init];
				[fmt setDateFormat:@"HH:mm"];
			}
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:was];
			BOOL today = [[NSCalendar currentCalendar]
					components:NSDayCalendarUnit fromDate:date].day ==
						 [[NSCalendar currentCalendar]
					components:NSDayCalendarUnit fromDate:[NSDate date]].day;
			text = today
				? [NSString stringWithFormat:@"last seen at %@", [fmt stringFromDate:date]]
				: @"last seen a long time ago";
		}
		if (completion) completion(text);
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
				name = u[@"usernames"][@"active_usernames"][0] ?: @"";
			if (name.length)
				me.usersById[@(userId)] = name;
			[me cacheProfilePhoto:u];
		}
		if (completion) completion();
	}];
}

- (void)mergeChat:(NSDictionary *)chat {
	if (![chat isKindOfClass:NSDictionary.class])
		return;

	NSNumber *chatId = chat[@"id"];
	if (!chatId)
		return;

	NSMutableDictionary *info = self.chatsById[chatId];
	if (!info){
		info = [NSMutableDictionary dictionary];
		self.chatsById[chatId] = info;
	}

	info[@"id"] = chatId;
	if (chat[@"title"])
		info[@"title"] = chat[@"title"];
	if (chat[@"unread_count"])
		info[@"unread"] = chat[@"unread_count"];

	NSString *chatType = chat[@"type"][@"@type"];
	if (chatType)
		info[@"isGroup"] = @(![chatType isEqualToString:@"chatTypePrivate"] &&
							 ![chatType isEqualToString:@"chatTypeSecret"]);

	// A forum keeps several threads in one chat, so it opens on a topic list
	// rather than a merged stream.
	if (chat[@"is_forum"])
		info[@"isForum"] = chat[@"is_forum"];
	if (chat[@"positions"]){
		info[@"order"] = @(TGMainListOrder(chat[@"positions"]));
		info[@"archiveOrder"] = @(TGArchiveOrder(chat[@"positions"]));
		info[@"isPinned"] = @(TGPinnedInMain(chat[@"positions"]));
	}
	if (chat[@"notification_settings"])
		info[@"isMuted"] = @([chat[@"notification_settings"][@"mute_for"] integerValue] > 0);

	// Small avatar, if the chat has one. Downloaded lazily; the id is enough
	// for the UI to ask for it later.
	NSNumber *photoFile = chat[@"photo"][@"small"][@"id"];
	if (photoFile)
		info[@"photoFileId"] = photoFile;

	NSString *draft = chat[@"draft_message"][@"input_message_text"][@"text"][@"text"];
	info[@"draft"] = draft ?: @"";

	NSDictionary *last = chat[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = [self previewForLastMessage:last inChat:info];
		info[@"date"] = last[@"date"] ?: @(0);
	}

	[self rebuildChats];
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

	NSMutableDictionary *info = self.chatsById[chatId];
	if (!info){
		info = [NSMutableDictionary dictionary];
		info[@"id"] = chatId;
		self.chatsById[chatId] = info;
	}

	if (update[@"title"])
		info[@"title"] = update[@"title"];
	if (update[@"unread_count"])
		info[@"unread"] = update[@"unread_count"];

	NSDictionary *last = update[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = [self previewForLastMessage:last inChat:info];
		info[@"date"] = last[@"date"] ?: @(0);
	}

	if (update[@"notification_settings"])
		info[@"isMuted"] = @([update[@"notification_settings"][@"mute_for"] integerValue] > 0);
	if (update[@"positions"]){
		info[@"order"] = @(TGMainListOrder(update[@"positions"]));
		info[@"archiveOrder"] = @(TGArchiveOrder(update[@"positions"]));
		info[@"isPinned"] = @(TGPinnedInMain(update[@"positions"]));
	}
	NSDictionary *position = update[@"position"];
	if ([position isKindOfClass:NSDictionary.class]){
		NSString *listType = position[@"list"][@"@type"];
		if ([listType isEqualToString:@"chatListArchive"])
			info[@"archiveOrder"] = @(TGArchiveOrder(@[position]));
		else
			info[@"order"] = @(TGMainListOrder(@[position]));
			info[@"isPinned"] = @(TGPinnedInMain(@[position]));
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

	if (self.onChatsChanged)
		self.onChatsChanged();
	if (self.onArchiveChanged)
		self.onArchiveChanged();
}

- (void)logOut {
	[self send:@{@"@type" : @"logOut"}];
}

@end

// vim:ft=objc
