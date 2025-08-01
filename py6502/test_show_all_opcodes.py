#!/usr/bin/env python

from . import asm6502

a = asm6502.asm6502()

print("All the opcodes known by asm6502")

for b in a.hexcodes:
    if a.hexcodes[b][0] == "":
        pass
    else:
        print(f"OPCODE={b:02X}  {a.hexcodes[b][0]}  {a.hexcodes[b][1]}")

print()
print("Alternative Opcode Names")
for b in a.otherhexcodes:
    if a.otherhexcodes[b][0] == "":
        pass
    else:
        print(f"OPCODE={b:02X}  {a.otherhexcodes[b][0]}  {a.otherhexcodes[b][1]}")
