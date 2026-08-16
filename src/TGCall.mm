#import "TGCall.h"
#import "TGClient.h"
#import "TGCallReflector.h"
#import "TGCallMessages.h"
#import "TGCallIce.h"
#import "TGCallStun.h"
#include "TGCallCrypto.h"
#import <AVFoundation/AVFoundation.h>

#include "libtgvoip/VoIPController.h"
#include <openssl/aes.h>
#include <openssl/modes.h>
#include <openssl/rand.h>
#include <openssl/sha.h>

#include "libtgvoip/video/VideoSource.h"
#include "libtgvoip/video/VideoRenderer.h"

using namespace tgvoip;

NSString *const TGCallStateDidChangeNotification = @"TGCallStateDidChangeNotification";

// With TGVOIP_USE_CUSTOM_CRYPTO the library declares this and leaves defining
// it to whoever links it.
namespace tgvoip {
	CryptoFunctions VoIPController::crypto;
}

// This build carries no video. VoIPController asks what the platform can do
// before it offers anything, and an empty answer is the honest one.
namespace tgvoip { namespace video {
	std::vector<uint32_t> VideoSource::GetAvailableEncoders() { return {}; }
	std::vector<uint32_t> VideoRenderer::GetAvailableDecoders() { return {}; }
	int VideoRenderer::GetMaximumResolution() { return 0; }
}}

#pragma mark - crypto

// libtgvoip is built with TGVOIP_USE_CUSTOM_CRYPTO, which means it ships no
// crypto of its own and expects these filled in before any controller runs.
// OpenSSL is already in the build for TDLib.

static void TGRandBytes(uint8_t *buffer, size_t length) {
	RAND_bytes(buffer, (int)length);
}

static void TGSha1(uint8_t *msg, size_t length, uint8_t *output) {
	SHA1(msg, length, output);
}

static void TGSha256(uint8_t *msg, size_t length, uint8_t *output) {
	SHA256(msg, length, output);
}

static void TGAesIgeEncrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_encrypt_key(key, 32 * 8, &akey);
	AES_ige_encrypt(in, out, length, &akey, iv, AES_ENCRYPT);
}

static void TGAesIgeDecrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_decrypt_key(key, 32 * 8, &akey);
	AES_ige_encrypt(in, out, length, &akey, iv, AES_DECRYPT);
}

static void TGAesCtrEncrypt(uint8_t *inout, size_t length, uint8_t *key,
							uint8_t *iv, uint8_t *ecount, uint32_t *num) {
	AES_KEY akey;
	AES_set_encrypt_key(key, 32 * 8, &akey);
	CRYPTO_ctr128_encrypt(inout, inout, length, &akey, iv, ecount, num,
						  (block128_f)AES_encrypt);
}

static void TGAesCbcEncrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_encrypt_key(key, 256, &akey);
	AES_cbc_encrypt(in, out, length, &akey, iv, AES_ENCRYPT);
}

static void TGAesCbcDecrypt(uint8_t *in, uint8_t *out, size_t length,
							uint8_t *key, uint8_t *iv) {
	AES_KEY akey;
	AES_set_decrypt_key(key, 256, &akey);
	AES_cbc_encrypt(in, out, length, &akey, iv, AES_DECRYPT);
}

static void TGInstallCrypto(void) {
	static BOOL installed = NO;
	if (installed)
		return;
	installed = YES;
	VoIPController::crypto.rand_bytes      = TGRandBytes;
	VoIPController::crypto.sha1            = TGSha1;
	VoIPController::crypto.sha256          = TGSha256;
	VoIPController::crypto.aes_ige_encrypt = TGAesIgeEncrypt;
	VoIPController::crypto.aes_ige_decrypt = TGAesIgeDecrypt;
	VoIPController::crypto.aes_ctr_encrypt = TGAesCtrEncrypt;
	VoIPController::crypto.aes_cbc_encrypt = TGAesCbcEncrypt;
	VoIPController::crypto.aes_cbc_decrypt = TGAesCbcDecrypt;
}

#pragma mark -

@interface TGCall ()
@property (nonatomic, assign) TGCallState state;
@property (nonatomic, assign) int32_t callId;
@property (nonatomic, assign) int64_t peerUserId;
@property (nonatomic, assign) BOOL outgoing;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, strong) NSDate *establishedAt;
@property (nonatomic, strong) NSString *endReason;
@property (nonatomic, strong) TGCallReflector *reflector;      // the chosen one
@property (nonatomic, strong) NSMutableArray *reflectors;      // all of them
@property (nonatomic, strong) NSData *callKey;
@property (nonatomic, strong) NSString *localUfrag;
@property (nonatomic, strong) NSString *localPwd;
@property (nonatomic, strong) NSString *reflectorHost;
@property (nonatomic, assign) uint32_t signallingSeq;
@property (nonatomic, assign) BOOL sentCandidates;
@property (nonatomic, assign) uint32_t currentSenderTag;
@property (nonatomic, strong) TGCallReflector *currentReflector;
@property (nonatomic, strong) NSString *peerUfrag;
@property (nonatomic, strong) NSString *peerPwd;
@property (nonatomic, strong) TGCallIce *ice;
@end

@implementation TGCall {
	VoIPController *_controller;
}

+ (instancetype)shared {
	static TGCall *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[TGCall alloc] init]; });
	return s;
}

- (NSTimeInterval)duration {
	return self.establishedAt ? -[self.establishedAt timeIntervalSinceNow] : 0;
}

- (void)setState:(TGCallState)state {
	if (_state == state)
		return;
	_state = state;
	if (state == TGCallStateEstablished && !self.establishedAt)
		self.establishedAt = [NSDate date];
	if (self.onStateChanged)
		self.onStateChanged(state);
	[[NSNotificationCenter defaultCenter]
			postNotificationName:TGCallStateDidChangeNotification object:self];
}

#pragma mark - signalling

/// ICE credentials are ours to choose; the peer signs its connectivity checks
/// with them, so they only have to be random and match what we announce.
- (NSString *)randomIceStringOfLength:(NSInteger)length {
	static NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	NSMutableString *out = [NSMutableString string];
	for (NSInteger i = 0; i < length; i++)
		[out appendFormat:@"%C", [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
	return out;
}

/// Our only route is the reflector, so that is the one candidate we offer -
/// a relay candidate pointing at it. The peer will send its checks there and
/// the reflector will hand them to us, because both ends share the tag.
- (void)sendOurCandidates {
	if (self.sentCandidates || !self.reflectorHost.length)
		return;
	self.sentCandidates = YES;

	self.localUfrag = [self randomIceStringOfLength:4];
	self.localPwd = [self randomIceStringOfLength:24];

	self.ice = [[TGCallIce alloc] init];
	self.ice.localUfrag = self.localUfrag;
	self.ice.localPwd = self.localPwd;
	__weak __typeof__(self) weakSelf = self;
	self.ice.transport = ^(NSData *packet){
		TGCall *me = weakSelf;
		// An answer goes to the port that asked; anything else - our own
		// checks - goes to every tag the peer has shown us.
		if (me.currentSenderTag){
			[me.currentReflector ?: me.reflector sendPayload:packet
													   toTag:me.currentSenderTag];
			return;
		}
		for (TGCallReflector *reflector in me.reflectors)
			[reflector sendPayload:packet];
	};
	self.ice.onConnected = ^(NSString *address, uint16_t port){
		NSLog(@"TGCall: media path is %@:%u", address, port);
		weakSelf.state = TGCallStateEstablished;
	};
	[self.ice start];

	// The address is a name rather than an IP: the peer reads our four-byte
	// tag out of it and uses that to address us through the reflector.
	NSMutableArray *candidates = [NSMutableArray array];
	NSInteger index = 0;
	for (TGCallReflector *reflector in self.reflectors){
		index++;
		NSString *hostname = [NSString stringWithFormat:@"reflector-%ld-%u.reflector",
				(long)index, reflector.localTag];
		// Written exactly the way the peer writes its own: component 0, no
		// raddr or rport. A line their parser rejects takes the whole message
		// with it, and then they never learn our credentials at all.
		[candidates addObject:[NSString stringWithFormat:
				@"candidate:%u 0 udp 41878272 %@ %u typ relay generation 0 "
				@"ufrag %@ network-id 9 network-cost 50",
				reflector.localTag, hostname, reflector.port, self.localUfrag]];
	}

	NSData *body = [TGCallMessages candidatesBody:candidates
											ufrag:self.localUfrag
											  pwd:self.localPwd];
	NSData *message = [TGCallMessages messageWithType:TGCallMessageCandidates body:body];
	[self sendSignalling:message
					 seq:[TGCallMessages markSeq:++self.signallingSeq requiresAck:YES]];
	NSLog(@"TGCall: sent our candidates, ufrag=%@", self.localUfrag);
}

/// The peer's half of the negotiation. Decrypting it is also the check that
/// the crypto is right: the msgKey is a slice of SHA256 over the plaintext, so
/// a wrong key cannot produce a match.
- (void)handleSignalingData:(NSData *)data {
	if (!self.callKey.length || !data.length)
		return;

	NSMutableData *out = [NSMutableData dataWithLength:data.length];
	uint32_t seq = 0;
	int size = TGCallDecryptPacket((const uint8_t *)self.callKey.bytes,
								   self.outgoing, 1 /* signalling */,
								   (const uint8_t *)data.bytes, data.length,
								   (uint8_t *)out.mutableBytes, &seq);
	if (size <= 0){
		NSLog(@"TGCall: signalling %lu bytes did not decrypt", (unsigned long)data.length);
		return;
	}
	out.length = size;

	for (NSDictionary *message in [TGCallMessages parsePacket:out seq:seq]){
		uint8_t type = [message[@"type"] unsignedCharValue];
		uint32_t messageSeq = [message[@"seq"] unsignedIntValue];

		// Without an acknowledgement the peer keeps resending and never moves
		// on to the next step of the negotiation.
		if ([TGCallMessages seqRequiresAck:messageSeq])
			[self sendSignalling:[TGCallMessages ackForSeq:messageSeq]
							 seq:++self.signallingSeq];

		if (type != TGCallMessageCandidates){
			NSLog(@"TGCall: signalling message type %d, %lu bytes", type,
					(unsigned long)[message[@"body"] length]);
			continue;
		}
		NSDictionary *ice = [TGCallMessages parseCandidates:message[@"body"]];
		self.peerUfrag = ice[@"ufrag"];
		self.peerPwd = ice[@"pwd"];
		self.ice.peerUfrag = self.peerUfrag;
		self.ice.peerPwd = self.peerPwd;
		NSLog(@"TGCall: peer ICE ufrag=%@ pwd=%@", self.peerUfrag, self.peerPwd);
		for (NSString *candidate in ice[@"candidates"]){
			NSLog(@"TGCall: peer candidate: %@", candidate);
			[self readPeerTagFromCandidate:candidate];
			[self.ice addPeerCandidate:candidate];
		}
	}
}

/// Their relay candidate carries their four bytes the same way ours does.
- (void)readPeerTagFromCandidate:(NSString *)candidate {
	NSRange marker = [candidate rangeOfString:@"reflector-"];
	if (marker.location == NSNotFound || self.reflector.remoteTag)
		return;

	NSString *tail = [candidate substringFromIndex:marker.location + marker.length];
	NSArray *parts = [[tail componentsSeparatedByString:@".reflector"][0]
			componentsSeparatedByString:@"-"];
	if (parts.count < 2)
		return;

	uint32_t tag = (uint32_t)[parts[1] longLongValue];
	for (TGCallReflector *reflector in self.reflectors)
		reflector.remoteTag = tag;
	NSLog(@"TGCall: peer reflector tag %u", tag);
}

- (void)sendSignalling:(NSData *)plaintext seq:(uint32_t)seq {
	if (!self.callKey.length)
		return;

	NSMutableData *encrypted = [NSMutableData dataWithLength:plaintext.length + 32];
	int size = TGCallEncryptPacket((const uint8_t *)self.callKey.bytes,
								   self.outgoing, 1 /* signalling */,
								   (const uint8_t *)plaintext.bytes, plaintext.length,
								   seq,
								   (uint8_t *)encrypted.mutableBytes);
	if (size <= 0)
		return;
	encrypted.length = size;

	[[TGClient shared] send:@{
		@"@type"   : @"sendCallSignalingData",
		@"call_id" : @(self.callId),
		@"data"    : [encrypted base64EncodedStringWithOptions:0],
	}];
}

- (void)callUser:(int64_t)userId {
	self.peerUserId = userId;
	self.outgoing = YES;
	self.state = TGCallStatePending;
	[[TGClient shared] send:@{
		@"@type"     : @"createCall",
		@"user_id"   : @(userId),
		@"protocol"  : [self protocol],
		@"is_video"  : @NO,
	}];
}

- (void)accept {
	if (!self.callId)
		return;
	[[TGClient shared] send:@{
		@"@type"    : @"acceptCall",
		@"call_id"  : @(self.callId),
		@"protocol" : [self protocol],
	}];
}

- (void)hangUp {
	if (self.callId)
		[[TGClient shared] send:@{
			@"@type"           : @"discardCall",
			@"call_id"         : @(self.callId),
			@"is_disconnected" : @NO,
			@"duration"        : @((int)[self duration]),
			@"is_video"        : @NO,
			@"connection_id"   : @(0),
		}];
	[self teardown];
	self.state = TGCallStateEnded;
}

/// 65 to 92 with library version 2.4.4 is exactly what the official clients
/// advertised while libtgvoip was their call library. A peer that only speaks
/// tgcalls refuses this outright - see the note in ROADMAP.
- (NSDictionary *)protocol {
	return @{
		@"@type"            : @"callProtocol",
		// A direct path needs an address the peer can reach, and behind a
		// carrier NAT there is none: checks sent to their public address are
		// dropped by their NAT because nothing has come from us before. The
		// reflector exists for exactly this, so it is what we ask for.
		@"udp_p2p"          : @NO,
		@"udp_reflector"    : @YES,
		@"min_layer"        : @(65),
		@"max_layer"        : @(92),
		// Probing which tgcalls versions this peer still accepts. 2.4.4 alone
		// is refused outright; if 3.0.0 is taken, its media is plain RTP with
		// Opus inside an EncryptedConnection, which is implementable here.
		// Probing what the peer prefers. 9.0.0 is the current tgcalls version;
		// if it takes that, the negotiation runs v2 - JSON signalling, relay
		// candidates with a resolvable tag, and DTLS-SRTP for the media.
		@"library_versions" : @[@"9.0.0", @"3.0.0", @"2.4.4"],
	};
}

- (void)handleUpdate:(NSDictionary *)call {
	self.callId = [call[@"id"] intValue];
	self.peerUserId = [call[@"user_id"] longLongValue];
	self.outgoing = [call[@"is_outgoing"] boolValue];

	NSDictionary *state = call[@"state"];
	NSString *kind = state[@"@type"];
	NSLog(@"TGCall: %@ (call %d, outgoing %d)", kind, self.callId, self.outgoing);

	if ([kind isEqualToString:@"callStatePending"]){
		self.state = TGCallStatePending;
	} else if ([kind isEqualToString:@"callStateExchangingKeys"]){
		self.state = TGCallStateExchangingKeys;
	} else if ([kind isEqualToString:@"callStateReady"]){
		[self startMediaWithState:state];
	} else if ([kind isEqualToString:@"callStateDiscarded"] ||
			   [kind isEqualToString:@"callStateHangingUp"]){
		// The reason is the useful part: a peer that cannot speak this
		// protocol discards rather than answering, and looks like a decline.
		NSString *reason = state[@"reason"][@"@type"];
		NSLog(@"TGCall: discarded, reason %@", reason ?: @"(none)");
		self.endReason = [self humanReason:reason];
		[self teardown];
		self.state = TGCallStateEnded;
	} else if ([kind isEqualToString:@"callStateError"]){
		NSLog(@"TGCall: error %@ %@", state[@"error"][@"code"], state[@"error"][@"message"]);
		self.endReason = state[@"error"][@"message"];
		[self teardown];
		self.state = TGCallStateFailed;
	}
}

- (NSString *)humanReason:(NSString *)reason {
	if ([reason isEqualToString:@"callDiscardReasonDeclined"])       return @"Declined";
	if ([reason isEqualToString:@"callDiscardReasonMissed"])         return @"No answer";
	if ([reason isEqualToString:@"callDiscardReasonDisconnected"])   return @"Disconnected";
	if ([reason isEqualToString:@"callDiscardReasonHungUp"])         return @"Call ended";
	// This is the one that means the other side speaks only tgcalls.
	if ([reason isEqualToString:@"callDiscardReasonUpgradeToGroupCall"]) return @"Moved to a group call";
	return nil;
}

#pragma mark - media

- (void)startMediaWithState:(NSDictionary *)state {
	if (_controller)
		return;

	TGInstallCrypto();
	self.state = TGCallStateConnecting;

	// The audio session has to be a call, or iOS routes it to the speaker and
	// ignores the proximity sensor.
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
	[session setMode:AVAudioSessionModeVoiceChat error:nil];
	[session setActive:YES error:nil];

	NSData *key = [[NSData alloc] initWithBase64EncodedString:state[@"encryption_key"]
													  options:0];
	if (key.length != 256){
		NSLog(@"TGCall: encryption key is %lu bytes, expected 256",
				(unsigned long)key.length);
		self.state = TGCallStateFailed;
		return;
	}

	self.callKey = key;
	[self probeReflectorsIn:state key:key];

	std::vector<Endpoint> endpoints;
	for (NSDictionary *server in state[@"servers"]){
		NSDictionary *type = server[@"type"];
		if (![type[@"@type"] isEqualToString:@"callServerTypeTelegramReflector"])
			continue;   // webrtc reflectors belong to tgcalls, not this library

		NSData *peerTag = [[NSData alloc] initWithBase64EncodedString:type[@"peer_tag"]
															 options:0];
		unsigned char tag[16] = {0};
		if (peerTag.length >= 16)
			memcpy(tag, peerTag.bytes, 16);

		IPv4Address v4([server[@"ip_address"] UTF8String] ?: "");
		IPv6Address v6([server[@"ipv6_address"] UTF8String] ?: "");
		endpoints.push_back(Endpoint([server[@"id"] longLongValue],
									 (uint16_t)[server[@"port"] intValue],
									 v4, v6, Endpoint::Type::UDP_RELAY, tag));
	}

	if (endpoints.empty()){
		NSLog(@"TGCall: no reflector this build can use");
		self.state = TGCallStateFailed;
		return;
	}

	_controller = new VoIPController();

	VoIPController::Config config(30.0, 20.0, DATA_SAVING_NEVER,
								  false /* AEC */, false /* NS */, false /* AGC */,
								  false /* call upgrade */);
	_controller->SetConfig(config);
	_controller->SetEncryptionKey((char *)key.bytes, self.outgoing);
	_controller->SetRemoteEndpoints(endpoints,
									[state[@"allow_p2p"] boolValue],
									[state[@"protocol"][@"max_layer"] intValue] ?: 65);

	VoIPController::Callbacks callbacks = {0};
	callbacks.connectionStateChanged = [](VoIPController *controller, int newState){
		dispatch_async(dispatch_get_main_queue(), ^{
			TGCall *call = [TGCall shared];
			switch (newState){
				case STATE_ESTABLISHED:  call.state = TGCallStateEstablished; break;
				case STATE_FAILED:       call.state = TGCallStateFailed; break;
				case STATE_RECONNECTING: call.state = TGCallStateConnecting; break;
				default: break;
			}
		});
	};
	_controller->SetCallbacks(callbacks);

	_controller->Start();
	_controller->Connect();
}

/// Stage one of speaking tgcalls rather than libtgvoip: open the reflector
/// ourselves and see what comes back. Nothing can arrive until the peer knows
/// our four-byte tag, which travels over the signalling channel - so for now
/// this proves the socket, the tag format and the address, and logs anything
/// the reflector says on its own.
/// Both ends have to sit on the same reflector: the twelve-byte prefix of the
/// tag is per server, so packets crossing different ones never meet. TDLib
/// hands out several and the peer picks its own, so this connects to all of
/// them and lets the tags decide which one carries the call.
- (void)probeReflectorsIn:(NSDictionary *)state key:(NSData *)key {
	self.reflectors = [NSMutableArray array];
	__weak __typeof__(self) weakSelf = self;

	NSInteger index = 0;
	for (NSDictionary *server in state[@"servers"]){
		NSDictionary *type = server[@"type"];
		if (![type[@"@type"] isEqualToString:@"callServerTypeTelegramReflector"])
			continue;

		NSData *peerTag = [[NSData alloc] initWithBase64EncodedString:type[@"peer_tag"]
															 options:0];
		TGCallReflector *reflector = [[TGCallReflector alloc]
				initWithHost:server[@"ip_address"]
						port:(uint16_t)[server[@"port"] intValue]
					 peerTag:peerTag];
		__weak TGCallReflector *weakReflector = reflector;
		reflector.onPacket = ^(NSData *packet){
			weakSelf.currentReflector = weakReflector;
			[weakSelf inspectReflectorPacket:packet];
		};
		[reflector start];
		[self.reflectors addObject:reflector];

		NSLog(@"TGCall: reflector %ld at %@:%d, our tag %u", (long)++index,
				server[@"ip_address"], [server[@"port"] intValue], reflector.localTag);

		if (!self.reflector){
			self.reflector = reflector;
			self.reflectorHost = server[@"ip_address"];
		}
	}
	[self sendOurCandidates];
}

/// Anything that arrives gets held against the call key both ways round: if it
/// decrypts, the crypto port is right and the packet is real call traffic.
- (void)inspectReflectorPacket:(NSData *)packet {
	const uint8_t *bytes = (const uint8_t *)packet.bytes;
	if (packet.length < 4){
		NSLog(@"TGCall: %lu-byte reflector packet", (unsigned long)packet.length);
		return;
	}
	if (packet.length <= 32){
		NSLog(@"TGCall: reflector service packet, %lu bytes, first %02x%02x%02x%02x",
				(unsigned long)packet.length, bytes[0], bytes[1], bytes[2], bytes[3]);
		return;
	}

	// The header the reflector puts in front of relayed data is not worth
	// guessing at: STUN announces itself with a magic cookie four bytes in, so
	// the payload is found by looking for it.
	static const size_t offsets[] = { 24, 16, 20, 0 };
	for (unsigned i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++){
		size_t offset = offsets[i];
		if (packet.length <= offset + 20)
			continue;
		NSData *payload = [packet subdataWithRange:
				NSMakeRange(offset, packet.length - offset)];
		if ([TGCallStun messageTypeOf:payload] < 0)
			continue;
		// The eight bytes between the tag and the payload decide how a reply is
		// addressed, so they are logged every time rather than once: syslog
		// drops lines under a burst and this one must not be missed.
		// The sender's four bytes sit between the destination tag and the
		// length; an answer goes back to exactly those.
		const uint8_t *raw = (const uint8_t *)packet.bytes;
		if (offset >= 24)
			memcpy(&_currentSenderTag, raw + 16, 4);
		if (offset >= 24)
			NSLog(@"hdr %02x%02x%02x%02x|%02x%02x%02x%02x|%02x%02x%02x%02x ours %08x",
					raw[12], raw[13], raw[14], raw[15],
					raw[16], raw[17], raw[18], raw[19],
					raw[20], raw[21], raw[22], raw[23],
					self.reflector.localTag);
		[self.ice handleRelayedPacket:payload];
		return;
	}

	// Not STUN, so it is either the reflector's own service traffic or media.
	if (packet.length > 32)
		NSLog(@"TGCall: %lu bytes from the reflector, not STUN",
				(unsigned long)packet.length);
}

- (void)setMuted:(BOOL)muted {
	_muted = muted;
	if (_controller)
		_controller->SetMicMute(muted);
}

- (void)teardown {
	self.sentCandidates = NO;
	self.callKey = nil;
	self.signallingSeq = 0;
	self.currentSenderTag = 0;
	self.currentReflector = nil;
	self.peerUfrag = nil;
	self.peerPwd = nil;
	self.localUfrag = nil;
	self.localPwd = nil;
	self.reflectorHost = nil;
	[self.ice stop];
	self.ice = nil;
	for (TGCallReflector *reflector in self.reflectors)
		[reflector stop];
	self.reflectors = nil;
	self.reflector = nil;
	if (_controller){
		_controller->Stop();
		delete _controller;
		_controller = NULL;
	}
	self.establishedAt = nil;
	self.callId = 0;
	[[AVAudioSession sharedInstance] setActive:NO error:nil];
}

@end

// vim:ft=objcpp
