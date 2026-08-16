#import "TGMusicPlayer.h"
#import "TGMusicPlayerBar.h"
#import "TGClient.h"
#import "TGVoiceDecoder.h"
#import "TGCall.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const TGMusicPlayerStateChangedNotification = @"TGMusicPlayerStateChanged";
NSString *const TGMusicPlayerProgressNotification     = @"TGMusicPlayerProgress";

NSString *const TGMusicTrackMessageId = @"messageId";
NSString *const TGMusicTrackChatId    = @"chatId";
NSString *const TGMusicTrackFileId    = @"fileId";
NSString *const TGMusicTrackTitle     = @"title";
NSString *const TGMusicTrackPerformer = @"performer";
NSString *const TGMusicTrackFileName  = @"fileName";
NSString *const TGMusicTrackDuration  = @"duration";
NSString *const TGMusicTrackIsVoice   = @"voice";
NSString *const TGMusicTrackSender    = @"sender";
NSString *const TGMusicTrackDate      = @"date";

static const NSInteger kPlaylistLimit = 100;

static AVAudioPlayer *TGMusicOpenPlayer(NSString *path, NSString *fileName, BOOL voice);

static NSString *TGMusicString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static BOOL TGMusicNeedsOpusDecode(NSString *path, NSString *fileName) {
	NSString *ext = path.pathExtension.lowercaseString;
	if (!ext.length)
		ext = fileName.pathExtension.lowercaseString;
	return [ext isEqualToString:@"ogg"] || [ext isEqualToString:@"oga"]
			|| [ext isEqualToString:@"opus"];
}

static NSString *TGMusicPathWithExtension(NSString *path, NSString *fileName) {
	if (path.pathExtension.length)
		return path;
	NSString *ext = fileName.pathExtension.lowercaseString;
	if (!ext.length)
		ext = @"mp3";
	NSString *linked = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"tgmusic-%@.%@", path.lastPathComponent, ext]];
	NSFileManager *files = [NSFileManager defaultManager];
	if (![files fileExistsAtPath:linked])
		[files createSymbolicLinkAtPath:linked withDestinationPath:path error:nil];
	return [files fileExistsAtPath:linked] ? linked : path;
}

@interface TGMusicPlayer () <AVAudioPlayerDelegate>
@end

@implementation TGMusicPlayer {
	NSMutableArray *_playlist;
	NSInteger _index;
	AVAudioPlayer *_player;
	NSTimer *_tick;
	BOOL _loading;
	BOOL _sessionActive;
	NSUInteger _token;
	NSTimeInterval _pendingOffset;
	NSTimeInterval _lastNowPlayingUpdate;
	NSString *_chatTitle;
	float _voiceRate;
}

+ (instancetype)shared {
	static TGMusicPlayer *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[TGMusicPlayer alloc] init]; });
	return shared;
}

- (instancetype)init {
	if (!(self = [super init]))
		return nil;
	_playlist = [NSMutableArray array];
	_index = NSNotFound;
	_voiceRate = 1.0f;
	NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
	[centre addObserver:self selector:@selector(applicationBackgrounded:)
				   name:UIApplicationDidEnterBackgroundNotification object:nil];
	[centre addObserver:self selector:@selector(applicationForegrounded:)
				   name:UIApplicationWillEnterForegroundNotification object:nil];
	return self;
}

#pragma mark - tracks

static NSString *TGMusicSenderName(int64_t senderId, BOOL outgoing) {
	if (outgoing)
		return @"You";
	NSString *name = senderId ? [[TGClient shared] nameForUserId:senderId] : nil;
	return name.length ? name : @"";
}

+ (NSDictionary *)trackFromMessage:(NSDictionary *)message chatId:(int64_t)chatId {
	if (![message isKindOfClass:NSDictionary.class])
		return nil;
	NSString *kind = TGMusicString(message[@"kind"]);
	BOOL voice = [kind isEqualToString:@"messageVoiceNote"];
	if (!voice && ![kind isEqualToString:@"messageAudio"])
		return nil;
	if (![message[@"docId"] isKindOfClass:NSNumber.class] ||
		![message[@"id"] isKindOfClass:NSNumber.class])
		return nil;

	NSString *fileName = TGMusicString(message[@"docName"]);
	NSString *title = TGMusicString(message[@"audioTitle"]);
	if (!title.length)
		title = voice ? @"Voice message"
					  : (fileName.length ? fileName.lastPathComponent : @"Audio");

	return @{
		TGMusicTrackMessageId : message[@"id"],
		TGMusicTrackChatId    : [NSNumber numberWithLongLong:chatId],
		TGMusicTrackFileId    : message[@"docId"],
		TGMusicTrackTitle     : title,
		TGMusicTrackPerformer : TGMusicString(message[@"audioPerformer"]),
		TGMusicTrackFileName  : fileName,
		TGMusicTrackDuration  : message[@"duration"] ?: @0,
		TGMusicTrackIsVoice   : [NSNumber numberWithBool:voice],
		TGMusicTrackSender    : TGMusicSenderName([message[@"senderId"] longLongValue],
												  [message[@"outgoing"] boolValue]),
		TGMusicTrackDate      : message[@"date"] ?: @0,
	};
}

static NSDictionary *TGMusicTrackFromRawMessage(NSDictionary *m) {
	if (![m isKindOfClass:NSDictionary.class])
		return nil;
	NSDictionary *content = m[@"content"];
	if (![content isKindOfClass:NSDictionary.class])
		return nil;
	NSString *kind = TGMusicString(content[@"@type"]);
	BOOL voice = [kind isEqualToString:@"messageVoiceNote"];
	NSDictionary *media = voice ? content[@"voice_note"] : content[@"audio"];
	if (![media isKindOfClass:NSDictionary.class])
		return nil;

	NSDictionary *file = voice ? media[@"voice"] : media[@"audio"];
	NSNumber *fileId = [file isKindOfClass:NSDictionary.class] ? file[@"id"] : nil;
	if (![fileId isKindOfClass:NSNumber.class] || ![m[@"id"] isKindOfClass:NSNumber.class])
		return nil;

	NSString *fileName = TGMusicString(media[@"file_name"]);
	NSString *title = TGMusicString(media[@"title"]);
	if (!title.length)
		title = voice ? @"Voice message"
					  : (fileName.length ? fileName.lastPathComponent : @"Audio");

	NSDictionary *sender = [m[@"sender_id"] isKindOfClass:NSDictionary.class]
			? m[@"sender_id"] : nil;

	return @{
		TGMusicTrackMessageId : m[@"id"],
		TGMusicTrackChatId    : m[@"chat_id"] ?: @0,
		TGMusicTrackFileId    : fileId,
		TGMusicTrackTitle     : title,
		TGMusicTrackPerformer : TGMusicString(media[@"performer"]),
		TGMusicTrackFileName  : fileName,
		TGMusicTrackDuration  : media[@"duration"] ?: @0,
		TGMusicTrackIsVoice   : [NSNumber numberWithBool:voice],
		TGMusicTrackSender    : TGMusicSenderName([sender[@"user_id"] longLongValue],
												  [m[@"is_outgoing"] boolValue]),
		TGMusicTrackDate      : m[@"date"] ?: @0,
	};
}

#pragma mark - state

- (NSArray *)playlist {
	return _playlist;
}

- (NSDictionary *)currentTrack {
	if (_index == NSNotFound || _index >= (NSInteger)_playlist.count)
		return nil;
	return _playlist[_index];
}

- (int64_t)currentMessageId {
	return [self.currentTrack[TGMusicTrackMessageId] longLongValue];
}

- (int64_t)currentChatId {
	return [self.currentTrack[TGMusicTrackChatId] longLongValue];
}

- (BOOL)isVoice {
	return [self.currentTrack[TGMusicTrackIsVoice] boolValue];
}

- (float)voiceRate {
	return _voiceRate;
}

- (BOOL)isPlaying {
	return _player != nil && _player.playing;
}

- (BOOL)isLoading {
	return _loading;
}

- (NSTimeInterval)currentTime {
	return _player ? _player.currentTime : 0;
}

- (NSTimeInterval)duration {
	if (_player && _player.duration > 0)
		return _player.duration;
	return [self.currentTrack[TGMusicTrackDuration] doubleValue];
}

- (CGFloat)playedFraction {
	NSTimeInterval total = self.duration;
	if (total <= 0)
		return 0;
	return (CGFloat)(self.currentTime / total);
}

- (BOOL)isCurrentMessage:(int64_t)messageId inChat:(int64_t)chatId {
	NSDictionary *track = self.currentTrack;
	if (!track)
		return NO;
	return [track[TGMusicTrackMessageId] longLongValue] == messageId &&
		   [track[TGMusicTrackChatId] longLongValue] == chatId;
}

#pragma mark - starting

- (void)playMessage:(NSDictionary *)message
			 inChat:(int64_t)chatId
		  chatTitle:(NSString *)chatTitle
		fromSeconds:(NSTimeInterval)seconds {
	NSDictionary *track = [TGMusicPlayer trackFromMessage:message chatId:chatId];
	if (!track)
		return;
	int64_t messageId = [track[TGMusicTrackMessageId] longLongValue];

	if ([self isCurrentMessage:messageId inChat:chatId] && (_player || _loading)){
		if (seconds > 0){
			[self seekToSeconds:seconds];
			if (!self.isPlaying)
				[self toggle];
			return;
		}
		[self toggle];
		return;
	}

	_chatTitle = [chatTitle copy];
	[_playlist removeAllObjects];
	[_playlist addObject:[self named:track]];
	_index = 0;
	[self startCurrentFromSeconds:seconds];
	[self loadPlaylistAround:track];
}

- (NSDictionary *)named:(NSDictionary *)track {
	if (![track[TGMusicTrackIsVoice] boolValue] || !_chatTitle.length)
		return track;
	if ([track[TGMusicTrackSender] length])
		return track;
	NSMutableDictionary *named = [track mutableCopy];
	named[TGMusicTrackSender] = _chatTitle;
	return named;
}

- (void)loadPlaylistAround:(NSDictionary *)track {
	int64_t chatId = [track[TGMusicTrackChatId] longLongValue];
	int64_t messageId = [track[TGMusicTrackMessageId] longLongValue];
	BOOL voice = [track[TGMusicTrackIsVoice] boolValue];
	NSString *filter = voice ? @"searchMessagesFilterVoiceNote" : @"searchMessagesFilterAudio";

	NSDictionary *request = @{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : [NSNumber numberWithLongLong:chatId],
		@"query"           : @"",
		@"from_message_id" : @0,
		@"offset"          : @0,
		@"limit"           : [NSNumber numberWithInteger:kPlaylistLimit],
		@"filter"          : @{@"@type" : filter},
	};

	__weak TGMusicPlayer *weakSelf = self;
	[[TGClient shared] request:request completion:^(NSDictionary *result){
		TGMusicPlayer *me = weakSelf;
		if (!me)
			return;
		if (![me isCurrentMessage:messageId inChat:chatId])
			return;
		NSArray *messages = [result isKindOfClass:NSDictionary.class]
				? result[@"messages"] : nil;
		if (![messages isKindOfClass:NSArray.class] || !messages.count)
			return;

		NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:messages.count];
		for (NSDictionary *raw in [messages reverseObjectEnumerator]){
			NSDictionary *entry = TGMusicTrackFromRawMessage(raw);
			if (!entry)
				continue;
			[tracks addObject:[me named:entry]];
		}

		NSInteger found = NSNotFound;
		for (NSUInteger i = 0; i < tracks.count; i++)
			if ([tracks[i][TGMusicTrackMessageId] longLongValue] == messageId)
				found = (NSInteger)i;
		if (found == NSNotFound){
			[tracks addObject:me.currentTrack];
			found = (NSInteger)tracks.count - 1;
		}

		[me adoptPlaylist:tracks index:found];
	}];
}

- (void)adoptPlaylist:(NSArray *)tracks index:(NSInteger)index {
	[_playlist setArray:tracks];
	_index = index;
	[self postStateChanged];
}

- (void)startCurrentFromSeconds:(NSTimeInterval)seconds {
	NSDictionary *track = self.currentTrack;
	if (!track){
		[self stop];
		return;
	}

	[self teardownPlayer];
	_loading = YES;
	_pendingOffset = seconds;
	NSUInteger token = ++_token;
	[TGMusicPlayerBar activate];
	[self postStateChanged];

	NSInteger fileId = [track[TGMusicTrackFileId] integerValue];
	BOOL voice = [track[TGMusicTrackIsVoice] boolValue];
	NSString *fileName = track[TGMusicTrackFileName];

	__weak TGMusicPlayer *weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		TGMusicPlayer *me = weakSelf;
		if (!me || token != me->_token)
			return;
		if (!path.length){
			[me failedWithMessage:@"This track could not be downloaded"];
			return;
		}
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			AVAudioPlayer *ready = TGMusicOpenPlayer(path, fileName, voice);
			dispatch_async(dispatch_get_main_queue(), ^{
				TGMusicPlayer *inner = weakSelf;
				if (!inner || token != inner->_token)
					return;
				if (!ready){
					[inner failedWithMessage:@"This track cannot be played"];
					return;
				}
				[inner beginPlaybackWith:ready];
			});
		});
	}];
}

static AVAudioPlayer *TGMusicOpenPlayer(NSString *path, NSString *fileName, BOOL voice) {
	AVAudioPlayer *player = nil;
	if (!voice && !TGMusicNeedsOpusDecode(path, fileName)){
		NSString *usable = TGMusicPathWithExtension(path, fileName);
		player = [[AVAudioPlayer alloc] initWithContentsOfURL:
				[NSURL fileURLWithPath:usable] error:nil];
		if (player)
			return player;
	}
	NSString *wav = [TGVoiceDecoder wavFromOpusFile:path];
	if (!wav.length)
		return nil;
	return [[AVAudioPlayer alloc] initWithContentsOfURL:
			[NSURL fileURLWithPath:wav] error:nil];
}

- (void)beginPlaybackWith:(AVAudioPlayer *)player {
	_loading = NO;
	_player = player;
	_player.delegate = self;
	if (self.isVoice){
		_player.enableRate = YES;
		[_player prepareToPlay];
	}
	[self activateSession];
	if (_pendingOffset > 0){
		_player.currentTime = MIN(_pendingOffset, _player.duration);
		_pendingOffset = 0;
	}
	[_player play];
	[self applyVoiceRate];
	[self startTick];
	[self updateNowPlaying];
	[self postStateChanged];
}

- (void)failedWithMessage:(NSString *)message {
	_loading = NO;
	[self stop];
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

#pragma mark - transport

- (void)toggle {
	if (_loading)
		return;
	if (!_player){
		if (self.currentTrack)
			[self startCurrentFromSeconds:0];
		return;
	}
	if (_player.playing){
		[_player pause];
		[self stopTick];
	} else {
		[self activateSession];
		[_player play];
		[self applyVoiceRate];
		[self startTick];
	}
	[self updateNowPlaying];
	[self postStateChanged];
}

- (void)playNext {
	if (_index == NSNotFound || _index + 1 >= (NSInteger)_playlist.count)
		return;
	_index += 1;
	[self startCurrentFromSeconds:0];
}

- (void)playPrevious {
	if (_index == NSNotFound)
		return;
	if (_player && _player.currentTime > 3.0){
		[self seekToSeconds:0];
		return;
	}
	if (_index == 0){
		[self seekToSeconds:0];
		return;
	}
	_index -= 1;
	[self startCurrentFromSeconds:0];
}

- (void)seekToFraction:(CGFloat)fraction {
	NSTimeInterval total = self.duration;
	if (total <= 0)
		return;
	[self seekToSeconds:total * MAX((CGFloat)0, MIN((CGFloat)1, fraction))];
}

- (void)seekToSeconds:(NSTimeInterval)seconds {
	if (!_player){
		_pendingOffset = seconds;
		return;
	}
	_player.currentTime = MAX((NSTimeInterval)0, MIN(seconds, _player.duration));
	[self updateNowPlaying];
	[self postProgress];
}

- (void)applyVoiceRate {
	if (!_player || !self.isVoice)
		return;
	_player.enableRate = YES;
	_player.rate = _voiceRate;
}

- (void)cycleVoiceRate {
	if (!self.isVoice)
		return;
	if (_voiceRate < 1.25f)
		_voiceRate = 1.5f;
	else if (_voiceRate < 1.75f)
		_voiceRate = 2.0f;
	else
		_voiceRate = 1.0f;
	[self applyVoiceRate];
	[self postStateChanged];
}

- (void)chatClosed:(int64_t)chatId {
	NSDictionary *track = self.currentTrack;
	if (!track || ![track[TGMusicTrackIsVoice] boolValue])
		return;
	if ([track[TGMusicTrackChatId] longLongValue] != chatId)
		return;
	[self stop];
}

- (void)chatOpened:(int64_t)chatId {
	NSDictionary *track = self.currentTrack;
	if (!track || ![track[TGMusicTrackIsVoice] boolValue])
		return;
	if ([track[TGMusicTrackChatId] longLongValue] == chatId)
		return;
	[self stop];
}

- (void)stop {
	[self teardownPlayer];
	[_playlist removeAllObjects];
	_index = NSNotFound;
	_loading = NO;
	_token++;
	[self clearNowPlaying];
	[self deactivateSession];
	[self postStateChanged];
}

- (void)teardownPlayer {
	[self stopTick];
	_player.delegate = nil;
	[_player stop];
	_player = nil;
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
	if (player != _player)
		return;
	if (_index != NSNotFound && _index + 1 < (NSInteger)_playlist.count){
		[self playNext];
		return;
	}
	[self stop];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
	if (player == _player)
		[self stop];
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player {
	[self stopTick];
	[self postStateChanged];
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player withOptions:(NSUInteger)flags {
	if (player != _player)
		return;
	[self activateSession];
	[_player play];
	[self applyVoiceRate];
	[self startTick];
	[self postStateChanged];
}

#pragma mark - session, remote control, lock screen

- (void)activateSession {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryPlayback error:nil];
	[session setActive:YES error:nil];
	if (!_sessionActive){
		_sessionActive = YES;
		[[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
	}
}

- (void)deactivateSession {
	if (!_sessionActive)
		return;
	_sessionActive = NO;
	[[UIApplication sharedApplication] endReceivingRemoteControlEvents];
	TGCallState call = [TGCall shared].state;
	if (call == TGCallStateNone || call == TGCallStateEnded || call == TGCallStateFailed)
		[[AVAudioSession sharedInstance] setActive:NO error:nil];
}

- (void)handleRemoteControlEvent:(UIEvent *)event {
	if (event.type != UIEventTypeRemoteControl)
		return;
	switch (event.subtype){
		case UIEventSubtypeRemoteControlPlay:
		case UIEventSubtypeRemoteControlPause:
		case UIEventSubtypeRemoteControlTogglePlayPause:
			[self toggle];
			break;
		case UIEventSubtypeRemoteControlNextTrack:
			if (!self.isVoice)
				[self playNext];
			break;
		case UIEventSubtypeRemoteControlPreviousTrack:
			if (!self.isVoice)
				[self playPrevious];
			break;
		case UIEventSubtypeRemoteControlStop:
			[self stop];
			break;
		default:
			break;
	}
}

- (Class)nowPlayingCentre {
	return NSClassFromString(@"MPNowPlayingInfoCenter");
}

- (void)updateNowPlaying {
	Class centre = [self nowPlayingCentre];
	NSDictionary *track = self.currentTrack;
	if (!centre || !track)
		return;
	if ([track[TGMusicTrackIsVoice] boolValue]){
		[self clearNowPlaying];
		_lastNowPlayingUpdate = [NSDate timeIntervalSinceReferenceDate];
		return;
	}
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[MPMediaItemPropertyTitle] = track[TGMusicTrackTitle] ?: @"Audio";
	NSString *performer = track[TGMusicTrackPerformer];
	if (performer.length)
		info[MPMediaItemPropertyArtist] = performer;
	info[MPMediaItemPropertyPlaybackDuration] = [NSNumber numberWithDouble:self.duration];
	info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
			[NSNumber numberWithDouble:self.currentTime];
	info[MPNowPlayingInfoPropertyPlaybackRate] =
			[NSNumber numberWithDouble:(self.isPlaying ? 1.0 : 0.0)];
	[(MPNowPlayingInfoCenter *)[centre defaultCenter] setNowPlayingInfo:info];
	_lastNowPlayingUpdate = [NSDate timeIntervalSinceReferenceDate];
}

- (void)clearNowPlaying {
	Class centre = [self nowPlayingCentre];
	if (centre)
		[(MPNowPlayingInfoCenter *)[centre defaultCenter] setNowPlayingInfo:nil];
}

#pragma mark - ticking

- (void)startTick {
	[self stopTick];
	_tick = [NSTimer scheduledTimerWithTimeInterval:0.2
											 target:self
										   selector:@selector(ticked)
										   userInfo:nil
											repeats:YES];
}

- (void)stopTick {
	[_tick invalidate];
	_tick = nil;
}

- (void)ticked {
	[self postProgress];
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if (now - _lastNowPlayingUpdate > 2.0)
		[self updateNowPlaying];
}

- (void)applicationBackgrounded:(NSNotification *)note {
	[self stopTick];
}

- (void)applicationForegrounded:(NSNotification *)note {
	if (self.isPlaying)
		[self startTick];
}

#pragma mark - notifications

- (void)postStateChanged {
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGMusicPlayerStateChangedNotification object:self];
}

- (void)postProgress {
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGMusicPlayerProgressNotification object:self];
}

@end
