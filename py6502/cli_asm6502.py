#!/usr/bin/env python3
"""
Command-line interface for the py6502 assembler.
"""

import argparse
import sys
from pathlib import Path

from py6502.asm6502 import asm6502


def main(argv=None):
    """Command-line interface for the 6502 assembler."""
    parser = argparse.ArgumentParser(
        description="6502 Assembler - Assemble 6502 assembly code",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s code.asm                    # Assemble to code.hex
  %(prog)s code.asm -o program.hex     # Assemble to program.hex
  %(prog)s code.asm -b program.bin     # Generate binary output too
  %(prog)s code.asm -v                 # Verbose output
  %(prog)s code.asm -b program.bin --compare original.bin  # Verify with smart diff
        """,
    )

    parser.add_argument("input_file", help="Input assembly file")
    parser.add_argument(
        "-o", "--output", help="Output hex file (default: input_file.hex)"
    )
    parser.add_argument(
        "-b", "--binary", help="Output binary file (in addition to hex file)"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Show detailed assembly output"
    )
    parser.add_argument(
        "--debug",
        type=int,
        default=0,
        metavar="LEVEL",
        help="Debug level (0-3, default: 0)",
    )
    parser.add_argument("--listing", help="Generate assembly listing file")
    parser.add_argument("--symbols", help="Generate symbol table file")
    parser.add_argument(
        "--compare",
        metavar="ORIGINAL",
        help="Compare assembled binary against original with smart diff analysis (requires -b flag)",
    )

    args = parser.parse_args(argv)

    # Check input file exists
    input_path = Path(args.input_file)
    if not input_path.exists():
        print(f"Error: Input file '{args.input_file}' not found.", file=sys.stderr)
        return 1

    # Check compare flag requirements
    if args.compare and not args.binary:
        print(f"Error: --compare requires --binary flag to be set.", file=sys.stderr)
        return 1

    if args.compare:
        compare_path = Path(args.compare)
        if not compare_path.exists():
            print(f"Error: Compare file '{args.compare}' not found.", file=sys.stderr)
            return 1

    # Read input file
    try:
        with open(input_path, encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading input file: {e}", file=sys.stderr)
        return 1

    # Create assembler instance
    assembler = asm6502(debug=args.debug)

    try:
        # Assemble the code
        (assembled_lines, summary) = assembler.assemble(lines)

        if args.verbose:
            print("=== Assembly Listing ===")
            for line in assembled_lines:
                print(line)
            print("\n=== Assembly Summary ===")
            for line in summary:
                print(line)
            print()

        # Determine output file
        if args.output:
            output_path = Path(args.output)
        else:
            output_path = input_path.with_suffix(".hex")

        # Write hex output
        try:
            with open(output_path, "w", encoding="utf-8") as f:
                hex_lines = assembler.hex()
                for line in hex_lines:
                    f.write(line + "\n")
            print(f"Assembly successful. Output written to: {output_path}")
        except Exception as e:
            print(f"Error writing output file: {e}", file=sys.stderr)
            return 1

        # Write binary output if requested
        if args.binary:
            try:
                binary_path = Path(args.binary)
                # Get the raw binary data from the assembler
                # Find the range of used memory
                used_addresses = [
                    i for i, val in enumerate(assembler.object_code) if val != -1
                ]

                if used_addresses:
                    min_addr = min(used_addresses)
                    max_addr = max(used_addresses)

                    # Only write the bytes that were actually assembled (no padding)
                    with open(binary_path, "wb") as f:
                        for address in range(min_addr, max_addr + 1):
                            if assembler.object_code[address] != -1:
                                f.write(bytes([assembler.object_code[address]]))
                    print(
                        f"Binary file written to: {binary_path} (addresses ${min_addr:04X}-${max_addr:04X}, length {max_addr - min_addr + 1})"
                    )
                else:
                    print("No object code generated, skipping binary output.")
            except Exception as e:
                print(f"Error writing binary file: {e}", file=sys.stderr)
                return 1

        # Generate optional listing file
        if args.listing:
            try:
                with open(args.listing, "w", encoding="utf-8") as f:
                    for line in assembled_lines:
                        f.write(line + "\n")
                print(f"Assembly listing written to: {args.listing}")
            except Exception as e:
                print(f"Error writing listing file: {e}", file=sys.stderr)
                return 1

        # Generate optional symbol table
        if args.symbols:
            try:
                with open(args.symbols, "w", encoding="utf-8") as f:
                    f.write("Symbol Table:\n")
                    f.write("=============\n")
                    for symbol, value in sorted(assembler.symbols.items()):
                        f.write(f"{symbol:<20} = ${value:04X} ({value})\n")
                print(f"Symbol table written to: {args.symbols}")
            except Exception as e:
                print(f"Error writing symbol file: {e}", file=sys.stderr)
                return 1

        # Compare against original binary if requested
        if args.compare:
            try:
                from py6502.diff6502 import Diff6502

                differ = Diff6502()
                result = differ.compare_files(
                    args.compare, args.binary, min_addr if used_addresses else 0
                )

                if result.get("identical"):
                    print(f"\n✓ ROUND-TRIP VERIFICATION SUCCESSFUL!")
                    print(f"  Assembled binary matches original: {args.compare}")
                else:
                    print(f"\n✗ ROUND-TRIP VERIFICATION FAILED!")
                    print(f"  Assembled binary differs from original: {args.compare}")
                    print()

                    # Print smart diff summary
                    if result.get("differences"):
                        print(f"Differences: {result['differences']} byte(s)")
                        print(f"Original size:  {result['original_size']} bytes")
                        print(f"Assembled size: {result['assembled_size']} bytes")

                        if result.get("first_diff"):
                            diff = result["first_diff"]
                            print(
                                f"\nFirst difference at offset 0x{diff['offset']:04X}:"
                            )
                            print(f"  Original:  ${diff['byte1']:02X}")
                            print(f"  Assembled: ${diff['byte2']:02X}")

                        if "length_diff" in result:
                            ld = result["length_diff"]
                            longer = (
                                "assembled"
                                if ld["shorter"] == "original"
                                else "original"
                            )
                            print(
                                f"\nLength difference: {ld['extra_bytes']} extra bytes in {longer} file"
                            )

                        # Print detected patterns
                        if result.get("patterns"):
                            print("\nDetected patterns:")
                            for pattern in result["patterns"]:
                                severity = f"[{pattern['severity']}]"
                                print(f"  {severity} {pattern['type']}")
                                print(f"       {pattern['description']}")

                        print(f"\nRun for more details:")
                        print(
                            f"  python3 py6502/cli_diff6502.py {args.compare} {args.binary} -v"
                        )

                    return 1
            except Exception as e:
                print(f"Error during comparison: {e}", file=sys.stderr)
                return 1

    except Exception as e:
        print(f"Assembly error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
