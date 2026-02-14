# SKILLS: Reverse Engineering 6502 Binaries into Literate Assembly

## Goal

Transform a raw 6502 binary into **literate assembly** that:
1. Assembles **byte-for-byte identically** to the original binary
2. Has meaningful labels, comments, macros, and documentation
3. Tells the story of what the program does

## The Core Loop

```
  1. Make an improvement to the assembly source
  2. Assemble to binary
  3. Diff against original
  4. If identical → commit, go to 1
  5. If different → fix, go to 2
```

**Never break the round-trip.** Every label rename, every comment, every data
annotation must preserve binary identity. This constraint forces real understanding.

## Best Practices: Equates, Addressing Modes & Documentation

### Equates for Documentation (Not Code Replacement)

When adding equates to document memory locations, **do not replace addresses in the
code with equate names**. This causes addressing mode mismatches:

```asm
; WRONG: Using equate name in code
MY_VAR = $1394
sta MY_VAR          ; Assembler treats this as zero-page → 85 94 (2 bytes)
                    ; Original was absolute → 8D 94 13 (3 bytes) → BROKEN!

; RIGHT: Use equates for reference, keep literals in code
MY_VAR = $1394      ; For documentation
sta $1394           ; Original addressing mode preserved
```

**Solution:** Add equates in a dedicated section for reference only. Code uses literal
addresses. This approach:
- Maintains byte-for-byte binary compatibility
- Provides helpful documentation for readers
- Avoids the `.a` suffix workaround for every high-address instruction
- Keeps equates as a "cheat sheet" rather than active code replacement

### Addressing Mode Gotchas

The 6502 has two common addressing modes for the same address:

| Mode | Syntax | Bytes | Example |
|------|--------|-------|---------|
| Zero-page | `sta $00` | 2 | Operates on page 0 only |
| Absolute | `sta $00.a` or `sta $1394` | 3 | Full 16-bit address |

When reassembling from a disassembly, the original binary determined which mode was used.
The assembler will optimize `sta $00` to zero-page (2 bytes), but if the original was
absolute (3 bytes), the round-trip fails. Use `.a` suffix to force absolute mode.

The `--reassemble` flag in `cli_dis6502.py` handles this automatically by emitting `.a`
where needed.

### Documentation Structure

Effective literate assembly balances:

1. **Equates section** (reference only, organized by category)
   - Zero-page variables and their ranges
   - ROM entry points with descriptions
   - Program-specific constants grouped logically
   - Format: `NAME = $ADDRESS ; brief description`

2. **Memory map** (overview of address layout)
   - Start/end addresses of major sections
   - Byte counts and subdivisions
   - Runtime vs. static allocations
   - Notes on shared memory spaces

3. **Subroutine headers** (what, not how)
   - Purpose statement
   - Entry conditions (registers, flags, memory state)
   - Exit conditions (return values, side effects)
   - Call sites (where it's called from)

4. **Inline comments** (explain non-obvious operations)
   - Immediate values and their meanings
   - Loop structures and counters
   - Branch targets and why
   - ROM routine calls and side effects
   - Register state changes

Example:
```asm
; ============================================================================
; SUBROUTINE: print_string ($0ACD)
; ============================================================================
; Print a null-terminated string from the string table.
;
; Entry:  X = string index (0-48)
; Exit:   String printed via COUT; registers unchanged
; Uses:   $04-$05 as pointer to current string
;
; Algorithm:
;   1. Save registers (A, X, Y)
;   2. Index into STRING_TABLE at $13E8 (word pointers)
;   3. Loop through string, outputting characters
;   4. Stop at null terminator
;   5. Restore registers
; ============================================================================

print_string:
 pha                     ; Save A register
 tya                     ; Transfer Y to A
 pha                     ; Save Y register
 txa                     ; Transfer X to A
 pha                     ; Save X register (string index)
 
 asl  A                  ; Multiply by 2 (word table offset)
 tax                     ; Transfer to X
 lda  $13e8,x            ; Load pointer low byte from table
 sta  $04                ; Store in $04
 lda  $13e9,x            ; Load pointer high byte from table
 sta  $05                ; Store in $05
 
 ldy  #$00               ; Y = 0 (offset in string)
loop:
 lda  ($04),y            ; Load character from pointer
 beq  done               ; If null, exit loop
 jsr  $fded              ; COUT: output character
 iny                     ; Next character
 bne  loop               ; Loop if Y != 0 (max 256 chars)
 
done:
 pla                     ; Restore X
 tax
 pla                     ; Restore Y
 tay
 pla                     ; Restore A
 rts
```

---

## Tools Reference

All tools live in `py6502/`. Run with `python3 py6502/<tool>`.

### cli_dis6502.py — Disassembler

Converts binary to assembly. **Always use `--reassemble`** for round-trip work.

```
# Disassemble with reassembly support (critical flags shown)
python3 py6502/cli_dis6502.py INPUT.bin \
    -s 0x0803           # start address in 6502 memory
    --offset 4          # skip N bytes of file header before reading code
    -l 4686             # number of bytes to disassemble
    --reassemble        # emit org directive, numeric branch offsets, .a suffixes
    -o output.asm       # output file
```

`--reassemble` changes the output from a human listing to something the assembler
can consume: `org` directive, no address/hex columns, branch offsets as `+$nn`/`-$nn`.

Other useful flags: `--symbols FILE` (load label=address pairs), `-f hex|both`.

### cli_asm6502.py — Assembler

Assembles `.asm` to binary. **Use `--compare`** to verify round-trip in one step.

```
python3 py6502/cli_asm6502.py code.asm \
    -b output.bin                   # binary output
    --compare original_noheader.bin # auto-verify with smart diff
    -v                              # verbose listing
    --symbols syms.txt              # dump symbol table
```

On success: `✓ ROUND-TRIP VERIFICATION SUCCESSFUL!`

On failure, the **`--compare` diff mode** shows:
- First difference with address and byte values
- **Context bytes** around the difference (before and after)
- **Pattern detection**: off-by-one errors, endianness swaps, all-zeros/all-0xFF regions
- **Diagnosis hints**: branch offset issues, data vs. code confusion, addressing mode errors

For even more detail, use the separate `cli_diff6502.py` tool with `-v` flag for grouped
differences across the entire binary and region-by-region analysis.

### cli_diff6502.py — Smart Binary Differ

Dedicated binary comparison tool with **context-aware diff output**. Much more detailed
than assembler's `--compare` flag.

```
python3 py6502/cli_diff6502.py original.bin assembled.bin       # Basic comparison
python3 py6502/cli_diff6502.py original.bin assembled.bin -v    # Verbose: all grouped differences
python3 py6502/cli_diff6502.py original.bin assembled.bin --context 32  # More context bytes
python3 py6502/cli_diff6502.py original.bin assembled.bin -s 0x0800 -e 0x1000  # Compare range
```

**Key features:**
- **Context display**: Shows bytes before/after difference with hex dump and markers
- **Pattern detection**: Off-by-one errors, endianness swaps, all-zeros regions, branch offset issues
- **Grouped differences**: Consecutive bytes within 8 bytes grouped together in verbose mode
- **Diagnosis hints**: Detects data vs. code confusion, addressing mode errors, ROM vs. RAM issues
- **Address filtering**: Compare only specific memory ranges with `-s`/`-e`
- **JSON export**: `--json` for scripted analysis

Example verbose output:
```
✗ DIFFERENCES FOUND
Total differences: 3 bytes
First difference at offset 0x0145 (byte #325)

FIRST DIFFERENCE:
  Address:  0x0145
  Original: $A1
  Assembled: $A0

CONTEXT (16 bytes before and after):
>>> 0x0140:
    Original:  9E A1 BD 40 30 A0 A0 A0 A0 A0 A0 A0 00 00 00 00
    Assembled: 9E A0 BD 40 30 A0 A0 A0 A0 A0 A0 A0 00 00 00 00
                     ^^

DIAGNOSIS:
  • All bytes are -1 from expected (possible unsigned/signed mismatch)
```

Exit code 0 = identical, 1 = differences found.

### cli_reverse6502.py — Binary Format Helper

Analyzes and manipulates binary headers (Apple II format).

```
python3 py6502/cli_reverse6502.py FILE.bin --info      # show header
python3 py6502/cli_reverse6502.py FILE.bin --extract    # strip header → code only
python3 py6502/cli_reverse6502.py code.bin --make-bin out.bin --addr 0x0803 --len 4686
```

### cli_analyzer6502.py — Control Flow Analyzer

Traces execution from entry points to separate code from data.

```
python3 py6502/cli_analyzer6502.py FILE.bin \
    -s 0x0803 -e 0x0803    # start addr, entry point
    --regions               # show CODE/DATA regions
    --subroutines           # list detected subroutines with callers
    --calls                 # show call graph
    -o improved.asm         # generate improved disassembly
```

### generate_literate_asm.py — Label Generator

Takes raw `--reassemble` output and adds mechanical labels (`sub_XXXX`, `loc_XXXX`)
for all JSR/JMP/branch targets, plus subroutine header comments.

```
python3 py6502/generate_literate_asm.py raw_v1.asm literate.asm
```

### improve_semantic_names.py — Semantic Renamer

Applies a mapping of mechanical labels → meaningful names, adds variable
documentation and ROM routine descriptions. Edit the `SUBROUTINE_NAMES`,
`LOCATION_NAMES`, and `ROM_DESCRIPTIONS` dicts in the script for each binary.

```
python3 py6502/improve_semantic_names.py literate.asm semantic.asm
```

### convert_strings_to_macros.py — String Macro Converter

Converts Apple II high-bit-set strings from hex bytes to `@apple2_str` macros.
Useful for reducing file size and improving readability of string data sections.

```
# Convert all strings in a file
python3 py6502/convert_strings_to_macros.py input.asm -o output.asm

# Preview conversions first
python3 py6502/convert_strings_to_macros.py input.asm -v
```

**Capabilities:**
- Parses `db` statements containing Apple II hex bytes
- Converts to readable ASCII strings with escape sequences
- Handles control bytes: `\xHH` (e.g., `\x87` for non-ASCII bytes)
- Handles newlines: `\n` → CR ($0D)
- Multi-line strings across multiple `db` statements supported
- Preserves comments for reference

---

## Macro System

Macros generate data at assemble-time via Python functions. They integrate directly
into the assembler — no preprocessing step needed.

### Defining and Using Macros

```asm
; Register at top of file
.macro text_string = py6502.macros_examples.text_string
.macro word_table  = py6502.macros_examples.word_table
.macro jump_table  = py6502.macros_examples.jump_table

; Invoke with @
msg_hello:
    @text_string "Hello, World!"

addresses:
    @word_table $1234, $5678

dispatch:
    @jump_table handler_a, handler_b   ; auto subtracts 1 for RTS trick
```

### Built-in Macros (py6502.macros_examples)

| Macro | Description | Example |
|-------|-------------|---------|
| `text_string` | Null-terminated ASCII | `@text_string "Hello"` → `$48,$65,$6C,$6C,$6F,$00` |
| `pascal_string` | Length-prefixed string | `@pascal_string "Hi"` → `$02,$48,$69` |
| `byte_table` | Raw byte values | `@byte_table $12, $34, $56` |
| `word_table` | 16-bit little-endian words | `@word_table $1234` → `$34,$12` |
| `jump_table` | RTS dispatch table (addr-1) | `@jump_table label_a, label_b` |
| `apple2_str` | Apple II high-bit-set string | `@apple2_str "HELLO"` → `$C8,$C5,$CC,$CC,$CF,$00` |
| `repeat_byte` | Fill N bytes | `@repeat_byte $FF, 16` |
| `raw_hex` | Hex byte insertion | `@raw_hex 48 65 6C 6C 6F` |
| `sine_table` | 256-byte sine LUT | `@sine_table` or `@sine_table 128` |
| `cosine_table` | 256-byte cosine LUT | `@cosine_table` |

### Apple II Strings in Detail

The `apple2_str` macro is designed for Apple II assembly where normal text has the
high bit (0x80) set. It automatically converts readable ASCII to this format.

**Features:**
- Normal ASCII → high-bit-set (`'A'` $41 → $C1, space $20 → $A0)
- Newline escape: `\n` → CR ($0D, displayed as $8D with high bit)
- Hex escapes: `\xHH` → raw byte value (e.g., `\x87` for control character)
- Null terminator added automatically

**Examples:**
```asm
.macro apple2_str = py6502.macros_examples.apple2_str

; Simple string
@apple2_str "HELLO"          ; → $C8,$C5,$CC,$CC,$CF,$00

; With newline
@apple2_str "HELLO\nWORLD"   ; → $C8,$C5,$CC,$CC,$CF,$8D,$D7,$CF,$D2,$CC,$C4,$00

; With control bytes (e.g., bell character)
@apple2_str "ALERT\x87SOUND" ; → $C1,$CC,$C5,$D2,$D4,$87,$D3,$CF,$D5,$CE,$C4,$00
```

### Writing Custom Macros

Create a Python function that receives `args` (list of strings) and returns
a list of byte values (0–255), a string of assembly lines, or `None`.

```python
# my_macros.py
def apple2_str(args, context=None, pass_num=2):
    """Null-terminated Apple II string (high-bit-set ASCII)."""
    text = args[0].strip('"').strip("'")
    text = text.replace('\\n', '\r')  # Apple II uses $8D for newline
    result = [(ord(c) | 0x80) & 0xFF for c in text]
    result.append(0x00)  # null terminator
    return result
```

Register: `.macro apple2_str = my_macros.apple2_str`
Use: `@apple2_str "HELLO WORLD"`

**Important:** Macros must return the same number of bytes on pass 1 and pass 2.
The assembler calls macros twice for label resolution.

---

## Workflow: From Binary to Literate Assembly

### Phase 1: Initial Disassembly and Round-Trip

```bash
# 1. Analyze binary format
python3 py6502/cli_reverse6502.py prog.bin --info
#    → Load address: $0803, Code length: 4686 bytes, 4-byte Apple II header

# 2. Extract code without header (for comparison target)
dd if=prog.bin of=prog_noheader.bin bs=1 skip=4 count=4686

# 3. Disassemble
python3 py6502/cli_dis6502.py prog.bin -s 0x0803 --offset 4 -l 4686 \
    --reassemble -o prog_v1.asm

# 4. Verify round-trip
python3 py6502/cli_asm6502.py prog_v1.asm -b /tmp/test.bin \
    --compare prog_noheader.bin
```

### Phase 2: Code/Data Separation

Use the analyzer to find what's code and what's data:

```bash
python3 py6502/cli_analyzer6502.py prog_noheader.bin -s 0x0803 -e 0x0803 --regions
```

Then in the assembly, replace data regions with `db` directives. For strings,
use `@apple2_str` or `@text_string` macros. For tables, use `@word_table` or
`@byte_table`. **Verify round-trip after each change.**

Common data patterns to look for:
- **Strings:** Runs of bytes in $A0–$FE range (Apple II) or $20–$7E (standard ASCII)
- **Pointer tables:** Pairs of low/high bytes pointing to other addresses in the binary
- **Jump tables:** Pointer tables where each address is target−1 (RTS dispatch trick)
- **Lookup tables:** Sequential or patterned byte/word values

### Phase 3: Labels and Structure

```bash
# Auto-generate mechanical labels for all targets
python3 py6502/generate_literate_asm.py prog_v1.asm prog_v2.asm
```

This creates `sub_XXXX:` for JSR targets and `loc_XXXX:` for JMP/branch targets.
Verify round-trip. Then replace numeric branch offsets with label references where
the assembler can calculate them.

### Phase 4: Semantic Understanding

Rename labels based on what the code actually does:

```asm
; Before                    ; After
sub_0844:                   init_system:
sub_088b:                   show_menu:
sub_0acd:                   print_string_x:
loc_080e:                   main_loop:
```

Add documentation:
- **Block comments** above each subroutine: purpose, inputs, outputs, clobbers
- **Inline comments** for non-obvious instructions
- **Memory map** at the top of the file: zero-page usage, RAM variables, I/O
- **Constants** via equates: `SCREEN_WIDTH = 40`

Use `improve_semantic_names.py` to apply batch renames, or edit by hand.
**Verify round-trip after each batch of changes.**

### Phase 5: Macros for Data

Replace raw `db` sequences with macros that convey meaning:

```asm
; Before
msg_source_slot:
    db $D3, $CF, $D5, $D2, $C3, $C5, $A0, $D3, $CC, $CF, $D4, $BF, $00

; After
.macro apple2_str = my_macros.apple2_str
msg_source_slot:
    @apple2_str "SOURCE SLOT?"
```

For pointer tables and jump tables:
```asm
; Before
    db $65, $0E, $A9, $0D, $D7, $0D, $96, $0D, ...

; After
menu_dispatch:
    @jump_table do_copy, do_delete, do_catalog, do_lock, ...
```

**Verify round-trip after each change.**

---

## Assembler Features Reference

### Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `org $XXXX` | Set assembly address | `org $0803` |
| `db` | Define bytes | `db $41, $42, $00` |
| `dw` | Define words (16-bit LE) | `dw $1234, label` |
| `ddw` | Define double words | `ddw $12345678` |
| `text` | Null-terminated string | `text "hello"` |
| `label = value` | Constant/equate | `SCREEN = $0400` |

### Addressing Mode Suffix

The `.a` suffix forces **absolute** (3-byte) addressing when the assembler would
otherwise optimize to zero-page (2-byte):

```asm
sta $00      ; → 85 00       (2 bytes, zero-page)
sta $00.a    ; → 8D 00 00    (3 bytes, absolute)
lda $10.a,x  ; → BD 10 00    (3 bytes, absolute,X)
```

This is critical for round-trip fidelity. The disassembler's `--reassemble` mode
emits `.a` where the original binary uses absolute addressing for zero-page addresses.

### Branch Offsets

In `--reassemble` mode, branches are emitted as signed offsets:

```asm
bne +$09     ; branch forward 9 bytes
bpl -$0d     ; branch backward 13 bytes
```

These can later be replaced with label references once labels are established.

---

## Real-World Example: FID (File Developer)

The 6502-prog.bin contains the Apple II FID utility (disk file manager). Reverse-engineering
it into literate assembly demonstrates all these principles:

### Challenge: Understanding Complex Data Structures

FID uses a sophisticated menu system with validation sub-tables:

```asm
; Main menu selections
MENU_CHARS = $13AF      ; "123456789" - all valid options

; Sub-tables (offsets from MENU_CHARS base)
NO_DISK_OPTIONS = $13B9 ; "79" - RESET SLOT & QUIT (no disk needed)
FILE_OPS = $13BC        ; "625348" - file operations
COPY_OPTION = $13C3     ; "1" - copy only (needs two slots)
ALT_PATH_OPS = $13C5    ; "2739" - catalog, reset, space, quit
```

The `find_in_table` subroutine searches these using offset-based indexing. Without
documentation, this looks like magic. With comments explaining the table organization,
the logic becomes clear.

### Solution: Comprehensive Equates + Inline Comments

1. Define all address ranges with clear purpose
2. Document table layouts with offset calculations
3. Explain loop structures (Y counter for menu options 0-8)
4. Note register preservation and side effects

Result: A reader can understand the menu dispatch mechanism without debugging.

### Key Insight: Literal Addresses Are Your Friend

By keeping literal addresses in code and using equates only for documentation:
- Round-trip verification never fails on addressing modes
- The code remains portable to different assemblers
- Comments explain what equates mean
- No `.a` suffix workarounds needed

---

## Real-World Example: FID (File Developer)

The 6502-prog.bin contains the Apple II FID utility (disk file manager). Reverse-engineering
it into literate assembly demonstrates all these principles:

### Challenge: Understanding Complex Data Structures

FID uses a sophisticated menu system with validation sub-tables:

```asm
; Main menu selections
MENU_CHARS = $13AF      ; "123456789" - all valid options

; Sub-tables (offsets from MENU_CHARS base)
NO_DISK_OPTIONS = $13B9 ; "79" - RESET SLOT & QUIT (no disk needed)
FILE_OPS = $13BC        ; "625348" - file operations
COPY_OPTION = $13C3     ; "1" - copy only (needs two slots)
ALT_PATH_OPS = $13C5    ; "2739" - catalog, reset, space, quit
```

The `find_in_table` subroutine searches these using offset-based indexing. Without
documentation, this looks like magic. With comments explaining the table organization,
the logic becomes clear.

### Solution: Comprehensive Equates + Inline Comments

1. Define all address ranges with clear purpose
2. Document table layouts with offset calculations
3. Explain loop structures (Y counter for menu options 0-8)
4. Note register preservation and side effects

Result: A reader can understand the menu dispatch mechanism without debugging.

### Key Insight: Literal Addresses Are Your Friend

By keeping literal addresses in code and using equates only for documentation:
- Round-trip verification never fails on addressing modes
- The code remains portable to different assemblers
- Comments explain what equates mean
- No `.a` suffix workarounds needed

---

## Apple II Specifics

### Binary Header Format

Many Apple II binaries have a 4-byte header:

| Offset | Content | Example |
|--------|---------|---------|
| $00–$01 | Load address (little-endian) | $03 $08 → $0803 |
| $02–$03 | Code length (little-endian) | $4E $12 → 4686 |

**Always skip the header** when disassembling (`--offset 4`) and compare against
the headerless code (`dd if=file.bin of=code.bin bs=1 skip=4`).

### Apple II ROM Calls

Common Monitor ROM entry points:

| Address | Name | Description |
|---------|------|-------------|
| `$FBC1` | BASCALC | Calculate text base address from CV ($25) |
| `$FC10` | CROUT1 | CR if cursor not at column 0 |
| `$FC58` | HOME | Clear screen, cursor to top-left |
| `$FC62` | CLREOL | Clear to end of line |
| `$FC66` | CLREOP | Clear to end of page |
| `$FD0C` | RDKEY | Read one keypress (blocks) |
| `$FD6F` | GETLN | Read line into $0200 buffer, X=length |
| `$FD8E` | CROUT | Output carriage return |
| `$FDDA` | PRBYTE | Print A register as 2-digit hex |
| `$FDED` | COUT | Output character in A |
| `$FF3A` | BELL | Ring bell (beep) |

### DOS 3.3 Entry Points

| Address | Description |
|---------|-------------|
| `$03D2` | DOS version check byte |
| `$03D3` | DOS warm start (return to BASIC/DOS) |
| `$03D6` | File manager call |
| `$03D9` | File manager call (alt entry) |
| `$03DC` | Get file manager parameter list (returns A,Y) |
| `$03E3` | Get RWTS parameter list (returns A,Y) |

### Apple II Text Encoding

Apple II "normal" text has the high bit set on every character:

| Char | ASCII | Apple II |
|------|-------|----------|
| Space | $20 | $A0 |
| A | $41 | $C1 |
| 0 | $30 | $B0 |
| CR | $0D | $8D |

Strings are typically null-terminated ($00). A custom `apple2_str` macro handles
the encoding automatically.

### Key Zero-Page Locations

| Address | Name | Used By |
|---------|------|---------|
| `$00–$01` | General pointer | Monitor, DOS |
| `$02–$03` | General pointer | Monitor, DOS |
| `$22` | WNDLFT | Text window left |
| `$24` | CH | Cursor horizontal position |
| `$25` | CV | Cursor vertical position |
| `$33` | PROMPT | Prompt character |
| `$76` | HGRPAGE | Hi-res page |
| `$D9` | ORONE | OR mask for output |

---

## Common 6502 Patterns

### RTS Dispatch (Computed Jump via Stack)

```asm
; A = command index
dispatch:
    asl A             ; ×2 for word index
    tay
    lda table+1,y     ; push high byte
    pha
    lda table,y       ; push low byte
    pha
    rts               ; "jump" to address+1

table:
    ; addresses are target−1 because RTS adds 1
    @jump_table handler_0, handler_1, handler_2
```

### 16-Bit Addition

```asm
    clc
    lda ptr_lo
    adc #$40
    sta ptr_lo
    lda ptr_hi
    adc #$00          ; carry propagation
    sta ptr_hi
```

### String Printing Loop

```asm
print_str:
    ldy #$00
.loop:
    lda (ptr),y
    beq .done         ; null terminator
    jsr COUT
    iny
    bne .loop
.done:
    rts
```

### Indexed String Table Printing

```asm
; X = string index (0, 1, 2, ...)
; Table at str_ptrs contains word pointers to null-terminated strings
print_indexed:
    txa
    asl A              ; ×2 for word table
    tax
    lda str_ptrs,x     ; low byte of pointer
    sta $04
    lda str_ptrs+1,x   ; high byte of pointer
    sta $05
    ldy #$00
.loop:
    lda ($04),y
    beq .done
    jsr COUT
    iny
    bne .loop
.done:
    rts
```

### BCD Arithmetic (Score Keeping)

```asm
    sed               ; set decimal mode
    clc
    lda score_lo
    adc #$01
    sta score_lo
    lda score_hi
    adc #$00
    sta score_hi
    cld               ; clear decimal mode (important!)
```

---

## Pitfalls

| Problem | Symptom | Fix |
|---------|---------|-----|
| ZP optimization | Assembled binary 1 byte shorter per occurrence | Add `.a` suffix to force absolute addressing |
| Data as code | Garbage instructions in listing, round-trip fails | Mark region with `db` directives |
| Missing header skip | First 4 bytes are wrong | Use `--offset 4` in disassembler |
| Wrong comparison target | Diff shows header bytes as errors | Compare against `dd`-extracted code, not full file |
| Branch to data | Analyzer misses a code path | Add extra entry points to analyzer (`-e`) |
| Self-modifying code | Assembled code differs from runtime behavior | Document with comments; the static binary is still correct |
| 65C02 undefined opcodes | Unknown opcode error | Emit as `db $XX` |

---

## Tips

1. **Verify after every change.** `--compare` is cheap; debugging cascading errors is not.
2. **Fix the first diff.** One wrong byte shifts everything after it. Always fix the earliest difference first.
3. **Start with `db`, refine to macros.** Get data regions correct as raw bytes first, then convert to macros.
4. **Use `dd` to extract comparison targets.** Never compare against a file with headers.
5. **Keep the original binary untouched.** It's your ground truth.
6. **Commit after each successful round-trip.** Version control is your friend.
7. **Research the platform.** Knowing Apple II ROM calls, DOS conventions, and memory maps turns gibberish into understanding.
8. **Strings reveal everything.** Finding readable text in data sections tells you what the program is.
9. **Follow the call graph.** JSR targets are subroutines; understanding their contract (inputs, outputs, side effects) is the key to understanding the program.
10. **Write macros for repeated data patterns.** If you see the same encoding 36 times, automate it.
11. **Use equates for documentation, not code replacement.** Define all memory addresses in a reference section; keep code using literal addresses to avoid addressing mode mismatches. Equates are a cheat sheet for readers, not replacements in instructions.
12. **Add a memory map section.** List all major address ranges with byte counts. This helps readers understand layout and makes finding things easier.
13. **Document register preservation.** Note which registers are saved/restored. This is essential for understanding subroutine contracts.
14. **Explain table-driven logic.** String tables, dispatch tables, and validation sub-tables are common in compact 6502 code. Document how indices map to entries.
15. **Comment the non-obvious.** Bit shifts for slot numbers, BCD arithmetic, pointer arithmetic—these need explanation. Obvious code (like `iny`) needs fewer comments.
