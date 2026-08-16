import sys, struct, hmac, hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

src, dst, keyhex = sys.argv[1], sys.argv[2], sys.argv[3]
kb = bytes.fromhex(keyhex)
assert len(kb) == 36, len(kb)
aeskey, hmackey = kb[:16], kb[16:]

f = open(src, 'rb')
hdr = f.read(0x60)
assert hdr[:8] == b'encrcdsa'
version, ivsize = struct.unpack('>II', hdr[8:16])
blocksize, = struct.unpack('>I', hdr[0x34:0x38])
datasize, dataoffset = struct.unpack('>QQ', hdr[0x38:0x48])
print('v%d ivsize=%d blocksize=%d datasize=%d dataoffset=%d' % (version, ivsize, blocksize, datasize, dataoffset), file=sys.stderr)

base = hmac.new(hmackey, digestmod=hashlib.sha1)
f.seek(dataoffset)
out = open(dst, 'wb')
alg = algorithms.AES(aeskey)
n = 0
remaining = datasize
while remaining > 0:
    chunk = f.read(blocksize)
    if not chunk:
        break
    h = base.copy()
    h.update(struct.pack('>I', n))
    iv = h.digest()[:16]
    dec = Cipher(alg, modes.CBC(iv)).decryptor()
    plain = dec.update(chunk) + dec.finalize()
    take = min(len(plain), remaining)
    out.write(plain[:take])
    remaining -= take
    n += 1
    if n % 200000 == 0:
        print('  %d blocks' % n, file=sys.stderr)
out.close()
print('done blocks=%d' % n, file=sys.stderr)
