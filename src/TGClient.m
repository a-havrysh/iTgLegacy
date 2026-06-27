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
		[type isEqualToString:@"updateChatReadInbox"]){
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
	if ([type isEqualToString:@"updateUnreadChatCount"] ||
		[type isEqualToString:@"updateChatFolders"]){
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

/// Flatten a TDLib message into what the UI needs.
static NSDictionary *TGFlattenMessage(NSDictionary *m) {
	NSDictionary *content = m[@"content"];
	NSString *ctype = content[@"@type"];
	NSNumber *photoFileId = nil;   // an image to show in the bubble
	NSNumber *docFileId   = nil;   // a file to play or offer for download
	NSString *docName     = nil;
	NSString *extra       = nil;   // text the content itself carries
	NSNumber *latitude = nil, *longitude = nil;

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

	return @{
		@"id"        : m[@"id"] ?: @(0),
		@"text"      : text,
		@"kind"      : ctype ?: @"",
		@"date"      : m[@"date"] ?: @(0),
		@"outgoing"  : m[@"is_outgoing"] ?: @NO,
		@"senderId"  : m[@"sender_id"][@"user_id"] ?: @(0),
		@"photoId"   : photoFileId ?: [NSNull null],
		@"docId"     : docFileId   ?: [NSNull null],
		@"docName"   : docName     ?: @"",
		@"lat"       : latitude    ?: [NSNull null],
		@"lon"       : longitude   ?: [NSNull null],
	};
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
	[self send:@{
		@"@type"                : @"sendMessage",
		@"chat_id"              : @(chatId),
		@"input_message_content": @{
			@"@type" : @"inputMessageText",
			@"text"  : @{@"@type" : @"formattedText", @"text" : text ?: @""},
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
	if ([ctype isEqualToString:@"messagePoll"])
		return @"Poll";
	// Unknown kinds read better without the "message" prefix than raw.
	if ([ctype hasPrefix:@"message"])
		return [ctype substringFromIndex:7];
	return ctype ?: @"";
}

/// Chats are ordered by the "order" of their position in the main list. It is
/// an int64 sent as a string, so it must not be compared as a string.
static int64_t TGMainListOrder(NSArray *positions) {
	for (NSDictionary *p in positions){
		NSDictionary *list = p[@"list"];
		if ([list[@"@type"] isEqualToString:@"chatListMain"])
			return (int64_t)[p[@"order"] longLongValue];
	}
	return 0;
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
	if (chat[@"positions"])
		info[@"order"] = @(TGMainListOrder(chat[@"positions"]));

	// Small avatar, if the chat has one. Downloaded lazily; the id is enough
	// for the UI to ask for it later.
	NSNumber *photoFile = chat[@"photo"][@"small"][@"id"];
	if (photoFile)
		info[@"photoFileId"] = photoFile;

	NSDictionary *last = chat[@"last_message"];
	if ([last isKindOfClass:NSDictionary.class]){
		info[@"text"] = TGMessagePreview(last);
		info[@"date"] = last[@"date"] ?: @(0);
	}

	[self rebuildChats];
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
		info[@"text"] = TGMessagePreview(last);
		info[@"date"] = last[@"date"] ?: @(0);
	}

	if (update[@"positions"])
		info[@"order"] = @(TGMainListOrder(update[@"positions"]));
	NSDictionary *position = update[@"position"];
	if ([position isKindOfClass:NSDictionary.class])
		info[@"order"] = @(TGMainListOrder(@[position]));

	[self rebuildChats];
}

- (void)rebuildChats {
	NSArray *all = self.chatsById.allValues;
	self.chats = [all sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
		int64_t oa = [a[@"order"] longLongValue];
		int64_t ob = [b[@"order"] longLongValue];
		if (oa == ob) return NSOrderedSame;
		return oa > ob ? NSOrderedAscending : NSOrderedDescending;   // newest first
	}];

	if (self.onChatsChanged)
		self.onChatsChanged();
}

- (void)logOut {
	[self send:@{@"@type" : @"logOut"}];
}

@end

// vim:ft=objc
