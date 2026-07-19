//
// TGCallCrypto - the packet crypto tgcalls uses on a call.
//
// Ported from tgcalls (EncryptedConnection.cpp, CryptoHelper.cpp), which is
// open source; the algorithm is small and the WebRTC types around it are not
// part of it. OpenSSL does the work, as it does in the original.
//
// Layout of an encrypted packet:
//
//   [0..16)   msgKey
//   [16..)    AES-256-CTR ciphertext of: be32 seq, then the payload
//
// with the key and iv derived from the 256-byte call key and msgKey, and
// msgKey itself being a slice of SHA256(keyPart || plaintext) - so decrypting
// verifies as a side effect: if the digest does not match, the packet is not
// ours.
//
#ifndef TG_CALL_CRYPTO_H
#define TG_CALL_CRYPTO_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// `key` is the 256-byte call key from TDLib. `outgoing` is whether we placed
/// the call, and `signaling` selects the signaling keyspace over the media one
/// - both shift which part of the key is used.
///
/// Returns the payload length written to `out` (which needs `length` bytes),
/// or -1 when the packet is not for us. `seq` receives the packet counter.
int TGCallDecryptPacket(const uint8_t *key, int outgoing, int signaling,
                        const uint8_t *packet, size_t length,
                        uint8_t *out, uint32_t *seq);

/// The inverse. `out` needs `length + 20` bytes; returns bytes written.
int TGCallEncryptPacket(const uint8_t *key, int outgoing, int signaling,
                        const uint8_t *payload, size_t length,
                        uint32_t seq, uint8_t *out);

#ifdef __cplusplus
}
#endif

#endif
