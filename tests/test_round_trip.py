#!/usr/bin/env python3
"""
Round-trip test for py6502 assembler/disassembler.
"""

import os
import tempfile

import pytest

ASM_FIXTURES = [
    # Simple branch with offset
    (
        0x8000,
        """
    lda #$01
    bne -$02
    sta $0200
    rts
    """,
    ),
    # Branch forward with label
    (
        0x9000,
        """
    nop
    bpl next
    nop
    nop
    next:
    nop
    """,
    ),
    # Branch backward with label
    (
        0xA000,
        """
    start:
    nop
    nop
    bmi start
    nop
    """,
    ),
    # Forward branch
    (
        0x9000,
        """
    nop
    bpl end
    nop
    nop
    nop
end: jsr do_nothing
    brk
    do_nothing:
    rts
    """,
    ),
    # Backward branch
    (
        0xA000,
        """
    nop
    nop
    bmi -$04
    nop
    """,
    ),
    # Indexed and indirect
    (
        0xB000,
        """
    lda ($10,x)
    sta ($20),y
    ldx #$05
    stx $30,y
    """,
    ),
    # Absolute and accumulator
    (
        0xC000,
        """
    lda $1234
    asl A
    asl
    rol $1234,x
    ror $1234
    """,
    ),
    # Absolute zero-page with .a suffix
    (
        0xD000,
        """
    sta $00.a
    lda $10.a,x
    ldy $20.a,y
    """,
    ),
]


@pytest.mark.parametrize("org, asm_src", ASM_FIXTURES)
def test_round_trip(org, asm_src):
    with tempfile.TemporaryDirectory() as tmpdir:
        asm_path = os.path.join(tmpdir, "test.asm")
        bin_path = os.path.join(tmpdir, "test.bin")

        # Write original assembly
        with open(asm_path, "w") as f:
            f.write(f"org ${org:04X}\n" + asm_src)

        import subprocess

        # Assemble to binary using -b (ignore hex output)
        ret = subprocess.run(
            ["python3", "py6502/cli_asm6502.py", asm_path, "-b", bin_path]
        )
        assert ret.returncode == 0, "Assembler failed"

        ret2 = subprocess.run(
            ["python3", "py6502/cli_asm6502.py", asm_path, "-b", bin_path + ".2"]
        )
        assert ret2.returncode == 0, "Re-assembler failed"

        # Get actual binary size
        bin_size = os.path.getsize(bin_path)

        # Use org directly for start address
        start_addr = str(org)
        length = str(bin_size)

        # Disassemble original binary to reassemblable assembly using subprocess
        disasm_asm_path = os.path.join(tmpdir, "disasm.asm")
        ret3 = subprocess.run(
            [
                "python3",
                "py6502/cli_dis6502.py",
                bin_path,
                "-s",
                start_addr,
                "-l",
                length,
                "--reassemble",
                "-o",
                disasm_asm_path,
            ]
        )
        assert ret3.returncode == 0, "Disassembler failed"

        # Re-assemble the disassembled assembly to binary
        disasm_bin_path = os.path.join(tmpdir, "disasm.bin")
        ret4 = subprocess.run(
            ["python3", "py6502/cli_asm6502.py", disasm_asm_path, "-b", disasm_bin_path]
        )
        assert ret4.returncode == 0, "Re-assembly from disassembly failed"

        # Compare original and round-tripped binaries byte-for-byte
        with open(bin_path, "rb") as f1, open(disasm_bin_path, "rb") as f2:
            orig_bytes = f1.read()
            roundtrip_bytes = f2.read()
        assert orig_bytes == roundtrip_bytes, (
            "Round-trip binary does not match original"
        )
