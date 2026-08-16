import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVIDENCE = os.path.join(HERE, os.pardir, "evidence", "ios6_emoji_tables.json")


def decode(units):
    out = []
    i = 0
    while i < len(units):
        u = units[i]
        if 0xD800 <= u <= 0xDBFF and i + 1 < len(units):
            out.append(0x10000 + ((u - 0xD800) << 10) + (units[i + 1] - 0xDC00))
            i += 2
        else:
            out.append(u)
            i += 1
    return "".join(chr(c) for c in out)


def cstring(text):
    return '"' + "".join("\\x%02x" % b for b in text.encode("utf-8")) + '"'


def main():
    target = sys.argv[1]
    data = json.load(open(EVIDENCE, encoding="utf-8"))

    per_type = {}
    for cat in data["categories"]:
        slots = []
        for slot in cat.get("slot_units", []):
            units = [int(u, 16) for u in slot]
            units = [u for u in units if u]
            slots.append(decode(units) if units else None)
        extras = [decode([int(u, 16) for u in seq])
                  for seq in cat.get("extra_sequences", [])]
        for text in extras:
            for i, value in enumerate(slots):
                if value is None:
                    slots[i] = text
                    break
        per_type[cat["type"]] = [s for s in slots if s]

    lines = ["#ifndef EK_STOCK_TABLE_H", "#define EK_STOCK_TABLE_H", ""]
    for t in range(6):
        entries = per_type.get(t, [])
        lines.append("static const char *kEKStock%d[] = {" % t)
        for text in entries:
            lines.append("\t%s," % cstring(text))
        lines.append("\tNULL")
        lines.append("};")
        lines.append("")
    lines.append("static const char **kEKStock[6] = {")
    lines.append("\t" + ", ".join("kEKStock%d" % t for t in range(6)))
    lines.append("};")
    lines.append("")
    lines.append("#endif")

    with open(target, "w", encoding="ascii") as fh:
        fh.write("\n".join(lines) + "\n")

    print("stocktable: %s (%s)"
          % (target, ", ".join("type %d: %d" % (t, len(per_type.get(t, [])))
                               for t in range(6))))


if __name__ == "__main__":
    main()
