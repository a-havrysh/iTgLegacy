#import "TGCallMessages.h"

const uint8_t TGCallMessageCandidates = 1;
const uint8_t TGCallMessageMediaState = 4;
const uint8_t TGCallMessageAudioData  = 5;

static const uint8_t kEmptyId = 0xFE;
static const uint8_t kAckId   = 0xFF;

/// Everything here is big-endian, as rtc::ByteBufferWriter writes it.
static uint32_t TGReadU32(const uint8_t *bytes) {
	return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
		   ((uint32_t)bytes[2] << 8)  |  (uint32_t)bytes[3];
}

static void TGAppendU32(NSMutableData *data, uint32_t value) {
	uint8_t bytes[4] = {
		(uint8_t)(value >> 24), (uint8_t)(value >> 16),
		(uint8_t)(value >> 8),  (uint8_t)value
	};
	[data appendBytes:bytes length:4];
}

static void TGAppendString(NSMutableData *data, NSString *string) {
	NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
	TGAppendU32(data, (uint32_t)utf8.length);
	[data appendData:utf8];
}

@implementation TGCallMessages

+ (NSArray *)parsePacket:(NSData *)plaintext seq:(uint32_t)packetSeq {
	const uint8_t *bytes = (const uint8_t *)plaintext.bytes;
	NSUInteger length = plaintext.length;
	NSUInteger at = 0;
	NSMutableArray *messages = [NSMutableArray array];
	uint32_t currentSeq = packetSeq;

	while (at < length){
		uint8_t type = bytes[at];

		if (type == kEmptyId || type == kAckId){
			at += 1;
		} else {
			// A message body runs to the end of the packet unless another
			// sequence number follows, which only the message itself knows how
			// to find - so the tail is handed over whole and the caller reads
			// what it understands.
			[messages addObject:@{
				@"type" : @(type),
				@"seq"  : @(currentSeq),
				@"body" : [plaintext subdataWithRange:
						NSMakeRange(at + 1, length - at - 1)],
			}];
			return messages;
		}

		// Between messages comes the next sequence number.
		if (at + 4 > length)
			break;
		currentSeq = TGReadU32(bytes + at);
		at += 4;
	}
	return messages;
}

+ (NSData *)messageWithType:(uint8_t)type body:(NSData *)body {
	NSMutableData *packet = [NSMutableData data];
	[packet appendBytes:&type length:1];
	[packet appendData:body];
	return packet;
}

+ (BOOL)seqRequiresAck:(uint32_t)seq {
	return (seq & ((uint32_t)1 << 30)) != 0;
}

/// Two messages in one packet, so neither the single-message bit nor the
/// ack-request bit belongs on the sequence number carrying it.
+ (NSData *)ackForSeq:(uint32_t)seq {
	NSMutableData *packet = [NSMutableData data];
	uint8_t empty = kEmptyId, ack = kAckId;
	[packet appendBytes:&empty length:1];
	TGAppendU32(packet, seq);
	[packet appendBytes:&ack length:1];
	return packet;
}

+ (uint32_t)markSeq:(uint32_t)seq requiresAck:(BOOL)requiresAck {
	// A message that wants an acknowledgement cannot also claim to be the only
	// one in its packet, because it may be resent alongside others later.
	return requiresAck ? (seq | ((uint32_t)1 << 30))
					   : (seq | ((uint32_t)1 << 31));
}

+ (NSData *)candidatesBody:(NSArray *)candidates ufrag:(NSString *)ufrag pwd:(NSString *)pwd {
	NSMutableData *body = [NSMutableData data];
	uint8_t count = (uint8_t)candidates.count;
	[body appendBytes:&count length:1];
	for (NSString *candidate in candidates)
		TGAppendString(body, candidate);
	TGAppendString(body, ufrag);
	TGAppendString(body, pwd);
	return body;
}

+ (NSDictionary *)parseCandidates:(NSData *)body {
	const uint8_t *bytes = (const uint8_t *)body.bytes;
	NSUInteger length = body.length;
	NSUInteger at = 0;

	if (length < 1)
		return nil;
	uint8_t count = bytes[at++];

	NSMutableArray *candidates = [NSMutableArray array];
	for (uint8_t i = 0; i < count; i++){
		if (at + 4 > length)
			return nil;
		uint32_t size = TGReadU32(bytes + at);
		at += 4;
		if (at + size > length)
			return nil;
		NSString *candidate = [[NSString alloc]
				initWithBytes:bytes + at length:size encoding:NSUTF8StringEncoding];
		if (candidate)
			[candidates addObject:candidate];
		at += size;
	}

	// The ICE credentials follow the list, and they are what a connectivity
	// check has to be signed with.
	NSString *ufrag = nil, *pwd = nil;
	for (int i = 0; i < 2; i++){
		if (at + 4 > length)
			break;
		uint32_t size = TGReadU32(bytes + at);
		at += 4;
		if (at + size > length)
			break;
		NSString *value = [[NSString alloc]
				initWithBytes:bytes + at length:size encoding:NSUTF8StringEncoding];
		at += size;
		if (i == 0) ufrag = value; else pwd = value;
	}

	return @{
		@"candidates" : candidates,
		@"ufrag"      : ufrag ?: @"",
		@"pwd"        : pwd ?: @"",
	};
}

@end

// vim:ft=objc
