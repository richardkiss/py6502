#!/usr/bin/env python3
"""
Command-line interface for the py6502 disassembler.
"""

import argparse
import sys
from pathlib import Path

from py6502.dis6502 import dis6502


def main(argv=None):
    """Command-line interface for the 6502 disassembler."""
    parser = argparse.ArgumentParser(
        description="6502 Disassembler - Disassemble 6502 machine code",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s program.bin                 # Disassemble entire file from $0000
  %(prog)s program.bin -s 0x8000       # Start at $8000
  %(prog)s program.bin -s 0x8000 -l 256 # Disassemble 256 bytes
  %(prog)s program.bin --offset 0x100 -s 0x8000 # Skip first 256 bytes of file, start disassembly at $8000
  %(prog)s program.bin -o listing.asm  # Save to file
        """,
    )

    parser.add_argument("input_file", help="Input binary file to disassemble")
    parser.add_argument(
        "-s",
        "--start",
        type=lambda x: int(x, 0),
        default=0,
        help="Start address (default: 0, can use hex with 0x prefix)",
    )
    parser.add_argument(
        "--offset",
        type=lambda x: int(x, 0),
        default=0,
        help="File offset to start reading from (default: 0, can use hex with 0x prefix)",
    )
    parser.add_argument(
        "-l",
        "--length",
        type=int,
        help="Number of bytes to disassemble (default: entire file from offset)",
    )
    parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    parser.add_argument(
        "-f",
        "--format",
        choices=["asm", "hex", "both"],
        default="asm",
        help="Output format (default: asm)",
    )
    parser.add_argument("--symbols", help="Symbol file to use for labels")

    args = parser.parse_args(argv)

    # Check input file exists
    input_path = Path(args.input_file)
    if not input_path.exists():
        print(f"Error: Input file '{args.input_file}' not found.", file=sys.stderr)
        return 1

    # Read binary file
    try:
        with open(input_path, "rb") as f:
            # Seek to the specified offset
            if args.offset > 0:
                f.seek(args.offset)
            data = f.read()
    except Exception as e:
        print(f"Error reading input file: {e}", file=sys.stderr)
        return 1

    if len(data) == 0:
        print(
            "Error: No data to disassemble (file empty or offset beyond end of file).",
            file=sys.stderr,
        )
        return 1

    # Load symbols if provided
    symbols = {}
    if args.symbols:
        try:
            with open(args.symbols, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if "=" in line and not line.startswith("#"):
                        parts = line.split("=")
                        if len(parts) == 2:
                            name = parts[0].strip()
                            value_str = parts[1].strip()
                            # Handle hex values
                            if value_str.startswith("$"):
                                value = int(value_str[1:], 16)
                            elif value_str.startswith("0x"):
                                value = int(value_str, 16)
                            else:
                                value = int(value_str)
                            symbols[name] = value
        except Exception as e:
            print(f"Warning: Error reading symbol file: {e}", file=sys.stderr)

    # Create disassembler instance - need to provide object_code array
    object_code = [0] * 65536  # Initialize 64K memory

    # Load binary data into object_code
    for i, byte in enumerate(data):
        if args.start + i < len(object_code):
            object_code[args.start + i] = byte

    disassembler = dis6502(object_code)

    # Load symbols into disassembler
    if symbols:
        disassembler.symbols = symbols
        # Create reverse lookup for labels
        disassembler.labels = {v: k for k, v in symbols.items()}

    # Determine length to disassemble
    length = args.length if args.length else len(data)
    if length > len(data):
        length = len(data)

    # Show info about what we're disassembling (to stderr so it doesn't interfere with output)
    if args.offset > 0:
        print(
            f"Disassembling {length} bytes from file offset 0x{args.offset:X} (address range: ${args.start:04X}-${args.start + length - 1:04X})",
            file=sys.stderr,
        )
    else:
        print(
            f"Disassembling {length} bytes (address range: ${args.start:04X}-${args.start + length - 1:04X})",
            file=sys.stderr,
        )

    try:
        # Disassemble the region
        lines = []

        if args.format in ["asm", "both"]:
            # Generate assembly listing
            for line in disassembler.disassemble_region(args.start, length):
                lines.append(line)

        if args.format == "hex":
            # Generate hex dump
            for i in range(0, length, 16):
                addr = args.start + i
                hex_bytes = []
                ascii_chars = []

                for j in range(16):
                    if i + j < length:
                        byte = data[i + j]
                        hex_bytes.append(f"{byte:02X}")
                        ascii_chars.append(chr(byte) if 32 <= byte <= 126 else ".")
                    else:
                        hex_bytes.append("  ")
                        ascii_chars.append(" ")

                hex_part = " ".join(hex_bytes[:8]) + "  " + " ".join(hex_bytes[8:])
                ascii_part = "".join(ascii_chars)
                lines.append(f"{addr:04X}: {hex_part:<48} |{ascii_part}|")

        elif args.format == "both":
            lines.append("")
            lines.append("=== HEX DUMP ===")
            # Add hex dump after assembly
            for i in range(0, length, 16):
                addr = args.start + i
                hex_bytes = []
                ascii_chars = []

                for j in range(16):
                    if i + j < length:
                        byte = data[i + j]
                        hex_bytes.append(f"{byte:02X}")
                        ascii_chars.append(chr(byte) if 32 <= byte <= 126 else ".")
                    else:
                        hex_bytes.append("  ")
                        ascii_chars.append(" ")

                hex_part = " ".join(hex_bytes[:8]) + "  " + " ".join(hex_bytes[8:])
                ascii_part = "".join(ascii_chars)
                lines.append(f"{addr:04X}: {hex_part:<48} |{ascii_part}|")

        # Output results
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                for line in lines:
                    f.write(line + "\n")
            print(f"Disassembly written to: {args.output}")
        else:
            for line in lines:
                print(line)

    except Exception as e:
        print(f"Disassembly error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
