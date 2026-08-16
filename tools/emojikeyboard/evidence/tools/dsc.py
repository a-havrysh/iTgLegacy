import struct, mmap, sys, bisect

class DSC:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        m = self.m
        assert m[:8] == b'dyld_v1 '
        self.magic = m[:16].rstrip(b'\x00').decode()
        (self.mappingOffset, self.mappingCount, self.imagesOffset,
         self.imagesCount) = struct.unpack_from('<IIII', m, 0x10)
        self.mappings = []
        for i in range(self.mappingCount):
            off = self.mappingOffset + i*32
            addr, size, foff, maxp, initp = struct.unpack_from('<QQQII', m, off)
            self.mappings.append((addr, size, foff, maxp, initp))
        self.images = []
        for i in range(self.imagesCount):
            off = self.imagesOffset + i*32
            addr, mtime, inode, pathoff, pad = struct.unpack_from('<QQQII', m, off)
            end = m.find(b'\x00', pathoff)
            self.images.append((addr, m[pathoff:end].decode()))

    def off(self, vmaddr):
        for addr, size, foff, _, _ in self.mappings:
            if addr <= vmaddr < addr + size:
                return foff + (vmaddr - addr)
        raise KeyError(hex(vmaddr))

    def vm(self, fileoff):
        for addr, size, foff, _, _ in self.mappings:
            if foff <= fileoff < foff + size:
                return addr + (fileoff - foff)
        raise KeyError(hex(fileoff))

    def read(self, vmaddr, n):
        o = self.off(vmaddr)
        return self.m[o:o+n]

    def u32(self, vmaddr):
        return struct.unpack_from('<I', self.m, self.off(vmaddr))[0]

    def ptr(self, vmaddr):
        return self.u32(vmaddr)

    def cstr(self, vmaddr):
        o = self.off(vmaddr)
        e = self.m.find(b'\x00', o)
        return self.m[o:e].decode('utf-8', 'replace')

    def image(self, needle):
        for addr, path in self.images:
            if needle in path:
                return addr, path
        raise KeyError(needle)

class MachO:
    def __init__(self, dsc, base):
        self.dsc = dsc
        self.base = base
        magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags = struct.unpack(
            '<IIIIIII', dsc.read(base, 28))
        assert magic == 0xfeedface, hex(magic)
        self.segments = []
        self.sections = {}
        p = base + 28
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack('<II', dsc.read(p, 8))
            if cmd == 0x1:  # LC_SEGMENT
                d = dsc.read(p, cmdsize)
                segname = d[8:24].rstrip(b'\x00').decode()
                vmaddr, vmsize, fileoff, filesize, maxp, initp, nsects, fl = struct.unpack_from('<IIIIIIII', d, 24)
                self.segments.append((segname, vmaddr, vmsize))
                for i in range(nsects):
                    so = 56 + i*68
                    sectname = d[so:so+16].rstrip(b'\x00').decode()
                    sg = d[so+16:so+32].rstrip(b'\x00').decode()
                    saddr, ssize, soff = struct.unpack_from('<III', d, so+32)
                    self.sections[(sg, sectname)] = (saddr, ssize)
            p += cmdsize

    def sect(self, seg, name):
        return self.sections[(seg, name)]

def objc_classes(dsc, mo):
    out = {}
    try:
        addr, size = mo.sect('__DATA', '__objc_classlist')
    except KeyError:
        return out
    for i in range(size // 4):
        cls = dsc.u32(addr + i*4)
        name = class_name(dsc, cls)
        out[name] = cls
    return out

def class_ro(dsc, cls):
    isa, superclass, cache, vtable, data = struct.unpack('<IIIII', dsc.read(cls, 20))
    return data & ~3

def class_name(dsc, cls):
    ro = class_ro(dsc, cls)
    flags, start, size, ivarlayout, name = struct.unpack('<IIIII', dsc.read(ro, 20))
    return dsc.cstr(name)

def class_methods(dsc, cls):
    ro = class_ro(dsc, cls)
    d = dsc.read(ro, 40)
    baseMethods = struct.unpack_from('<I', d, 20)[0]
    res = []
    if baseMethods:
        entsize, count = struct.unpack('<II', dsc.read(baseMethods, 8))
        entsize &= ~3
        for i in range(count):
            nm, types, imp = struct.unpack('<III', dsc.read(baseMethods + 8 + i*entsize, 12))
            res.append((dsc.cstr(nm), dsc.cstr(types), imp))
    return res

def metaclass(dsc, cls):
    return struct.unpack('<I', dsc.read(cls, 4))[0]

if __name__ == '__main__':
    d = DSC(sys.argv[1])
    print(d.magic, 'mappings:')
    for a, s, o, mp, ip in d.mappings:
        print('  vm %08x size %9d off %9d prot %d/%d' % (a, s, o, mp, ip))
    print('images:', d.imagesCount)
