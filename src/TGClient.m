#import "TGClient.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include "../libtg/api_id.h"

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
@end

@implementation TGClient

+ (instancetype)shared {
	static TGClient *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGClient alloc] init]; });
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

	// TDLib runs single-threaded on armv7 (no thread-local storage), so its
	// scheduler only advances while we are inside td_json_client_receive.
	// Keep one thread parked in it.
	[NSThread detachNewThreadSelector:@selector(receiveLoop) toTarget:self withObject:nil];

	// The single-threaded ClientManager creates its scheduler lazily, on the
	// first request - without this nothing ever runs and no update arrives.
	[self send:@{@"@type" : @"getAuthorizationState"}];

	NSLog(@"TGClient: started");
	return YES;
}

- (void)receiveLoop {
	while (self.running){
		@autoreleasepool {
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

- (void)send:(NSDictionary *)request {
	if (!self.available)
		return;

	NSError *err = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&err];
	if (!data){
		NSLog(@"TGClient: cannot encode %@: %@", request, err);
		return;
	}

	NSMutableData *z = [data mutableCopy];   // td_json_client_send wants a C string
	[z appendBytes:"\0" length:1];
	self.td_send(self.client, z.bytes);
}

#pragma mark - updates

- (void)handleUpdate:(NSDictionary *)obj {
	NSString *type = obj[@"@type"];

	if ([type isEqualToString:@"updateAuthorizationState"]){
		[self handleAuthState:obj[@"authorization_state"]];
		return;
	}
	if ([type isEqualToString:@"error"]){
		NSString *msg = obj[@"message"] ?: @"unknown error";
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

- (void)logOut {
	[self send:@{@"@type" : @"logOut"}];
}

@end

// vim:ft=objc
