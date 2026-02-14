# 6502 Macro System Documentation

## Overview

The 6502 assembler includes an integrated macro system for generating repetitive code and data patterns. Macros are defined once and can be invoked multiple times with different arguments.

## Basic Usage

### Defining a Macro

Register a macro at the beginning of your assembly file:

```asm
.macro text_string = py6502.macros_examples.text_string
.macro byte_table = py6502.macros_examples.byte_table
```

The syntax is: `.macro name = module.path.function_name`

### Invoking a Macro

Use the `@` prefix to invoke a macro:

```asm
hello_msg:
    @text_string "Hello, World!"

my_table:
    @byte_table $41, $42, $43, $00
```

## Built-in Macros

All built-in macros are in `py6502.macros_examples`. Register them with:

```asm
.macro name = py6502.macros_examples.function_name
```

### `text_string` - Null-Terminated Text

Generates a null-terminated ASCII string.

**Usage:**
```asm
@text_string "Hello"
```

**Output:** Bytes `$48, $65, $6C, $6C, $6F, $00`

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

**Output:** Bytes `$05, $48, $65, $6C, $6C, $6F`

---

### `byte_table` - 8-Bit Values

Generates a table of 8-bit bytes.

**Usage:**
```asm
@byte_table $12, $34, $56, $78
```

**Formats Supported:**
- Hex: `$FF`
- Octal: `@77` (octal)
- Decimal: `255`

---

### `word_table` - 16-Bit Words (Little-Endian)

Generates a table of 16-bit words in little-endian format (low byte first).

**Usage:**
```asm
@word_table $1234, $5678, my_label
```

**Output:** Bytes `$34, $12, $78, $56`

**Note:** On Pass 1 (size estimation), label names will cause a warning. This is normal and resolves on Pass 2.

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

---

### `sine_table` - Sine Wave Lookup Table

Generates a 256-byte sine wave lookup table (values 0-255 represent angles 0-360°).

**Usage:**
```asm
sine_data:
    @sine_table              ; 256 bytes
    @sine_table 128          ; 128 bytes
```

**Output:** Scaled sine values: `sin(x) * 127 + 128` for each byte

---

### `cosine_table` - Cosine Wave Lookup Table

Generates a 256-byte cosine wave lookup table.

**Usage:**
```asm
cosine_data:
    @cosine_table            ; 256 bytes
    @cosine_table 128        ; 128 bytes
```

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

## Advanced: Creating Custom Macros

### Basic Macro Function

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

### Macro with Context

Macros can access assembly context (current address, labels, etc.):

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

The `context` parameter is a dict with:
- `org` - Current ORG address
- `labels` - Dict of resolved label names to addresses
- `addr` - Estimated current address

**Note:** On Pass 1, forward labels won't be resolved yet. Return size placeholder.

### Multi-Pass Aware Macro

For macros that need different behavior on Pass 1 vs Pass 2:

```python
def my_adaptive_macro(args, context=None, pass_num=2):
    """Adapt behavior based on assembly pass."""
    if pass_num == 1:
        # Pass 1: size estimation
        # Return placeholder bytes of correct length
        return [0] * 10
    else:
        # Pass 2: actual generation with resolved references
        # Return real bytes
        return generate_real_bytes(args, context)
```

## Multi-Pass Assembly

The macro system integrates with the assembler's multi-pass design:

- **Pass 1:** Macros expand with `pass_num=1` for size estimation
- **Pass 2:** Macros expand with `pass_num=2` with fully resolved labels and addresses

Macros should return the same number of bytes on both passes, even if the content differs.

## Complete Example

```asm
; 6502 program with macros
.macro text_string = py6502.macros_examples.text_string
.macro byte_table = py6502.macros_examples.byte_table
.macro sine_table = py6502.macros_examples.sine_table

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

; Sine wave data (256 bytes)
sine_data:
    @sine_table

; Padding
    @repeat_byte $FF, 16
```

## Troubleshooting

### Warning: "Cannot parse label reference"

This happens on Pass 1 when a macro tries to reference a label that hasn't been defined yet. The warning disappears on Pass 2 when labels are resolved. This is normal behavior.

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

1. **Organize macros:** Put `.macro` definitions at the top of your file
2. **Document macros:** Add comments explaining what each macro does
3. **Use consistent names:** Keep macro names short but descriptive
4. **Test macros:** Use simple test files before complex usage
5. **Check output:** Use `--verbose` flag to see generated assembly
6. **Size constraints:** Remember each macro result must fit in your address space
