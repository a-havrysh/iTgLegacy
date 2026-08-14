#import "TGVoiceRecorder.h"
#import <AVFoundation/AVFoundation.h>
#include "opusenc/opusenc.h"

static const NSTimeInterval TGVoiceRecorderMaxDuration = 60.0 * 60.0;

@interface TGVoiceRecorder () <AVAudioRecorderDelegate>
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) NSString *pcmPath;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, assign) NSTimeInterval capturedDuration;
@end

@implementation TGVoiceRecorder

+ (instancetype)shared {
	static TGVoiceRecorder *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGVoiceRecorder alloc] init]; });
	return s;
}

- (BOOL)recording {
	return self.recorder != nil && self.recorder.isRecording;
}

- (NSTimeInterval)duration {
	if (self.startedAt)
		return self.capturedDuration - [self.startedAt timeIntervalSinceNow];
	return self.capturedDuration;
}

- (NSString *)temporaryPathWithExtension:(NSString *)ext {
	NSString *name = [NSString stringWithFormat:@"voice-%.0f-%u.%@",
			[[NSDate date] timeIntervalSince1970] * 1000.0, arc4random() % 100000, ext];
	return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (void)deactivateSession {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	NSError *err = nil;
	[session setCategory:AVAudioSessionCategoryPlayback error:&err];
	[session setActive:YES error:&err];
}

- (BOOL)start {
	if (self.recording)
		return YES;

	[self teardownRecorderKeepingFile:NO];

	NSError *err = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	if (![session setCategory:AVAudioSessionCategoryPlayAndRecord error:&err]){
		NSLog(@"TGVoiceRecorder: audio session category: %@", err);
		return NO;
	}
	err = nil;
	if (![session setActive:YES error:&err]){
		NSLog(@"TGVoiceRecorder: audio session activate: %@", err);
		return NO;
	}

	if ([session respondsToSelector:@selector(inputIsAvailable)] && !session.inputIsAvailable){
		NSLog(@"TGVoiceRecorder: no audio input available");
		[self deactivateSession];
		return NO;
	}

	self.pcmPath = [self temporaryPathWithExtension:@"caf"];
	[[NSFileManager defaultManager] removeItemAtPath:self.pcmPath error:nil];

	// 48kHz mono 16-bit: what libopusenc wants, so nothing has to be resampled.
	NSDictionary *settings = @{
		AVFormatIDKey            : @(kAudioFormatLinearPCM),
		AVSampleRateKey          : @(48000.0),
		AVNumberOfChannelsKey    : @(1),
		AVLinearPCMBitDepthKey   : @(16),
		AVLinearPCMIsFloatKey    : @NO,
		AVLinearPCMIsBigEndianKey: @NO,
	};

	err = nil;
	self.recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:self.pcmPath]
												settings:settings
												   error:&err];
	if (!self.recorder || err){
		NSLog(@"TGVoiceRecorder: %@", err);
		self.recorder = nil;
		self.pcmPath = nil;
		[self deactivateSession];
		return NO;
	}

	self.recorder.delegate = self;
	if (![self.recorder prepareToRecord]){
		NSLog(@"TGVoiceRecorder: prepareToRecord failed");
		[self teardownRecorderKeepingFile:NO];
		[self deactivateSession];
		return NO;
	}

	self.capturedDuration = 0;
	self.startedAt = [NSDate date];

	BOOL started = [self.recorder recordForDuration:TGVoiceRecorderMaxDuration];
	if (!started){
		NSLog(@"TGVoiceRecorder: record failed to start");
		[self teardownRecorderKeepingFile:NO];
		[self deactivateSession];
		return NO;
	}

	if ([session respondsToSelector:@selector(requestRecordPermission:)]){
		__weak typeof(self) weakSelf = self;
		[session requestRecordPermission:^(BOOL granted){
			if (granted)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				TGVoiceRecorder *me = weakSelf;
				NSLog(@"TGVoiceRecorder: microphone permission denied");
				[me cancel];
			});
		}];
	}

	return YES;
}

- (void)teardownRecorderKeepingFile:(BOOL)keepFile {
	AVAudioRecorder *recorder = self.recorder;
	self.recorder = nil;
	recorder.delegate = nil;
	if (recorder.isRecording)
		[recorder stop];

	self.startedAt = nil;
	if (!keepFile){
		if (self.pcmPath)
			[[NSFileManager defaultManager] removeItemAtPath:self.pcmPath error:nil];
		self.pcmPath = nil;
		self.capturedDuration = 0;
	}
}

- (void)cancel {
	[self teardownRecorderKeepingFile:NO];
	[self deactivateSession];
}

- (void)stopWithCompletion:(void (^)(NSString *, NSTimeInterval))completion {
	NSTimeInterval seconds = self.duration;
	self.capturedDuration = seconds;

	NSString *pcmPath = self.pcmPath;
	[self teardownRecorderKeepingFile:YES];
	self.pcmPath = nil;
	self.capturedDuration = 0;
	[self deactivateSession];

	if (!pcmPath || seconds < 0.3){
		if (pcmPath)
			[[NSFileManager defaultManager] removeItemAtPath:pcmPath error:nil];
		if (completion) completion(nil, 0);
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *oga = nil;
		@try {
			oga = [self encodePCMAtPath:pcmPath];
		} @catch (NSException *exception){
			NSLog(@"TGVoiceRecorder: encode exception %@", exception);
			oga = nil;
		}
		[[NSFileManager defaultManager] removeItemAtPath:pcmPath error:nil];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(oga, seconds);
		});
	});
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
	NSLog(@"TGVoiceRecorder: encode error %@", error);
	if (recorder == self.recorder)
		[self cancel];
}

- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder {
	if (recorder == self.recorder)
		[self cancel];
}

/// CAF from AVAudioRecorder is a header followed by raw samples; find the data
/// chunk, then feed it to libopusenc.
- (NSString *)encodePCMAtPath:(NSString *)path {
	if (!path)
		return nil;

	NSData *caf = [NSData dataWithContentsOfFile:path
										 options:NSDataReadingMappedIfSafe
										   error:nil];
	if (caf.length < 64){
		NSLog(@"TGVoiceRecorder: nothing recorded");
		return nil;
	}

	const uint8_t *bytes = caf.bytes;
	NSUInteger offset = 0, dataLength = 0;

	// Walk CAF chunks looking for "data"; its payload starts 4 bytes in, after
	// the edit-count field.
	NSUInteger p = 8;
	while (p + 12 <= caf.length){
		char type[5] = {0};
		memcpy(type, bytes + p, 4);
		uint64_t size = 0;
		for (int i = 0; i < 8; i++)
			size = (size << 8) | bytes[p + 4 + i];   // CAF sizes are big-endian

		if (!strcmp(type, "data")){
			offset = p + 12 + 4;
			if (offset >= caf.length)
				break;
			if (size == (uint64_t)-1 || size < 4 || p + 12 + size > caf.length)
				dataLength = caf.length - offset;
			else
				dataLength = (NSUInteger)size - 4;
			if (dataLength > caf.length - offset)
				dataLength = caf.length - offset;
			break;
		}

		if (size == 0 || size > caf.length)
			break;
		p += 12 + (NSUInteger)size;
	}

	if (!offset || dataLength < 2){
		NSLog(@"TGVoiceRecorder: no data chunk");
		return nil;
	}

	NSString *out = [self temporaryPathWithExtension:@"oga"];
	[[NSFileManager defaultManager] removeItemAtPath:out error:nil];

	int error = 0;
	OggOpusComments *comments = ope_comments_create();
	OggOpusEnc *enc = ope_encoder_create_file(out.UTF8String, comments, 48000, 1, 0, &error);
	if (!enc){
		NSLog(@"TGVoiceRecorder: encoder create failed (%d)", error);
		ope_comments_destroy(comments);
		return nil;
	}

	const short *samples = (const short *)(bytes + offset);
	NSUInteger total = dataLength / sizeof(short);
	NSUInteger chunk = 960;   // 20ms at 48kHz

	for (NSUInteger i = 0; i < total; i += chunk){
		int count = (int)MIN(chunk, total - i);
		if (ope_encoder_write(enc, samples + i, count) != 0){
			NSLog(@"TGVoiceRecorder: write failed at %lu", (unsigned long)i);
			break;
		}
	}

	ope_encoder_drain(enc);
	ope_encoder_destroy(enc);
	ope_comments_destroy(comments);

	NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:out error:nil];
	unsigned long long size = attrs ? [attrs fileSize] : 0;
	NSLog(@"TGVoiceRecorder: encoded %llu bytes", size);
	if (size == 0){
		[[NSFileManager defaultManager] removeItemAtPath:out error:nil];
		return nil;
	}
	return out;
}

@end

// vim:ft=objc
