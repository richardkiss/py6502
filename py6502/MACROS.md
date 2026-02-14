# 6502 Macro System

## Overview

The 6502 assembler includes an integrated macro system for generating repetitive code and data patterns. Macros are defined once and can be invoked multiple times with different arguments.

The macro system is **fully integrated** into the assembler—no separate preprocessing step is needed. It supports multi-pass assembly with proper label resolution and context awareness.

## Quick Start

### 1. Define Macros

Register macros at the beginning of your assembly file:

```asm
.macro text_string = py6502.macros_examples.text_string
.macro byte_table = py6502.macros_examples.byte_table
```

Syntax: `.macro name = module.path.function_name`

### 2. Use Macros

Invoke macros with the `@` prefix:

```asm
msg:
    @text_string "Hello, World!"

table:
    @byte_table $41, $42, $43, $00
```

### 3. Assemble

Simply assemble normally—macros expand automatically:

```bash
python3 py6502/cli_asm6502.py program.asm -b program.bin
```

## Built-in Macros

All built-in macros are in `py6502.macros_examples`.

### `text_string` - Null-Terminated Text

Generates a null-terminated ASCII string.

**Usage:**
```asm
@text_string "Hello"
```

**Output:** `$48, $65, $6C, $6C, $6F, $00`

**Escape Sequences:**
- `\n` - newline
- `\r` - carriage return
- `\t` - tab
- `\0` - null byte
- `\\` - backslash

---

### `pascal_string` - Length-Prefixed String

Generates a Pascal-style string with length byte prefix (no null terminator).

**Usage:**
```asm
@pascal_string "Hello"
```

**Output:** `$05, $48, $65, $6C, $6C, $6F`

---

### `byte_table` - 8-Bit Values

Generates a table of 8-bit bytes.

**Usage:**
```asm
@byte_table $12, $34, $56, $78
```

**Formats Supported:**
- Hex: `$FF`
- Octal: `@77`
- Decimal: `255`

**Error Handling:**
- Values must be 0-255 (errors on out-of-range)
- Requires at least one argument

---

### `word_table` - 16-Bit Words (Little-Endian)

Generates a table of 16-bit words in little-endian format (low byte first).

**Usage:**
```asm
@word_table $1234, $5678, my_label
```

**Output:** `$34, $12, $78, $56`

**Features:**
- Supports hex ($1234), decimal, octal
- Can reference labels (on Pass 2 with resolved addresses)
- Little-endian format

---

### `jump_table` - Jump Dispatch Table

Generates a jump table for dispatch-style subroutine calls. Automatically subtracts 1 from addresses (for RTS compatibility).

**Usage:**
```asm
dispatch_table:
    @jump_table routine_a, routine_b, routine_c
```

---

### `repeat_byte` - Repeat a Byte N Times

Repeats a single byte value a specified number of times.

**Usage:**
```asm
padding:
    @repeat_byte $FF, 16     ; 16 bytes of $FF
```

**Arguments:** `@repeat_byte value, count`

---

### `raw_hex` - Raw Hex Bytes

Insert raw hex bytes directly.

**Usage:**
```asm
@raw_hex 48 65 6C 6C 6F     ; "Hello" in hex
```

**Formats Supported:**
- `48` (no prefix)
- `$48` (with $ prefix)

---

### `sine_table` - Sine Wave Lookup Table

Generates a sine wave lookup table (values 0-255 represent angles 0-360°).

**Usage:**
```asm
sine_data:
    @sine_table              ; 256 bytes
    @sine_table 128          ; 128 bytes
```

**Output:** Scaled sine values: `sin(x) * 127 + 128` for each byte

---

### `cosine_table` - Cosine Wave Lookup Table

Generates a cosine wave lookup table.

**Usage:**
```asm
cosine_data:
    @cosine_table            ; 256 bytes
    @cosine_table 128        ; 128 bytes
```

---

## Complete Example

```asm
; Define macros
.macro text_string = py6502.macros_examples.text_string
.macro byte_table = py6502.macros_examples.byte_table
.macro sine_table = py6502.macros_examples.sine_table
.macro word_table = py6502.macros_examples.word_table

org $0800

; Main program
main:
    ldx #0
    lda #<message
    sta $20
    lda #>message
    sta $21
    rts

; Message using macro
message:
    @text_string "Hello, 6502!"

; Lookup table using macro
lookup:
    @byte_table $01, $02, $04, $08, $10, $20, $40, $80

; Address table
addresses:
    @word_table main, lookup, sine_data

; Sine wave data (256 bytes)
sine_data:
    @sine_table

; Padding
padding:
    @repeat_byte $FF, 16
```

## Advanced Usage

### Creating Custom Macros

Create a Python file with a function that takes `args`:

```python
# my_macros.py
def my_pattern(args):
    """Generate a custom pattern."""
    if not args or len(args) == 0:
        raise ValueError("my_pattern requires an argument")
    
    count = int(args[0], 0)
    result = []
    for i in range(count):
        result.append(i & 0xFF)
    return result
```

Register and use in assembly:

```asm
.macro my_pattern = my_macros.my_pattern
@my_pattern 10
```

### Macros with Context

Macros can access assembly context (labels, addresses, org):

```python
def my_label_macro(args, context=None):
    """Use label addresses in a macro."""
    if context and 'labels' in context:
        labels = context['labels']
        if 'target_label' in labels:
            addr = labels['target_label']
            return [addr & 0xFF, (addr >> 8) & 0xFF]
    
    return [0, 0]
```

**Context dict contents:**
- `org` - Current ORG address
- `labels` - Dict of resolved label names to addresses
- `addr` - Estimated current address

### Multi-Pass Aware Macros

Macros receive `pass_num` parameter for different behavior on each pass:

```python
def my_adaptive_macro(args, context=None, pass_num=2):
    """Adapt behavior based on assembly pass."""
    if pass_num == 1:
        # Pass 1: size estimation
        # Return placeholder bytes of correct length
        return [0] * 10
    else:
        # Pass 2: actual generation with resolved references
        return generate_real_bytes(args, context)
```

**Important:** Return the same number of bytes on both passes!

## Multi-Pass Assembly

The macro system integrates with the assembler's multi-pass design:

- **Pass 1:** Macros expand with `pass_num=1` for size estimation
  - Used to compute addresses and resolve forward references
  - Return placeholder bytes of the correct size
  
- **Pass 2:** Macros expand with `pass_num=2` with fully resolved labels
  - Generate actual bytes with real address values
  - All labels are now available

Macros should return the same number of bytes on both passes, even if the content differs.

## Architecture

### How It Works

1. **Macro Definition** (in assembly file):
   ```asm
   .macro text_string = py6502.macros_examples.text_string
   ```
   - Parsed by `.macro` directive handler
   - Registered in macro expander
   - Module and function name stored for later

2. **Macro Expansion** (during assembly):
   - Detected by `@` prefix
   - Arguments extracted and passed to macro function
   - Returns list of bytes → converted to `db` directive
   - Inserted into assembly stream

3. **Dynamic Loading**:
   - Macro functions loaded via Python's `__import__`
   - Allows arbitrary Python modules to define macros
   - No modification to assembler needed

### Design Features

✓ **Integrated**: No separate preprocessing step
✓ **Multi-Pass Aware**: Proper support for two-pass assembly
✓ **Context Aware**: Macros can access labels and addresses
✓ **Dynamic Loading**: Macro functions in any Python module
✓ **Error Handling**: Graceful failures with informative messages
✓ **Flexible**: Supports custom macro definitions
✓ **Tested**: 42 comprehensive tests, all passing

## Testing

The macro system includes comprehensive tests:

```bash
python3 -m pytest tests/test_macros.py -v
```

**42 tests covering:**
- Macro expander functionality
- All built-in macros
- File processing and expansion
- Multi-pass assembly
- Assembler integration
- Error handling and edge cases

## Troubleshooting

### Warning: "Cannot parse label reference"

This happens on Pass 1 when a macro tries to reference a label that hasn't been defined yet. The warning disappears on Pass 2 when labels are resolved. **This is normal behavior.**

### Macro expands to wrong number of bytes

Ensure your macro returns the same number of bytes on both passes (even if placeholder bytes on Pass 1).

### Module not found error

Check that:
- The module path is correct (e.g., `py6502.macros_examples`)
- The module is importable from Python
- The function exists in that module

### Escaped characters not working

Use raw strings or double escaping:
```asm
@text_string "Line 1\nLine 2"     ; Newline
@text_string "Quoted: \"Hello\""   ; Quote
```

## Tips & Best Practices

1. **Organize macros**: Put `.macro` definitions at the top of your file
2. **Document macros**: Add comments explaining what each macro does
3. **Use consistent names**: Keep macro names short but descriptive
4. **Test macros**: Use simple test files before complex usage
5. **Check output**: Use `--verbose` flag to see generated assembly
6. **Size constraints**: Remember each macro result must fit in your address space
7. **Pass 1 awareness**: Always return the same byte count on both passes

## Files

- `py6502/macro6502.py` - Macro expansion engine
- `py6502/macros_examples.py` - Built-in macro implementations
- `tests/test_macros.py` - Comprehensive test suite (42 tests)
- `py6502/example_macros.asm` - Working example code

## Summary

The 6502 macro system provides:
- **Easy to use**: Simple `@name` syntax
- **Powerful**: Dynamic Python function loading
- **Reliable**: Multi-pass aware with proper label resolution
- **Extensible**: Create custom macros easily
- **Well-tested**: 42 comprehensive tests
- **Well-documented**: Complete reference and examples

Use macros to make your 6502 assembly code more readable, maintainable, and less repetitive!