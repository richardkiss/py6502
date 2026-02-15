# Changelog

## Version 1.0.0 (Fork from dj-on-github/py6502)

This fork significantly enhances the upstream py6502 with **round-trip verification and reverse engineering capabilities** designed specifically for the SKILLS.md workflow of reverse engineering 6502 binaries into literate assembly.

### Key Features Added

#### 1. Enhanced CLI Tools (3 tools)
- **a6502** - Enhanced assembler with `--compare` flag for smart binary diffing
- **d6502** - Disassembler with `--reassemble` flag for reassembly-compatible output
- **s6502** - 6502 simulator (subprocess-callable)

#### 2. Round-Trip Verification System
- **`.a` suffix** - Forces 3-byte absolute addressing for zero-page addresses (critical for binary-identical reassembly)
- **Smart binary diffing** - Context-aware diff output with pattern detection (off-by-one errors, endianness swaps, branch offset issues)
- **`--reassemble` mode** in disassembler:
  - Emits `org` directive
  - Numeric branch offsets (`+$nn`, `-$nn`)
  - `.a` suffixes for absolute zero-page addressing
  - Pure assembly output (no address/hex columns)

#### 3. Integrated Macro System
A fully integrated, multi-pass macro engine with built-in macros:
- `text_string` - Null-terminated ASCII strings with escape sequences
- `pascal_string` - Length-prefixed strings
- `byte_table`, `word_table` - Data tables (8-bit and 16-bit little-endian)
- `jump_table` - RTS-compatible dispatch tables (addr-1)
- **`apple2_str`** - Apple II high-bit-set strings (critical for Apple II reverse engineering)
- `repeat_byte`, `raw_hex` - Utilities
- `sine_table`, `cosine_table` - Lookup tables

Custom macros supported via Python module import (`.macro name = module.function`)

#### 4. Comprehensive Testing
- 69 passing tests (8 round-trip, 19 CLI integration, 42 macro tests)
- Test coverage: 60% overall, 84% for disassembler, 62% for assembler
- All tests verify binary-identical reassembly

#### 5. Documentation
- **SKILLS.md** - Comprehensive guide for reverse engineering 6502 binaries into literate assembly
- **MACROS.md** - Complete macro system documentation

### Changes from Upstream

#### Added Files
- `py6502/cli_asm6502.py` - Enhanced assembler CLI
- `py6502/cli_dis6502.py` - Disassembler CLI with `--reassemble`
- `py6502/cli_sim6502.py` - Simulator CLI
- `py6502/macro6502.py` - Macro expansion engine
- `py6502/macros_examples.py` - Built-in macro library
- `tests/test_round_trip.py` - Round-trip verification tests
- `tests/test_cli.py` - CLI integration tests
- `tests/test_macros.py` - Macro system tests
- `pyproject.toml` - Modern Python packaging configuration
- `SKILLS.md` - Reverse engineering workflow guide
- `MACROS.md` - Macro system documentation

#### Enhanced Files
- `py6502/asm6502.py` - Added macro support, `.a` suffix, multi-pass assembly, smart diffing
- `py6502/dis6502.py` - Added `--reassemble` mode, symbol loading, multiple output formats
- `py6502/sim6502.py` - Enhanced simulator with better error handling
- `py6502/__init__.py` - Package initialization for CLI tools

#### Moved Files
- `src/*.py` → `py6502/*.py` - Consolidated to single package directory

#### Removed Files (Dead-End Code)
The following files were removed as they were not essential for the SKILLS.md workflow:
- `py6502/debugger.py` - Interactive debugger (374 lines, 0% test coverage)
- `py6502/cli_debugger.py` - Debugger CLI (156 lines, 34% coverage)
- `py6502/termbox_util.py` - Terminal UI library (394 lines, 0% coverage)
- `py6502/py6502_common.py` - Unused common utilities (784 lines, 0% coverage)
- `py6502/scrolltest.py` - Example/test script (16 lines)
- `py6502/small_example.py` - Example script (10 lines)
- `py6502/test6502.py` - Old test script (34 lines)

These removals eliminate **1,768 lines of unused code** while preserving all functionality needed for the SKILLS.md reverse engineering workflow.

### Installation

#### Using pip
```bash
pip install -e .
```

#### Using uv (recommended)
```bash
uv venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
uv pip install -e .
```

### Quick Start

```bash
# Disassemble a binary for reassembly
d6502 program.bin -s 0x0800 --reassemble -o program.asm

# Assemble and verify round-trip
a6502 program.asm -b output.bin --compare original.bin

# Use macros in assembly
echo '.macro apple2_str = py6502.macros_examples.apple2_str
msg: @apple2_str "HELLO WORLD"' | a6502 - -o test.hex
```

### Key Innovation: Round-Trip Verification Loop

```
1. Improve assembly source (add labels, comments, macros)
2. Assemble to binary
3. Diff against original
4. If identical → commit, goto 1
5. If different → fix, goto 2
```

This forces binary-identical reassembly at every step, preventing subtle addressing mode and branch offset errors.

### Credits

- **Original py6502**: David Johnston (dj@deadhat.com) - https://github.com/dj-on-github/py6502/
- **Fork enhancements**: richardkiss - Round-trip verification, macro system, CLI tools, SKILLS.md documentation

### License

BSD-2-Clause (same as upstream)
