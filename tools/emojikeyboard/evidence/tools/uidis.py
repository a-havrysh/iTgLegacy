import sys, struct
from dsc import *
from capstone import *
from capstone.arm import *

d = DSC('dsc_armv7')
base, path = d.image('UIKit.framework/UIKit')
mo = MachO(d, base)
CLS = objc_classes(d, mo)

SYMS = {}

def load_symtab(imgbase):
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags = struct.unpack(
        '<IIIIIII', d.read(imgbase, 28))
    p = imgbase + 28
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack('<II', d.read(p, 8))
        if cmd == 0x2:
            symoff, nsyms, stroff, strsize = struct.unpack('<IIII', d.read(p + 8, 16))
            try:
                for i in range(nsyms):
                    o = symoff + i * 12
                    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from(
                        '<IBBHI', d.m, o)
                    if n_value and (n_type & 0x0e) == 0x0e:
                        e = d.m.find(b'\x00', stroff + n_strx)
                        nm = d.m[stroff + n_strx:e].decode('utf-8', 'replace')
                        SYMS.setdefault(n_value & ~1, nm)
            except Exception:
                pass
        p += cmdsize

for a, pth in d.images:
    try:
        load_symtab(a)
    except Exception:
        pass

for cn, ca in CLS.items():
    for kind, target in (('-', ca), ('+', metaclass(d, ca))):
        try:
            for nm, ty, imp in class_methods(d, target):
                SYMS[imp & ~1] = '%s[%s %s]' % (kind, cn, nm)
        except Exception:
            pass

def resolve_stub(a):
    try:
        w = struct.unpack('<3I', d.read(a, 12))
    except Exception:
        return None
    if w[0] & 0xfffff000 != 0xe59f0000:
        return None
    disp = w[0] & 0xfff
    off = d.u32(a + 8 + disp)
    ptr = (a + 12 + off) & 0xffffffff
    try:
        v = d.u32(ptr)
    except Exception:
        return None
    return SYMS.get(v & ~1)

IMGRANGE = sorted((a, p) for a, p in d.images)

def imgfor(addr):
    lo = 0
    best = None
    for a, p in IMGRANGE:
        if a <= addr:
            best = p
        else:
            break
    return best

def methods(clsname):
    c = CLS[clsname]
    out = []
    for nm, ty, imp in class_methods(d, c):
        out.append(('-', nm, ty, imp))
    for nm, ty, imp in class_methods(d, metaclass(d, c)):
        out.append(('+', nm, ty, imp))
    return out

def find(clsname, sel):
    for k, nm, ty, imp in methods(clsname):
        if nm == sel:
            return imp
    raise KeyError(clsname + ' ' + sel)

def cfstring(addr):
    try:
        isa, flags, data, length = struct.unpack('<IIII', d.read(addr, 16))
        if not (0x7c0 <= flags <= 0x7f8):
            return None
        if flags & 0x10:
            return d.read(data, length * 2).decode('utf-16-le', 'replace')
        return d.read(data, length).decode('utf-8', 'replace')
    except Exception:
        return None

def describe(v, deref=True):
    parts = []
    if v in SYMS:
        parts.append(SYMS[v])
    if (v & ~1) in SYMS and (v & 1):
        parts.append(SYMS[v & ~1])
    cs = cfstring(v)
    if cs is not None:
        return '@"%s"' % cs.replace('\n', '\\n')
    try:
        n = class_name(d, v)
        if n.isprintable():
            parts.append('class %s' % n)
    except Exception:
        pass
    try:
        s = d.cstr(v)
        if s and len(s) < 100 and all(31 < ord(c) < 127 for c in s):
            parts.append('"%s"' % s)
    except Exception:
        pass
    return ' '.join(parts)

def disasm(imp, n=200, label='', quiet=False):
    thumb = imp & 1
    start = imp & ~1
    code = d.read(start, n * 4 + 64)
    m = Cs(CS_ARCH_ARM, CS_MODE_THUMB if thumb else CS_MODE_ARM)
    m.detail = True
    out = ['==== %s  imp=%#x' % (label, imp)]
    reg = {}
    for i, ins in enumerate(m.disasm(code, start)):
        extra = ''
        mn = ins.mnemonic
        ops = ins.operands
        if mn in ('movw', 'mov', 'movs') and len(ops) == 2 and ops[0].type == ARM_OP_REG and ops[1].type == ARM_OP_IMM:
            reg[ops[0].reg] = ops[1].imm & 0xffff
        elif mn == 'movt' and len(ops) == 2 and ops[1].type == ARM_OP_IMM:
            r = ops[0].reg
            reg[r] = (reg.get(r, 0) & 0xffff) | ((ops[1].imm & 0xffff) << 16)
        elif mn == 'add' and len(ops) == 2 and ops[1].type == ARM_OP_REG and ops[1].reg == ARM_REG_PC:
            r = ops[0].reg
            if r in reg:
                reg[r] = (reg[r] + ins.address + 4) & 0xffffffff
                extra = ' ; addr=%#x %s' % (reg[r], describe(reg[r]))
        elif mn.startswith('ldr') and len(ops) == 2 and ops[1].type == ARM_OP_MEM:
            mem = ops[1].mem
            if mem.base == ARM_REG_PC:
                ea = ((ins.address + 4) & ~3) + mem.disp
                try:
                    val = d.u32(ea)
                    reg[ops[0].reg] = val
                    extra = ' ; =%#x %s' % (val, describe(val))
                except Exception:
                    pass
            elif mem.base in reg and mem.index == 0:
                ea = reg[mem.base] + mem.disp
                try:
                    val = d.u32(ea)
                    reg[ops[0].reg] = val
                    extra = ' ; [%#x]=%#x %s' % (ea, val, describe(val))
                except Exception:
                    reg.pop(ops[0].reg, None)
            else:
                reg.pop(ops[0].reg, None)
        elif mn.startswith('str') and len(ops) == 2 and ops[1].type == ARM_OP_MEM:
            mem = ops[1].mem
            if mem.base in reg and mem.index == 0:
                extra = ' ; store->%#x %s' % (reg[mem.base] + mem.disp,
                                              SYMS.get(reg[mem.base] + mem.disp, ''))
        if mn in ('bl', 'blx', 'b', 'b.w', 'bl.w') and ops and ops[0].type == ARM_OP_IMM:
            tgt = ops[0].imm
            nm2 = SYMS.get(tgt & ~1) or resolve_stub(tgt & ~1)
            extra += ' ; -> %s' % (nm2 or '')
            if mn.startswith('bl'):
                if ARM_REG_R1 in reg:
                    s = describe(reg[ARM_REG_R1])
                    if s:
                        extra += '  sel/arg1=%s' % s
                for rr in (ARM_REG_R0, ARM_REG_R2, ARM_REG_R3):
                    pass
                reg = {k: v for k, v in reg.items() if k not in
                       (ARM_REG_R0, ARM_REG_R1, ARM_REG_R2, ARM_REG_R3, ARM_REG_R12)}
        out.append('%08x  %-8s %-32s%s' % (ins.address, mn, ins.op_str, extra))
        if i >= n:
            break
    txt = '\n'.join(out)
    if not quiet:
        print(txt)
        print()
    return txt

if __name__ == '__main__':
    if sys.argv[1] == '@':
        disasm(int(sys.argv[2], 16), int(sys.argv[3]) if len(sys.argv) > 3 else 200, sys.argv[2])
    elif len(sys.argv) == 2:
        for k, nm, ty, imp in methods(sys.argv[1]):
            print('%s[%s %s]  %#x  %s' % (k, sys.argv[1], nm, imp, ty))
    else:
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 200
        disasm(find(sys.argv[1], sys.argv[2]), n, '%s %s' % (sys.argv[1], sys.argv[2]))
