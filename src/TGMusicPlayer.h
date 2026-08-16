#import <UIKit/UIKit.h>

extern NSString *const TGMusicPlayerStateChangedNotification;
extern NSString *const TGMusicPlayerProgressNotification;

extern NSString *const TGMusicTrackMessageId;
extern NSString *const TGMusicTrackChatId;
extern NSString *const TGMusicTrackFileId;
extern NSString *const TGMusicTrackTitle;
extern NSString *const TGMusicTrackPerformer;
extern NSString *const TGMusicTrackFileName;
extern NSString *const TGMusicTrackDuration;
extern NSString *const TGMusicTrackIsVoice;

@interface TGMusicPlayer : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray *playlist;
@property (nonatomic, readonly) NSDictionary *currentTrack;
@property (nonatomic, readonly) int64_t currentMessageId;
@property (nonatomic, readonly) int64_t currentChatId;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) CGFloat playedFraction;

+ (NSDictionary *)trackFromMessage:(NSDictionary *)message chatId:(int64_t)chatId;

- (void)playMessage:(NSDictionary *)message
			 inChat:(int64_t)chatId
		  chatTitle:(NSString *)chatTitle
		fromSeconds:(NSTimeInterval)seconds;

- (void)toggle;
- (void)playNext;
- (void)playPrevious;
- (void)seekToFraction:(CGFloat)fraction;
- (void)seekToSeconds:(NSTimeInterval)seconds;
- (void)stop;

- (BOOL)isCurrentMessage:(int64_t)messageId inChat:(int64_t)chatId;

- (void)handleRemoteControlEvent:(UIEvent *)event;

@end
