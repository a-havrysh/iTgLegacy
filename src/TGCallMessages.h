//
// TGCallMessages - the message framing tgcalls puts inside an encrypted packet.
//
// A decrypted packet is a sequence number followed by messages. The first byte
// of each is its type; 0xFE is an empty message that only carries the sequence
// number, 0xFF is an acknowledgement, and anything else is a real message whose
// body follows. Between messages comes another four-byte sequence number.
//
// Types are from tgcalls/Message.h: 1 candidates, 2 video formats, 4 remote
// media state, 5 audio data - and audio data is an RTP packet, which is what
// makes speaking this protocol possible without WebRTC.
//
#import <Foundation/Foundation.h>

extern const uint8_t TGCallMessageCandidates;   // 1
extern const uint8_t TGCallMessageMediaState;   // 4
extern const uint8_t TGCallMessageAudioData;    // 5

@interface TGCallMessages : NSObject

/// Split a decrypted packet into messages. Each entry has "type" (NSNumber),
/// "body" (NSData) and "seq" (NSNumber) - the sequence number that message
/// arrived under, which is what an acknowledgement refers to.
+ (NSArray *)parsePacket:(NSData *)plaintext seq:(uint32_t)packetSeq;

/// An acknowledgement for a message the peer sent: an empty message, then the
/// sequence number being confirmed, then the ack marker.
+ (NSData *)ackForSeq:(uint32_t)seq;

/// YES when a sequence number asks to be acknowledged.
+ (BOOL)seqRequiresAck:(uint32_t)seq;

/// The candidate strings and ICE credentials out of a candidates message.
/// Keys: "candidates" (NSArray of NSString), "ufrag", "pwd".
+ (NSDictionary *)parseCandidates:(NSData *)body;

/// One message, ready to be encrypted. The sequence number is not written
/// here: the crypto layer puts it in front of the plaintext, and writing it
/// twice makes the peer read our second copy as a message type and drop the
/// packet.
+ (NSData *)messageWithType:(uint8_t)type body:(NSData *)body;

/// The sequence number as it goes on the wire. Bit 30 asks for an
/// acknowledgement, bit 31 says the packet holds exactly one message.
+ (uint32_t)markSeq:(uint32_t)seq requiresAck:(BOOL)requiresAck;

/// The body of a candidates message: the list, then our ICE credentials.
+ (NSData *)candidatesBody:(NSArray *)candidates ufrag:(NSString *)ufrag pwd:(NSString *)pwd;

@end
