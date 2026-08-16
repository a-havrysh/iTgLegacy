from fontTools.ttLib import newTable
from fontTools.ttLib.tables import otTables as T

EOT, OOB, DEL, EOL = 0, 1, 2, 3
FIRST_CLASS = 4


def build_ligature_state_table(seqs, gid):
    inputs = sorted({g for seq, _ in seqs for g in seq})
    cls = {g: FIRST_CLASS + i for i, g in enumerate(inputs)}
    nclasses = FIRST_CLASS + len(inputs)

    stx = T.AATStateTable()
    stx.GlyphClasses = dict(cls)
    stx.GlyphClassCount = nclasses
    stx.LigComponents = [0] + list(range(len(seqs)))
    stx.Ligatures = [lig for _, lig in seqs]
    stx.PerGlyphLookups = []

    states = []

    def new_state():
        states.append(T.AATState())
        return len(states) - 1

    START = new_state()
    new_state()

    trie = {}
    for k, (seq, _lig) in enumerate(seqs):
        node = trie
        for g in seq:
            node = node.setdefault(g, {})
        if "#" in node:
            raise ValueError("duplicate sequence in subtable: %r" % (seq,))
        node["#"] = (k, seq)

    def push(next_state):
        a = T.LigatureMorphAction()
        a.SetComponent = True
        a.DontAdvance = False
        a.NewState = next_state
        return a

    def fire(k, seq):
        a = T.LigatureMorphAction()
        a.SetComponent = True
        a.DontAdvance = False
        a.NewState = START
        acts = []
        for i, g in enumerate(reversed(seq)):
            la = T.LigAction()
            la.Store = i == len(seq) - 1
            la.GlyphIndexDelta = ((1 + k) - gid(g)) if i == 0 else -gid(g)
            acts.append(la)
        a.Actions = acts
        return a

    def walk(node, state):
        for g, child in node.items():
            if g == "#":
                continue
            if "#" in child:
                k, seq = child["#"]
                states[state].Transitions[cls[g]] = fire(k, seq)
            else:
                nxt = new_state()
                states[state].Transitions[cls[g]] = push(nxt)
                walk(child, nxt)

    walk(trie, START)

    for si, state in enumerate(states):
        for c in range(nclasses):
            if c in state.Transitions:
                continue
            a = T.LigatureMorphAction()
            a.SetComponent = False
            if c == DEL:
                a.NewState = si
                a.DontAdvance = False
            else:
                a.NewState = START
                a.DontAdvance = si != START and c not in (EOT, OOB)
            state.Transitions[c] = a

    stx.States = states
    return stx


def make_ligature_subtable(stx):
    lig = T.LigatureMorph()
    lig.StateTable = stx
    sub = T.MorxSubtable()
    sub.MorphType = 2
    sub.ProcessingOrder = "LogicalOrder"
    sub.TextDirection = "Horizontal"
    sub.Reserved = 0
    sub.SubFeatureFlags = 1
    sub.SubStruct = lig
    return sub


def group_by_length_desc(seqs):
    groups = {}
    for seq, lig in seqs:
        groups.setdefault(len(seq), []).append((seq, lig))
    return [groups[n] for n in sorted(groups, reverse=True)]


def make_morx(seqs, gid):
    chain = T.MorxChain()
    chain.DefaultFlags = 1
    chain.MorphFeature = []
    for ft, fs, en, di in ((1, 0, 1, 0xFFFFFFFF), (0, 1, 0, 0xFFFFFFFF)):
        f = T.MorphFeature()
        f.FeatureType, f.FeatureSetting = ft, fs
        f.EnableFlags, f.DisableFlags = en, di
        chain.MorphFeature.append(f)
    chain.MorphSubtable = [
        make_ligature_subtable(build_ligature_state_table(g, gid))
        for g in group_by_length_desc(seqs)
    ]

    morx = T.morx()
    morx.Version = 2
    morx.Reserved = 0
    morx.MorphChain = [chain]
    tbl = newTable("morx")
    tbl.table = morx
    return tbl
