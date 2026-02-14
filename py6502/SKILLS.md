# SKILLS: Iterative Disassembly and Improvement of 6502 Binaries

## Philosophy and Goal

The goal is to transform a raw 6502 binary blob into literate, human-readable assembly source code that:
1. **Assembles byte-for-byte identically** to the original binary
2. Is **human-readable** with meaningful labels, comments, and documentation
3. Represents **literate programming** - code that tells a story and can be understood

This is an iterative process: **Assemble → Diff → Improve**

Every change must preserve binary identity. This constraint ensures we understand what the code actually does, not what we think it does.

## The Core Loop

```
┌─────────────────────────────────────────┐
│  1. Make improvement to assembly        │
│  2. Reassemble to binary                │
│  3. Diff against original               │
│  4. If identical: commit, goto 1        │
│  5. If different: debug and fix, goto 2 │
└─────────────────────────────────────────┘
```

**Never break the round-trip.** If you can't maintain byte-for-byte identity, you don't understand the code well enough yet.

## Prerequisites

### Tools Required
- `a6502` - Assembler (py6502/cli_asm6502.py)
- `d6502` - Disassembler (py6502/cli_dis6502.py)
- `diff6502` - Binary comparison (py6502/cli_diff6502.py)
- `analyze6502` - Control flow analysis (py6502/analyzer6502.py)
- Python 3.x
- Text editor

### Knowledge Required
- Basic 6502 instruction set
- Addressing modes (immediate, zero-page, absolute, indexed, indirect, relative)
- Understanding of the .a suffix for explicit absolute addressing
- Familiarity with hex and binary
- Understanding of 6502 vs 65C02 differences
- Apple II memory map and conventions (if working with Apple II binaries)

### Understanding the Tools

**Assembler (a6502):**
```
python3 py6502/cli_asm6502.py input.asm -b output.bin [--verify original.bin]
```
- Reads assembly source
- Produces binary output
- Supports labels, directives, comments
- `--verify` flag automatically checks round-trip

**Disassembler (d6502):**
```
python3 py6502/cli_dis6502.py input.bin -s START_ADDR -l LENGTH --reassemble -o output.asm
```
- Reads binary
- Produces assembly (with --reassemble flag for round-trip fidelity)
- Needs start address and length

**Binary Diff Tool (diff6502):**
```
python3 py6502/cli_diff6502.py file1.bin file2.bin -s START_ADDR [-v]
```
- Compares two binary files byte-by-byte
- Shows differences with context and address information
- Essential for debugging round-trip issues
- Exit code 0 if identical, 1 if different

**Analyzer (analyze6502):**
```
python3 py6502/analyzer6502.py binary.bin -s START_ADDR [-e ENTRY_POINT] [-o output.asm]
```
- Control flow analysis from entry points
- Separates code from data
- Generates improved disassembly with labels
- Identifies subroutines and strings

## Phase 1: Initial Disassembly and Round-Trip Verification

### Step 1.1: Gather Binary Information

Before disassembling, you need:
1. **Binary file** - The raw bytes
2. **Start address** - Where this code lives in 6502 memory space (often $8000, $C000, $0803, etc.)
3. **Length** - How many bytes to disassemble
4. **Entry point** - Where execution begins (if known)

For Apple II binaries:
- Check for 4-byte header: load_addr_lo, load_addr_hi, length_lo, length_hi
- Reset vector at $FFFC/$FFFD points to main entry
- Common load addresses: $0801 (BASIC), $0803 (BASIC continuation), $0800-$0900 (utilities), $1000+, $6000+, $8000, $C000

### Step 1.2: Initial Disassembly

```bash
# Example: Disassemble a binary that loads at $0803, 4686 bytes
python3 py6502/cli_dis6502.py game.bin -s 2051 -l 4686 --reassemble -o game_v1.asm
```

The `--reassemble` flag is **critical**. It ensures:
- Relative branches use numeric offsets, not labels (initially)
- Zero-page absolute addressing uses `.a` suffix where needed
- Byte-for-byte reassembly is possible
- Invalid opcodes are emitted as `db` directives

### Step 1.3: Verify Round-Trip

```bash
# Reassemble the disassembled code with automatic verification
python3 py6502/cli_asm6502.py game_v1.asm -b game_test.bin --verify game_original.bin

# This will assemble and automatically compare, showing:
# ✓ ROUND-TRIP VERIFICATION SUCCESSFUL!
# OR
# ✗ ROUND-TRIP VERIFICATION FAILED! with details

# You can also manually compare with the diff tool:
python3 py6502/cli_diff6502.py game_original.bin game_test.bin -s 0x0803
```

**If they differ, you have a problem:**
- Disassembler bug
- Addressing mode issue
- Data interpreted as code
- Branch offset calculation error

**Debug strategies:**
1. Use the diff tool to find the first byte that differs:
   ```bash
   python3 py6502/cli_diff6502.py original.bin test.bin -s START_ADDR
   ```
2. The diff tool will show you:
   - Exact offset and address of difference
   - Original vs assembled byte values
   - Context (surrounding bytes)
3. Look at the assembly around that address
4. Common issues:
   - Zero-page vs absolute addressing (missing or wrong `.a` suffix)
   - Branch offsets incorrect
   - Data bytes disassembled as instructions
   - 65C02 vs NMOS 6502 opcode differences

### Step 1.4: Common Round-Trip Issues

**Issue: Zero-page addressing optimization**
```
; Original binary has: 8D 00 00 (STA $0000 - absolute)
; Assembler produces:   85 00    (STA $00   - zero-page)
```
**Solution:** Use `.a` suffix to force absolute addressing:
```
sta $00.a    ; Forces 3-byte absolute addressing
lda $10.a,x  ; Indexed modes need .a too
```

**Issue: Relative branches**
```
; Disassembler should emit absolute addresses that assemble to correct offsets
bne $8050    ; Assembler calculates offset automatically
```

**Issue: Data vs Code**
If data is disassembled as code, the instructions won't reassemble correctly.
Solution: Mark data regions with `db` directive, or use analyzer6502.py to separate code from data.

**Issue: 65C02 undefined opcodes**
The 65C02 treats undefined opcodes as NOPs. If code contains these, they won't be in the opcode table:
```
$02, $22, $42, $62, $82, $C2, $E2: 2-byte NOPs
$03, $07, $0B, $0F, $13, $17, $1B, $1F, etc.: 1-byte NOPs
```
Solution: Emit as `db` directives, or extend the disassembler to recognize them.

## Phase 2: Code and Data Separation

Once round-trip works, identify what's code and what's data.

### Step 2.1: Use Control Flow Analysis

```bash
python3 py6502/analyzer6502.py binary.bin -s 0x0803 -e 0x0803 -o improved.asm
```

The analyzer will:
- Trace execution from entry points
- Mark reachable instructions as CODE
- Mark everything else as DATA
- Find strings and identify subroutines
- Generate improved disassembly with labels

### Step 2.2: Find Entry Points

**Check reset vector:**
```python
# Read bytes $FFFC and $FFFD from binary
reset_low = data[0xFFFC - base_address]
reset_high = data[0xFFFD - base_address]
entry_point = reset_low | (reset_high << 8)
```

**Manual tracing:** Start at the load address or known entry point, trace through branches and jumps.

### Step 2.3: Mark Data Regions

Once you identify data, replace disassembled instructions with data directives:

**Before:**
```
8100: 48 45 4C 4C 4F  ; PHA / EOR $4C / etc (nonsense code)
```

**After:**
```
msg_hello:
    str "HELLO"
```

**Or for binary data:**
```
sprite_data:
    db $3C, $42, $81, $81, $81, $42, $3C, $00
```

**Verify round-trip after each change!**

### Step 2.4: Data Pattern Recognition

Common data patterns:
- **Strings:** ASCII text (often terminated with $00 or high-bit set)
- **Lookup tables:** Sequential byte/word values
- **Pointers:** 16-bit addresses (lo/hi byte pairs)
- **Sprite/graphics data:** Bitmap patterns
- **Music/sound data:** Structured sequences
- **Pointer tables:** Arrays of addresses pointing to strings or routines

## Phase 3: Labeling and Structure

Now make the code navigable with meaningful labels.

### Step 3.1: Auto-Generate Labels

First pass: mechanical labels for all jump/branch targets:

**Before:**
```
8000: 20 50 80    jsr $8050
8003: 4C 00 80    jmp $8000
...
8050: A9 01       lda #$01
8052: 60          rts
```

**After:**
```
    org $8000
L_8000:
    jsr L_8050
    jmp L_8000

L_8050:
    lda #$01
    rts
```

**Label all:**
- JSR targets (subroutines)
- JMP targets (gotos)
- Branch targets (conditionals)
- Data regions
- Indirect jump tables

### Step 3.2: Convert Addresses to Labels

Replace hardcoded addresses with label references:

**Before:**
```
8000: 20 50 80    jsr $8050
8010: AD 00 20    lda $2000
8020: 8D 00 04    sta $0400
```

**After:**
```
    org $8000
    jsr init_screen
    lda data_table
    sta SCREEN_BASE

init_screen:
    ; ... code ...

    org $2000
data_table:
    db $00

SCREEN_BASE = $0400
```

**Verify round-trip!** Labels must resolve to same addresses.

### Step 3.3: Identify Subroutines

A subroutine is code that:
- Is reached by JSR
- Ends with RTS
- May have multiple exit points (multiple RTS)

Mark subroutines clearly:
```
; ============================================
; Subroutine: init_screen
; Called from: $8000, $8100
; Purpose: Clear screen to spaces
; ============================================
init_screen:
    lda #$00
    rts
```

## Phase 4: Semantic Understanding and Documentation

Now add human meaning to the code.

### Step 4.1: Rename Labels to Meaningful Names

Replace mechanical labels with descriptive names:

**Naming conventions:**
- Subroutines: verb_noun (e.g., `print_string`, `init_screen`, `update_sprite`)
- Labels: noun or adjective_noun (e.g., `loop_start`, `done`, `error`)
- Constants: UPPER_CASE (e.g., `SCREEN_WIDTH`, `MAX_SPRITES`)
- Variables: lowercase or mixed (e.g., `player_x`, `score`)

### Step 4.2: Document Zero-Page Usage

Zero-page is prime real estate. Document it clearly:

```
; ============================================
; Zero-Page Memory Map
; ============================================
ZP_TEMP_A       = $00   ; Temporary storage A
ZP_TEMP_B       = $01   ; Temporary storage B
ZP_LOOP_CTR     = $02   ; Loop counter
ZP_STR_PTR_LO   = $10   ; String pointer (low byte)
ZP_STR_PTR_HI   = $11   ; String pointer (high byte)
ZP_SCREEN_X     = $20   ; Current screen X position
ZP_SCREEN_Y     = $21   ; Current screen Y position
```

### Step 4.3: Add Inline Comments

Comment non-obvious instructions:

```
init_screen:
    lda #$00
    tax                 ; X = 0 (loop counter)
.clear_loop:
    sta SCREEN_BASE,x   ; Clear screen byte
    sta SCREEN_BASE+256,x
    sta SCREEN_BASE+512,x
    sta SCREEN_BASE+768,x
    inx
    bne .clear_loop     ; Loop 256 times
    rts
```

### Step 4.4: Add Block Comments for Subroutines

Document what each subroutine does:

```
; ============================================
; Subroutine: print_string
; ============================================
; Purpose: Print null-terminated string to screen
; 
; Input:
;   ZP_STR_PTR_LO/HI - Pointer to string
;   ZP_SCREEN_X      - Starting X position
;   ZP_SCREEN_Y      - Starting Y position
;
; Output:
;   ZP_SCREEN_X      - Updated to end position
;
; Destroys: A, Y
; Preserves: X
; ============================================
print_string:
    ldy #$00
.loop:
    lda (ZP_STR_PTR_LO),y
    beq .done           ; Exit on null terminator
    jsr print_char
    iny
    bne .loop
.done:
    rts
```

### Step 4.5: Identify Common 6502 Patterns

**Pattern: 16-bit addition**
```
; Add 16-bit value to pointer
add_to_pointer:
    clc
    lda ZP_PTR_LO
    adc #$40            ; Add offset low byte
    sta ZP_PTR_LO
    lda ZP_PTR_HI
    adc #$00            ; Add carry to high byte
    sta ZP_PTR_HI
```

**Pattern: Indirect indexed addressing for tables**
```
; Y = sprite number
; Load sprite X position
    lda sprite_x_table,y
    sta ZP_SPRITE_X
```

**Pattern: Bit masking**
```
; Test bit 7 of status byte
    lda status_byte
    bmi negative_flag_set  ; Branch if bit 7 = 1
    ; ... bit 7 is 0
```

**Pattern: Table-driven dispatch**
```
; A = command number
dispatch:
    asl                    ; Multiply by 2 (word addresses)
    tax
    lda command_table+1,x
    pha
    lda command_table,x
    pha
    rts                    ; "Jump" via RTS
```

## Phase 5: Advanced Abstractions with Python Macros

For complex data or repetitive patterns, use Python to generate assembly.

### Step 5.1: Understanding Python Macro Concept

The idea: embed Python code that generates assembly at assemble-time.

**Conceptual syntax:**
```
.python
# Python code here
# Output assembly via print()
.endpython
```

This requires assembler enhancement to:
1. Detect `.python` / `.endpython` blocks
2. Execute Python code in safe context
3. Capture stdout as assembly lines
4. Continue assembling

### Step 5.2: Example - Generate Sine Table

**With Python macro:**
```
sine_table:
.python
import math
for i in range(256):
    value = int(128 + 127 * math.sin(i * 2 * math.pi / 256))
    print(f"    db ${value:02X}")
.endpython
```

### Step 5.3: Example - Lookup Table Generation

```
; Multiplication table for * 40 (screen row calculation)
mult_40_table:
.python
for i in range(256):
    value = i * 40
    lo = value & 0xFF
    hi = (value >> 8) & 0xFF
    print(f"    db ${lo:02X}, ${hi:02X}  ; {i} * 40")
.endpython
```

### Step 5.4: Pseudo-Opcodes (Custom Directives)

Define new assembler directives for common patterns:

**Example: .byte16 for 16-bit values**
```
; Instead of:
    lda #<value
    sta ZP_PTR_LO
    lda #>value
    sta ZP_PTR_HI

; Use:
.byte16 ZP_PTR_LO, value
```

## Phase 6: Organizing Large Disassemblies

### Step 6.1: Split Into Multiple Files

Organize by functional area:

```
main.asm        - Entry point and main loop
graphics.asm    - Screen drawing routines
input.asm       - Keyboard/joystick handling
sound.asm       - Sound effects and music
data.asm        - Lookup tables and constants
```

Use `.include` directive (requires assembler enhancement):
```
; main.asm
    org $8000

.include "graphics.asm"
.include "input.asm"
.include "sound.asm"
.include "data.asm"

start:
    jsr init_graphics
    jsr init_sound
main_loop:
    jsr handle_input
    jsr update_screen
    jmp main_loop
```

### Step 6.2: Memory Map Documentation

Create comprehensive memory map:

```
; ============================================
; Memory Map
; ============================================
; $0000-$00FF : Zero-page RAM
; $0100-$01FF : Stack
; $0200-$07FF : General RAM
; $0800-$0FFF : Screen memory
; $1000-$1FFF : Character set
; $8000-$FFFF : ROM (this program)
;
; ROM Layout:
; $8000-$8FFF : Main program code
; $9000-$9FFF : Graphics routines
; $A000-$AFFF : Sound routines  
; $B000-$DFFF : Data tables
; $E000-$FFFF : System routines
; ============================================
```

## Phase 7: Verification and Testing

### Step 1: Automated Round-Trip Testing

The assembler has a built-in `--verify` flag for automated round-trip testing:

```bash
# One-step verification during assembly
python3 py6502/cli_asm6502.py game.asm -b game_new.bin --verify game_original.bin

# This will automatically:
# 1. Assemble the code
# 2. Compare with original
# 3. Report success or show first difference
```

Or create a test script:

```bash
#!/bin/bash
echo "Testing round-trip assembly..."

# Assemble with verification
python3 py6502/cli_asm6502.py game.asm -b game_new.bin --verify game_original.bin

# Exit code: 0 = success, 1 = failed
if [ $? -eq 0 ]; then
    echo "✓ All tests passed!"
else
    echo "✗ Test failed - see output above"
    echo "Run: python3 py6502/cli_diff6502.py game_original.bin game_new.bin -s ADDR -v"
fi
```

## Common Pitfalls and Solutions

### Pitfall 1: Zero-Page Addressing Ambiguity

**Problem:** Assembler optimizes absolute → zero-page, breaking round-trip.

**Solution:** Use `.a` suffix to force absolute addressing:
```
sta $0000.a     ; 3 bytes: 8D 00 00
lda $0010.a,x   ; 3 bytes: BD 10 00
```

### Pitfall 2: Branch Offset Calculation

**Problem:** Branches use relative offsets, not absolute addresses.

**Solution:** In reassemble mode, disassembler should emit addresses that calculate correctly.
```
; At $8000:
bne $8010   ; Assembler calculates: $8010 - ($8002) = $0E offset
```

### Pitfall 3: Self-Modifying Code

**Problem:** Code that modifies itself won't disassemble correctly.

**Example:**
```
8000: A9 00       lda #$00
8002: 8D 01 80    sta $8001    ; Modifies own immediate value!
```

**Solution:** 
1. Document as self-modifying
2. Show both initial and modified states
3. Consider using variables instead in documentation

### Pitfall 4: Data Within Code

**Problem:** Inline data (jump tables, constants) disassembles as garbage instructions.

**Example:**
```
8000: 4C 10 80    jmp $8010
8003: 48 45 4C    ; "HEL" - string data
8006: 4C 4F 00    ; "LO" - string data
8009: 00 00       ; padding
...
8010:             ; actual code continues
```

**Solution:** Mark data sections explicitly:
```
    jmp start
msg_hello:
    str "HELLO"
    db $00, $00   ; padding
start:
    ; code...
```

### Pitfall 5: Computed Jumps

**Problem:** Indirect jumps through tables.

**Example:**
```
; Jump table dispatch
    lda command
    asl
    tax
    lda jump_table+1,x
    pha
    lda jump_table,x
    pha
    rts            ; "Returns" to address from table

jump_table:
    dw &cmd_0-1    ; Addresses minus 1 (RTS adds 1)
    dw &cmd_1-1
    dw &cmd_2-1
```

**Solution:** Document the pattern and maintain the table carefully.

## Tool Enhancement Checklist

### Assembler Enhancements Needed

- [ ] `.include` directive for file inclusion
- [ ] `.python` / `.endpython` for Python macro blocks
- [ ] `.macro` / `.endmacro` for text macros
- [ ] Conditional assembly (`.if` / `.else` / `.endif`)
- [ ] Better error messages with line numbers
- [ ] Symbol table export to JSON/text
- [ ] Multiple input file support
- [ ] Listing file generation

### Disassembler Enhancements Needed

- [ ] 65C02 undefined opcode recognition
- [ ] Symbol table import
- [ ] Comments from symbol annotations
- [ ] Multiple output formats

### Completed Tools

**diff6502.py** - Smart diffing: ✅
- Binary diff with assembly context
- Show hex and assembly side-by-side
- Highlight differences
- Track down addressing mode issues
- Usage: `python3 py6502/cli_diff6502.py file1.bin file2.bin -s ADDR`

**analyzer6502.py** - Static analysis: ✅
- Control flow graphing
- Subroutine detection
- Entry point finding
- Code/data separation
- String detection
- Cross-reference generation
- Output: improved assembly and JSON analysis

## Workflow Example: Complete Disassembly

Let's walk through a complete example with Apple's FID (File Developer) utility.

### Given: 6502-prog.bin (4686 bytes, loads at $0803)

**Step 1: Initial disassembly**
```bash
python3 py6502/cli_dis6502.py 6502-prog.bin -s 0x0803 -l 4686 --reassemble -o fid_v1.asm
```

**Step 2: Verify round-trip**
```bash
python3 py6502/cli_asm6502.py fid_v1.asm -b fid_test.bin --verify 6502-prog.bin
# ✓ ROUND-TRIP VERIFICATION SUCCESSFUL!
```

**Step 3: Analyze code structure**
```bash
python3 py6502/analyzer6502.py 6502-prog.bin -s 0x0803 -e 0x0803 -o fid_improved.asm
```

**Step 4: Identify code vs data regions**
The analyzer will separate machine code from data tables and strings.

**Step 5: Add labels**
Convert JSR/JMP targets to label references.

**Step 6: Document subroutines**
Add comments explaining what each routine does.

**Step 7: Verify round-trip at each step!**
```bash
# Quick verification with --verify flag
python3 py6502/cli_asm6502.py fid_v5.asm -b fid_test.bin --verify 6502-prog.bin
# ✓ ROUND-TRIP VERIFICATION SUCCESSFUL!

# Or detailed comparison
python3 py6502/cli_diff6502.py 6502-prog.bin fid_test.bin -s 0x0803
# ✓ FILES ARE IDENTICAL!
```

**Step 8: Organize into sections**
```
; ============================================
; MAIN PROGRAM
; ============================================
    org $0803
main:
    ...

; ============================================
; GRAPHICS ROUTINES
; ============================================
init_screen:
    ...

; ============================================
; DATA SECTION
; ============================================
    org $1400
string_table:
    ...
```

## Tips for Success

1. **Always verify round-trip** after every change
2. **Make small, incremental improvements** - don't try to do everything at once
3. **Document as you learn** - write down discoveries immediately
4. **Use version control** - commit after each successful round-trip
5. **Keep original binary safe** - never lose your reference
6. **Test with simulator** when possible - verify behavior matches
7. **Research the platform** - understand the hardware and conventions
8. **Look for patterns** - 6502 code often repeats similar patterns
9. **Be patient** - disassembly is detective work, not a race
10. **Ask for help** - share findings, get feedback from others

## Conclusion

Disassembling a 6502 binary is an iterative process that combines:
- **Technical precision** (byte-perfect round-trips)
- **Detective work** (understanding what code does)
- **Documentation** (making it readable)
- **Engineering** (improving tools to help)

The constraint of maintaining binary identity forces you to truly understand the code. Every label rename, every comment, every improvement must be earned through understanding.

The result is a literate program that:
- Assembles identically to the original
- Tells a story about what it does
- Can be maintained and modified
- Serves as documentation for the binary

Welcome to the art of reverse engineering!