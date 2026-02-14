# 6502 Macro System - Implementation Summary

## Overview

We've successfully implemented a comprehensive, integrated macro system for the 6502 assembler. Macros allow you to define reusable code and data patterns that automatically expand during assembly.

## What Was Built

### 1. Core Components

**`py6502/macro6502.py`** (225 lines)
- `MacroExpander` class for managing macro expansion
- Dynamic Python function loading via `__import__`
- Pattern matching for `.macro` definitions and `@invocations`
- Multi-pass aware expansion (Pass 1 for sizing, Pass 2 for generation)
- Context-aware expansion (labels, addresses, org)

**`py6502/macros_examples.py`** (303 lines)
- 9 built-in macro implementations
- All functions support optional `pass_num` and `context` parameters
- Comprehensive docstrings and error handling

**`py6502/asm6502.py`** (modified)
- Integrated macro support directly into assembly process
- `.macro` directive parsing
- Macro expansion pass before standard assembly passes
- Seamless multi-pass assembly

### 2. Built-in Macros

| Macro | Purpose | Example |
|-------|---------|---------|
| `text_string` | Null-terminated ASCII strings | `@text_string "Hello"` → `$48, $65, $6C, $6C, $6F, $00` |
| `pascal_string` | Length-prefixed strings | `@pascal_string "Hi"` → `$02, $48, $69` |
| `byte_table` | 8-bit value tables | `@byte_table $41, $42, $43` |
| `word_table` | 16-bit value tables (LE) | `@word_table $1234, $5678` |
| `jump_table` | Dispatch tables | `@jump_table start, end` |
| `repeat_byte` | Repeated bytes | `@repeat_byte $FF, 16` |
| `raw_hex` | Raw hex bytes | `@raw_hex 48 65 6C 6C 6F` |
| `sine_table` | 256-byte sine lookup | `@sine_table` |
| `cosine_table` | 256-byte cosine lookup | `@cosine_table` |

### 3. Features

✓ **Dynamic Registration**: Macros defined via `.macro name = module.function`
✓ **Easy Invocation**: Use `@macro_name args` syntax
✓ **Multi-Pass Aware**: Different behavior on Pass 1 (size) vs Pass 2 (code)
✓ **Context Access**: Macros can access labels, addresses, org values
✓ **Escape Sequences**: Full support for `\n`, `\r`, `\t`, `\\`, `\0`
✓ **Number Formats**: Hex ($FF), Octal (@77), Decimal (255)
✓ **Error Handling**: Graceful failure with informative messages
✓ **Integrated**: No separate preprocessing step needed

## Testing

**`tests/test_macros.py`** (449 lines)
- **42 comprehensive tests** - ALL PASSING ✓
- Test categories:
  - Macro expander functionality (7 tests)
  - Built-in macro implementations (24 tests)
  - Integration with expansion (7 tests)
  - Assembler integration (2 tests)
  - Error handling (2 tests)

Run tests: `python3 -m pytest tests/test_macros.py -v`

## Usage Example

```asm
; Define macros at top of file
.macro text_string = py6502.macros_examples.text_string
.macro byte_table = py6502.macros_examples.byte_table

org $0800

; Use macros naturally
message:
    @text_string "Hello, World!"

lookup_table:
    @byte_table $01, $02, $04, $08, $10, $20, $40, $80

; Regular assembly code mixed with macros
start:
    lda #<message
    sta $20
    rts
```

Assemble normally:
```bash
python3 py6502/cli_asm6502.py program.asm -b program.bin
```

## Architecture

### Design Decisions

1. **Integrated vs Separate**: Macros are integrated into the assembler, not a separate preprocessing step. This ensures proper integration with multi-pass assembly.

2. **Dynamic Loading**: Macro functions are loaded via Python's `__import__`, allowing arbitrary Python modules to define macros without modifying the assembler.

3. **Two-Pass Support**: Macros receive `pass_num` parameter:
   - Pass 1: Return placeholder bytes of correct size for address computation
   - Pass 2: Return actual bytes with resolved labels

4. **Context Support**: Macros can optionally receive assembly context:
   - Current org address
   - Resolved label addresses
   - Estimated current address
   
   This allows macros to generate address-dependent code.

### How It Works

1. **Macro Definition Phase** (in `parse_line`):
   ```asm
   .macro text_string = py6502.macros_examples.text_string
   ```
   - Parsed by `.macro` directive handler
   - Registered in `macro_expander.macros` dict
   - Module and function name stored for later loading

2. **Macro Expansion Phase** (in `assemble`):
   ```python
   # Pass 1 (size estimation)
   lines = self.macro_expander.process_file(lines, pass_num=1)
   # lines now contain db directives with placeholder bytes
   
   # Pass 2 (actual generation with resolved labels)
   # Macros are re-expanded with actual values
   ```

3. **Invocation**:
   ```asm
   msg:
       @text_string "Hello"
   ```
   - Detected by `@` prefix
   - Arguments parsed and passed to macro function
   - Returns list of bytes → converted to `db` directive
   - Integrated into assembly stream

## Documentation

See `py6502/MACROS.md` for:
- Complete macro reference
- Advanced usage (custom macros)
- Multi-pass assembly details
- Troubleshooting guide
- Best practices

## Files Changed/Created

```
Created:
  py6502/macro6502.py              (225 lines)
  py6502/macros_examples.py        (303 lines)
  py6502/MACROS.md                 (314 lines)
  tests/test_macros.py             (449 lines)
  py6502/example_macros.asm        (60 lines)

Modified:
  py6502/asm6502.py                (added macro support)
  py6502/cli_asm6502.py            (simplified, no separate macro step)
```

## Quality Metrics

- **Test Coverage**: 42 tests, 100% passing
- **Code Quality**: Clean, well-documented
- **Error Handling**: Comprehensive with informative messages
- **Performance**: Minimal overhead (single pass through file)
- **Compatibility**: Fully backward compatible with existing assembly code

## Next Steps

The macro system is production-ready! You can now:

1. Load your corrected binary
2. Analyze it with the improved tools
3. Create clean, readable assembly with macros
4. Maintain byte-for-byte fidelity with the original

Recommended workflow:
```bash
# Analyze the binary
python3 py6502/analyzer6502.py your_binary.bin -s 0x0800 -o disassembly.asm

# Edit disassembly to add macros for data patterns
# (use @text_string, @byte_table, etc. where appropriate)

# Assemble (macros expand automatically)
python3 py6502/cli_asm6502.py disassembly.asm -b output.bin

# Verify round-trip
python3 py6502/cli_asm6502.py disassembly.asm -b output.bin --verify your_binary.bin
```

## Summary

We've created a robust, well-tested macro system that:
- Integrates seamlessly with the 6502 assembler
- Supports multi-pass assembly correctly
- Provides 9 useful built-in macros
- Allows custom macro definitions
- Maintains 100% backward compatibility
- Includes comprehensive documentation
- Is fully tested with 42 passing tests

The macro system is ready for real-world use in analyzing and reassembling 6502 binaries.
