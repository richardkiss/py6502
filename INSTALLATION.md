# Installation Guide

## Quick Start

### Using uv (Recommended)

```bash
# Create virtual environment
uv venv

# Activate virtual environment
source .venv/bin/activate  # On Linux/macOS
# or
.venv\Scripts\activate     # On Windows

# Install package
uv pip install -e .
```

### Using pip

```bash
# Create virtual environment (optional but recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Linux/macOS

# Install package
pip install -e .
```

## Verification

After installation, verify the CLI tools are available:

```bash
# Check assembler
a6502 --help

# Check disassembler
d6502 --help

# Check simulator
s6502 --help
```

## Running Tests

```bash
# Install test dependencies
pip install pytest pytest-cov

# Run all tests
pytest tests/

# Run specific test suite
pytest tests/test_round_trip.py
pytest tests/test_macros.py
pytest tests/test_cli.py
```

## Quick Example

Create a simple assembly file with macros:

```bash
cat > hello.asm << 'EOF'
org $0800
.macro apple2_str = py6502.macros_examples.apple2_str

message:
    @apple2_str "HELLO WORLD"
EOF

# Assemble it
a6502 hello.asm -b hello.bin -v

# Disassemble it
d6502 hello.bin -s 0x0800 --reassemble
```

## Documentation

- **SKILLS.md** - Complete workflow for reverse engineering 6502 binaries
- **MACROS.md** - Macro system documentation
- **CHANGELOG.md** - List of enhancements from upstream
- **FORK_REVIEW.md** - Review summary and recommendations

## CLI Tools

### a6502 - Assembler
```bash
a6502 input.asm -b output.bin --compare original.bin
```

### d6502 - Disassembler
```bash
d6502 program.bin -s 0x0800 --reassemble -o program.asm
```

### s6502 - Simulator
```bash
s6502 program.bin -s 0x0800 --trace
```
