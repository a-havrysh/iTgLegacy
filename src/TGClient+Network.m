#import "TGClient+Private.h"
#import "TGClient+Network.h"

@interface TGClient (NetworkInternal)
- (void)tgNetworkAutoDownloadPresetsWithCompletion:(void (^)(NSDictionary *presets))completion;
- (void)tgNetworkApplyAutoDownloadSettings:(NSDictionary *)settings
                        toEveryNetworkKind:(void (^)(BOOL ok))completion;
- (void)tgNetworkConnectionStateTick:(NSTimer *)timer;
@end

NSString *const TGProxyListDidChangeNotification = @"TGProxyListDidChangeNotification";
NSString *const TGConnectionStateDidChangeNotification = @"TGConnectionStateDidChangeNotification";
NSString *const TGConnectionStateKey = @"state";
NSString *const TGConnectionStateTitleKey = @"title";

static NSInteger TGNetStateObservers = 0;
static NSTimer *TGNetStateTimer = nil;
static TGConnectionState TGNetLastState = TGConnectionStateUnknown;
static BOOL TGNetHasLastState = NO;

static void TGNetPostProxyListChanged(id client) {
	[[NSNotificationCenter defaultCenter] postNotificationName:TGProxyListDidChangeNotification
														object:client];
}

static BOOL TGNetIsError(NSDictionary *result) {
	if (![result isKindOfClass:[NSDictionary class]])
		return YES;
	id type = [result objectForKey:@"@type"];
	if (![type isKindOfClass:[NSString class]])
		return YES;
	return [type isEqualToString:@"error"];
}

static NSString *TGNetString(id value) {
	if (![value isKindOfClass:[NSString class]])
		return @"";
	return value;
}

static NSNumber *TGNetNumber(id value) {
	if (![value isKindOfClass:[NSNumber class]])
		return @0;
	return value;
}

static NSNumber *TGNetBool(id value) {
	if (![value isKindOfClass:[NSNumber class]])
		return @NO;
	return [value boolValue] ? @YES : @NO;
}

static NSArray *TGNetArray(id value) {
	if (![value isKindOfClass:[NSArray class]])
		return [NSArray array];
	return value;
}

static NSDictionary *TGNetDict(id value) {
	if (![value isKindOfClass:[NSDictionary class]])
		return nil;
	return value;
}

static NSString *TGNetNetworkTypeName(NSString *kind) {
	NSString *name = [TGNetString(kind) lowercaseString];
	if ([name isEqualToString:@"none"])
		return @"networkTypeNone";
	if ([name isEqualToString:@"mobile"])
		return @"networkTypeMobile";
	if ([name isEqualToString:@"mobileroaming"] || [name isEqualToString:@"roaming"])
		return @"networkTypeMobileRoaming";
	if ([name isEqualToString:@"wifi"])
		return @"networkTypeWiFi";
	return @"networkTypeOther";
}

static NSDictionary *TGNetProxyTypeObject(NSDictionary *proxy) {
	NSString *kind = [TGNetString(proxy[@"type"]) lowercaseString];
	if ([kind isEqualToString:@"mtproto"]){
		return @{@"@type"  : @"proxyTypeMtproto",
				 @"secret" : TGNetString(proxy[@"secret"])};
	}
	if ([kind isEqualToString:@"http"]){
		return @{@"@type"     : @"proxyTypeHttp",
				 @"username"  : TGNetString(proxy[@"username"]),
				 @"password"  : TGNetString(proxy[@"password"]),
				 @"http_only" : TGNetBool(proxy[@"httpOnly"])};
	}
	return @{@"@type"    : @"proxyTypeSocks5",
			 @"username" : TGNetString(proxy[@"username"]),
			 @"password" : TGNetString(proxy[@"password"])};
}

static NSDictionary *TGNetProxyObject(NSDictionary *proxy) {
	if (![proxy isKindOfClass:[NSDictionary class]])
		return nil;
	return @{@"@type"  : @"proxy",
			 @"server" : TGNetString(proxy[@"server"]),
			 @"port"   : TGNetNumber(proxy[@"port"]),
			 @"type"   : TGNetProxyTypeObject(proxy)};
}

static NSDictionary *TGNetProxyDict(NSDictionary *proxy, NSDictionary *added) {
	NSDictionary *inner = TGNetDict(proxy);
	if (!inner)
		return nil;
	NSDictionary *type = TGNetDict(inner[@"type"]);
	NSString *typeName = TGNetString(type[@"@type"]);
	NSString *kind = @"socks5";
	if ([typeName isEqualToString:@"proxyTypeHttp"])
		kind = @"http";
	else if ([typeName isEqualToString:@"proxyTypeMtproto"])
		kind = @"mtproto";

	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	[out setObject:TGNetString(inner[@"server"]) forKey:@"server"];
	[out setObject:TGNetNumber(inner[@"port"]) forKey:@"port"];
	[out setObject:kind forKey:@"type"];
	[out setObject:TGNetString(type[@"username"]) forKey:@"username"];
	[out setObject:TGNetString(type[@"password"]) forKey:@"password"];
	[out setObject:TGNetString(type[@"secret"]) forKey:@"secret"];
	[out setObject:TGNetBool(type[@"http_only"]) forKey:@"httpOnly"];
	if (added){
		[out setObject:TGNetNumber(added[@"id"]) forKey:@"id"];
		[out setObject:TGNetBool(added[@"is_enabled"]) forKey:@"isEnabled"];
		[out setObject:TGNetString(added[@"comment"]) forKey:@"comment"];
		[out setObject:TGNetNumber(added[@"last_used_date"]) forKey:@"lastUsedDate"];
	}
	return out;
}

static NSDictionary *TGNetAddedProxyDict(NSDictionary *added) {
	NSDictionary *safe = TGNetDict(added);
	if (!safe)
		return nil;
	return TGNetProxyDict(TGNetDict(safe[@"proxy"]), safe);
}

static NSDictionary *TGNetSettingsDict(NSDictionary *settings) {
	NSDictionary *safe = TGNetDict(settings);
	if (!safe)
		return nil;
	return @{
		@"enabled"             : TGNetBool(safe[@"is_auto_download_enabled"]),
		@"maxPhotoSize"        : TGNetNumber(safe[@"max_photo_file_size"]),
		@"maxVideoSize"        : TGNetNumber(safe[@"max_video_file_size"]),
		@"maxOtherSize"        : TGNetNumber(safe[@"max_other_file_size"]),
		@"videoUploadBitrate"  : TGNetNumber(safe[@"video_upload_bitrate"]),
		@"preloadLargeVideos"  : TGNetBool(safe[@"preload_large_videos"]),
		@"preloadNextAudio"    : TGNetBool(safe[@"preload_next_audio"]),
		@"preloadStories"      : TGNetBool(safe[@"preload_stories"]),
		@"useLessDataForCalls" : TGNetBool(safe[@"use_less_data_for_calls"]),
	};
}

static NSDictionary *TGNetSettingsObject(NSDictionary *settings) {
	NSDictionary *safe = TGNetDict(settings);
	if (!safe)
		safe = [NSDictionary dictionary];
	return @{
		@"@type"                    : @"autoDownloadSettings",
		@"is_auto_download_enabled" : TGNetBool(safe[@"enabled"]),
		@"max_photo_file_size"      : TGNetNumber(safe[@"maxPhotoSize"]),
		@"max_video_file_size"      : TGNetNumber(safe[@"maxVideoSize"]),
		@"max_other_file_size"      : TGNetNumber(safe[@"maxOtherSize"]),
		@"video_upload_bitrate"     : TGNetNumber(safe[@"videoUploadBitrate"]),
		@"preload_large_videos"     : TGNetBool(safe[@"preloadLargeVideos"]),
		@"preload_next_audio"       : TGNetBool(safe[@"preloadNextAudio"]),
		@"preload_stories"          : TGNetBool(safe[@"preloadStories"]),
		@"use_less_data_for_calls"  : TGNetBool(safe[@"useLessDataForCalls"]),
	};
}

@implementation TGClient (Network)

#pragma mark - proxy list

- (void)proxiesWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getProxies"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSMutableArray *out = [NSMutableArray array];
		if (!TGNetIsError(result)){
			for (id item in TGNetArray(result[@"proxies"])){
				NSDictionary *proxy = TGNetAddedProxyDict(TGNetDict(item));
				if (proxy)
					[out addObject:proxy];
			}
		}
		completion(out);
	}];
}

- (void)addProxy:(NSDictionary *)proxy
          enable:(BOOL)enable
      completion:(void (^)(NSDictionary *))completion {
	NSDictionary *object = TGNetProxyObject(proxy);
	if (!object){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type"   : @"addProxy",
					@"proxy"   : object,
					@"enable"  : enable ? @YES : @NO,
					@"comment" : TGNetString(proxy[@"comment"])}
	   completion:^(NSDictionary *result){
		if (!TGNetIsError(result))
			TGNetPostProxyListChanged(self);
		if (!completion)
			return;
		if (TGNetIsError(result)){
			completion(nil);
			return;
		}
		completion(TGNetAddedProxyDict(result));
	}];
}

- (void)editProxy:(NSInteger)proxyId
               to:(NSDictionary *)proxy
           enable:(BOOL)enable
       completion:(void (^)(NSDictionary *))completion {
	NSDictionary *object = TGNetProxyObject(proxy);
	if (!object){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type"    : @"editProxy",
					@"proxy_id" : @(proxyId),
					@"proxy"    : object,
					@"enable"   : enable ? @YES : @NO,
					@"comment"  : TGNetString(proxy[@"comment"])}
	   completion:^(NSDictionary *result){
		if (!TGNetIsError(result))
			TGNetPostProxyListChanged(self);
		if (!completion)
			return;
		if (TGNetIsError(result)){
			completion(nil);
			return;
		}
		completion(TGNetAddedProxyDict(result));
	}];
}

- (void)enableProxy:(NSInteger)proxyId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"enableProxy", @"proxy_id" : @(proxyId)}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGNetIsError(result);
		if (ok)
			TGNetPostProxyListChanged(self);
		if (completion)
			completion(ok);
	}];
}

- (void)disableProxyWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"disableProxy"} completion:^(NSDictionary *result){
		BOOL ok = !TGNetIsError(result);
		if (ok)
			TGNetPostProxyListChanged(self);
		if (completion)
			completion(ok);
	}];
}

- (void)removeProxy:(NSInteger)proxyId completion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"removeProxy", @"proxy_id" : @(proxyId)}
	   completion:^(NSDictionary *result){
		BOOL ok = !TGNetIsError(result);
		if (ok)
			TGNetPostProxyListChanged(self);
		if (completion)
			completion(ok);
	}];
}

- (void)activeProxyWithCompletion:(void (^)(NSDictionary *))completion {
	[self proxiesWithCompletion:^(NSArray *proxies){
		if (!completion)
			return;
		for (id item in proxies){
			NSDictionary *proxy = TGNetDict(item);
			if (proxy && [TGNetBool(proxy[@"isEnabled"]) boolValue]){
				completion(proxy);
				return;
			}
		}
		completion(nil);
	}];
}

- (void)activeProxyIdWithCompletion:(void (^)(NSInteger))completion {
	[self activeProxyWithCompletion:^(NSDictionary *proxy){
		if (!completion)
			return;
		if (!proxy){
			completion(-1);
			return;
		}
		completion([TGNetNumber(proxy[@"id"]) integerValue]);
	}];
}

- (void)setProxy:(NSInteger)proxyId
         enabled:(BOOL)enabled
      completion:(void (^)(BOOL))completion {
	if (enabled)
		[self enableProxy:proxyId completion:completion];
	else
		[self disableProxyWithCompletion:completion];
}

#pragma mark - proxy checks

- (void)pingProxy:(NSDictionary *)proxy
       completion:(void (^)(double))completion {
	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	[request setObject:@"pingProxy" forKey:@"@type"];
	NSDictionary *object = TGNetProxyObject(proxy);
	if (object)
		[request setObject:object forKey:@"proxy"];
	[self request:request completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNetIsError(result)){
			completion(-1.0);
			return;
		}
		completion([TGNetNumber(result[@"seconds"]) doubleValue]);
	}];
}

- (void)pingAllProxiesWithCompletion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self proxiesWithCompletion:^(NSArray *proxies){
		NSMutableDictionary *results = [NSMutableDictionary dictionary];
		if (!proxies.count){
			if (completion)
				completion(results);
			return;
		}
		__block NSUInteger remaining = proxies.count;
		for (NSDictionary *proxy in proxies){
			NSNumber *proxyId = TGNetNumber(proxy[@"id"]);
			[weakSelf pingProxy:proxy completion:^(double seconds){
				[results setObject:[NSNumber numberWithDouble:seconds] forKey:proxyId];
				remaining--;
				if (remaining == 0 && completion)
					completion(results);
			}];
		}
	}];
}

- (void)testProxy:(NSDictionary *)proxy
             dcId:(NSInteger)dcId
          timeout:(double)timeout
       completion:(void (^)(BOOL))completion {
	NSDictionary *object = TGNetProxyObject(proxy);
	if (!object){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{@"@type"   : @"testProxy",
					@"proxy"   : object,
					@"dc_id"   : @(dcId > 0 ? dcId : 2),
					@"timeout" : [NSNumber numberWithDouble:timeout > 0.0 ? timeout : 10.0]}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGNetIsError(result));
	}];
}

- (void)selectFastestProxyWithCompletion:(void (^)(NSDictionary *))completion {
	__weak typeof(self) weakSelf = self;
	[self proxiesWithCompletion:^(NSArray *proxies){
		if (!proxies.count){
			if (completion)
				completion(nil);
			return;
		}
		[weakSelf pingAllProxiesWithCompletion:^(NSDictionary *seconds){
			NSDictionary *best = nil;
			double bestSeconds = 0.0;
			for (NSDictionary *proxy in proxies){
				id measured = [seconds objectForKey:TGNetNumber(proxy[@"id"])];
				if (![measured isKindOfClass:[NSNumber class]])
					continue;
				double value = [measured doubleValue];
				if (value < 0.0)
					continue;
				if (!best || value < bestSeconds){
					best = proxy;
					bestSeconds = value;
				}
			}
			if (!best){
				if (completion)
					completion(nil);
				return;
			}
			[weakSelf enableProxy:[TGNetNumber(best[@"id"]) integerValue]
					   completion:^(BOOL ok){
				if (completion)
					completion(ok ? best : nil);
			}];
		}];
	}];
}

#pragma mark - proxy links

- (void)proxyLinkFor:(NSDictionary *)proxy
          completion:(void (^)(NSString *))completion {
	NSDictionary *object = TGNetProxyObject(proxy);
	if (!object){
		if (completion)
			completion(nil);
		return;
	}
	[self request:@{@"@type"   : @"getInternalLink",
					@"type"    : @{@"@type" : @"internalLinkTypeProxy",
								   @"proxy" : object},
					@"is_http" : @YES}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNetIsError(result)){
			completion(nil);
			return;
		}
		NSString *url = result[@"url"];
		completion([url isKindOfClass:[NSString class]] && url.length ? url : nil);
	}];
}

- (void)proxyFromLink:(NSString *)link
           completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getInternalLinkType",
					@"link"  : TGNetString(link)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNetIsError(result) ||
			![TGNetString(result[@"@type"]) isEqualToString:@"internalLinkTypeProxy"]){
			completion(nil);
			return;
		}
		completion(TGNetProxyDict(TGNetDict(result[@"proxy"]), nil));
	}];
}

#pragma mark - network type

- (void)setNetworkTypeKind:(NSString *)kind {
	[self send:@{@"@type" : @"setNetworkType",
				 @"type"  : @{@"@type" : TGNetNetworkTypeName(kind)}}];
}

#pragma mark - data usage

- (void)resetNetworkStatisticsWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"resetNetworkStatistics"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGNetIsError(result));
	}];
}

- (void)addCallStatisticsSent:(long long)sentBytes
                     received:(long long)receivedBytes
                     duration:(double)seconds
                  networkKind:(NSString *)kind {
	[self send:@{
		@"@type" : @"addNetworkStatistics",
		@"entry" : @{
			@"@type"          : @"networkStatisticsEntryCall",
			@"network_type"   : @{@"@type" : TGNetNetworkTypeName(kind)},
			@"sent_bytes"     : [NSNumber numberWithLongLong:sentBytes],
			@"received_bytes" : [NSNumber numberWithLongLong:receivedBytes],
			@"duration"       : [NSNumber numberWithDouble:seconds],
		},
	}];
}

#pragma mark - auto-download

- (void)tgNetworkAutoDownloadPresetsWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getAutoDownloadSettingsPresets"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		NSDictionary *low = TGNetSettingsDict(TGNetDict(result[@"low"]));
		NSDictionary *medium = TGNetSettingsDict(TGNetDict(result[@"medium"]));
		NSDictionary *high = TGNetSettingsDict(TGNetDict(result[@"high"]));
		if (TGNetIsError(result) || !low || !medium || !high){
			completion(nil);
			return;
		}
		completion(@{@"low" : low, @"medium" : medium, @"high" : high});
	}];
}

- (void)autoDownloadPresetsWithCompletion:(void (^)(NSDictionary *))completion {
	[self tgNetworkAutoDownloadPresetsWithCompletion:completion];
}

- (void)setAutoDownloadSettings:(NSDictionary *)settings
                    networkKind:(NSString *)kind
                     completion:(void (^)(BOOL))completion {
	[self request:@{@"@type"    : @"setAutoDownloadSettings",
					@"settings" : TGNetSettingsObject(settings),
					@"type"     : @{@"@type" : TGNetNetworkTypeName(kind)}}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGNetIsError(result));
	}];
}

- (void)tgNetworkApplyAutoDownloadSettings:(NSDictionary *)settings
                        toEveryNetworkKind:(void (^)(BOOL ok))completion {
	NSArray *kinds = [NSArray arrayWithObjects:@"mobile", @"mobileRoaming", @"wifi", @"other", nil];
	__block NSUInteger remaining = kinds.count;
	__block BOOL allOk = YES;
	for (NSString *kind in kinds){
		[self setAutoDownloadSettings:settings networkKind:kind completion:^(BOOL ok){
			if (!ok)
				allOk = NO;
			remaining--;
			if (remaining == 0 && completion)
				completion(allOk);
		}];
	}
}

- (void)setDataSaverEnabled:(BOOL)enabled completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self tgNetworkAutoDownloadPresetsWithCompletion:^(NSDictionary *presets){
		NSDictionary *preset = TGNetDict(presets[enabled ? @"low" : @"high"]);
		if (!preset){
			if (completion)
				completion(NO);
			return;
		}
		[weakSelf tgNetworkApplyAutoDownloadSettings:preset toEveryNetworkKind:completion];
	}];
}

- (void)setUseLessDataForCalls:(BOOL)useLess completion:(void (^)(BOOL))completion {
	__weak typeof(self) weakSelf = self;
	[self tgNetworkAutoDownloadPresetsWithCompletion:^(NSDictionary *presets){
		NSDictionary *medium = TGNetDict(presets[@"medium"]);
		if (!medium){
			if (completion)
				completion(NO);
			return;
		}
		NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithDictionary:medium];
		[settings setObject:useLess ? @YES : @NO forKey:@"useLessDataForCalls"];
		[weakSelf tgNetworkApplyAutoDownloadSettings:settings toEveryNetworkKind:completion];
	}];
}

#pragma mark - diagnostics

- (void)optionNamed:(NSString *)name completion:(void (^)(id))completion {
	[self request:@{@"@type" : @"getOption", @"name" : TGNetString(name)}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGNetIsError(result)){
			completion(nil);
			return;
		}
		NSString *type = TGNetString(result[@"@type"]);
		if ([type isEqualToString:@"optionValueEmpty"]){
			completion(nil);
			return;
		}
		id value = result[@"value"];
		if ([type isEqualToString:@"optionValueBoolean"]){
			completion(TGNetBool(value));
			return;
		}
		if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]){
			completion(value);
			return;
		}
		completion(nil);
	}];
}

- (void)setOptionNamed:(NSString *)name
                 value:(id)value
             isBoolean:(BOOL)isBoolean {
	if (!name.length)
		return;
	NSDictionary *object = nil;
	if (isBoolean){
		object = @{@"@type" : @"optionValueBoolean", @"value" : TGNetBool(value)};
	} else if ([value isKindOfClass:[NSString class]]){
		object = @{@"@type" : @"optionValueString", @"value" : value};
	} else if ([value isKindOfClass:[NSNumber class]]){
		object = @{@"@type" : @"optionValueInteger", @"value" : value};
	} else {
		object = @{@"@type" : @"optionValueEmpty"};
	}
	[self send:@{@"@type" : @"setOption", @"name" : name, @"value" : object}];
}

- (NSString *)connectionStateTitle {
	switch (self.connectionState){
		case TGConnectionStateWaitingForNetwork:
			return @"Waiting for network";
		case TGConnectionStateConnecting:
			return @"Connecting...";
		case TGConnectionStateUpdating:
			return @"Updating...";
		default:
			return nil;
	}
}

- (NSString *)connectionStateTitleForState:(TGConnectionState)state {
	switch (state){
		case TGConnectionStateWaitingForNetwork:
			return @"Waiting for network";
		case TGConnectionStateConnecting:
			return @"Connecting...";
		case TGConnectionStateUpdating:
			return @"Updating...";
		default:
			return nil;
	}
}

- (void)tgNetworkConnectionStateTick:(NSTimer *)timer {
	TGConnectionState state = self.connectionState;
	if (TGNetHasLastState && state == TGNetLastState)
		return;
	TGNetHasLastState = YES;
	TGNetLastState = state;
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	[info setObject:[NSNumber numberWithInteger:(NSInteger)state] forKey:TGConnectionStateKey];
	NSString *title = [self connectionStateTitleForState:state];
	if (title)
		[info setObject:title forKey:TGConnectionStateTitleKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:TGConnectionStateDidChangeNotification
														object:self
													  userInfo:info];
}

- (void)beginBroadcastingConnectionState {
	TGNetStateObservers++;
	if (TGNetStateTimer)
		return;
	TGNetHasLastState = NO;
	TGNetStateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
													   target:self
													 selector:@selector(tgNetworkConnectionStateTick:)
													 userInfo:nil
													  repeats:YES];
	[self tgNetworkConnectionStateTick:nil];
}

- (void)endBroadcastingConnectionState {
	if (TGNetStateObservers > 0)
		TGNetStateObservers--;
	if (TGNetStateObservers > 0)
		return;
	[TGNetStateTimer invalidate];
	TGNetStateTimer = nil;
	TGNetHasLastState = NO;
}

@end

// vim:ft=objc
