#!/usr/bin/env python3
"""
Command-line interface for the py6502 debugger.
"""

import argparse
import sys
from pathlib import Path

from py6502.asm6502 import asm6502
from py6502.dis6502 import dis6502
from py6502.sim6502 import sim6502


def simple_debugger(simulator, disassembler, symbols=None):
    """Simple text-based debugger interface."""
    print("\n=== py6502 Simple Debugger ===")
    print(
        "Commands: step (s), run (r), registers (reg), memory (mem <addr>), quit (q), help (h)"
    )

    try:
        while True:
            # Show current instruction
            pc = simulator.pc
            try:
                line, length = disassembler.disassemble_line(pc)
                print(f"\nPC=${pc:04X}: {line}")
            except Exception:
                print(f"\nPC=${pc:04X}: ???")

            # Show registers
            print(
                f"A=${simulator.a:02X} X=${simulator.x:02X} Y=${simulator.y:02X} SP=${simulator.sp:02X} F=${simulator.cc:02X}"
            )

            # Get user command
            try:
                cmd = input("dbg> ").strip().lower()
            except (KeyboardInterrupt, EOFError, OSError):
                # Handle the case where input is not available (e.g., during testing)
                print("\nNo input available. Exiting debugger.")
                return 1

            if not cmd:
                continue

            parts = cmd.split()
            command = parts[0]

            if command in ["q", "quit", "exit"]:
                break
            elif command in ["s", "step"]:
                try:
                    # Check for BRK
                    if simulator.memory_map.Read(pc) == 0x00:
                        print("BRK instruction - execution stopped")
                        break
                    simulator.execute()
                except Exception as e:
                    print(f"Execution error: {e}")
            elif command in ["r", "run"]:
                steps = 1000
                if len(parts) > 1:
                    try:
                        steps = int(parts[1])
                    except ValueError:
                        print("Invalid step count")
                        continue

                print(f"Running {steps} steps...")
                for i in range(steps):
                    try:
                        # Check for BRK
                        if simulator.memory_map.Read(simulator.pc) == 0x00:
                            print(f"BRK instruction at step {i}")
                            break
                        simulator.execute()
                    except Exception as e:
                        print(f"Execution error at step {i}: {e}")
                        break
            elif command in ["reg", "registers"]:
                print(f"PC = ${simulator.pc:04X}")
                print(f"A  = ${simulator.a:02X} ({simulator.a})")
                print(f"X  = ${simulator.x:02X} ({simulator.x})")
                print(f"Y  = ${simulator.y:02X} ({simulator.y})")
                print(f"SP = ${simulator.sp:02X}")
                flags = simulator.cc
                print(
                    f"Flags = ${flags:02X} N:{(flags >> 7) & 1} V:{(flags >> 6) & 1} B:{(flags >> 4) & 1} D:{(flags >> 3) & 1} I:{(flags >> 2) & 1} Z:{(flags >> 1) & 1} C:{flags & 1}"
                )
            elif command == "mem":
                if len(parts) < 2:
                    addr = simulator.pc
                else:
                    try:
                        addr = int(parts[1], 0)  # Support hex with 0x
                    except ValueError:
                        print("Invalid address")
                        continue

                print(f"Memory at ${addr:04X}:")
                for i in range(4):  # Show 4 lines of 8 bytes each
                    line_addr = addr + i * 8
                    values = []
                    ascii_chars = []
                    for j in range(8):
                        byte_addr = line_addr + j
                        try:
                            value = simulator.memory_map.Read(byte_addr)
                            values.append(f"{value:02X}")
                            ascii_chars.append(
                                chr(value) if 32 <= value <= 126 else "."
                            )
                        except Exception:
                            values.append("??")
                            ascii_chars.append("?")
                    hex_str = " ".join(values)
                    ascii_str = "".join(ascii_chars)
                    print(f"  ${line_addr:04X}: {hex_str:<23} |{ascii_str}|")
            elif command in ["h", "help"]:
                print("Commands:")
                print("  step, s          - Execute one instruction")
                print("  run [steps], r   - Run multiple steps (default: 1000)")
                print("  registers, reg   - Show CPU registers")
                print("  mem [addr]       - Show memory (default: current PC)")
                print("  quit, q          - Exit debugger")
                print("  help, h          - Show this help")
            else:
                print(
                    f"Unknown command: {command}. Type 'help' for available commands."
                )
    except Exception as e:
        print(f"Debugger error: {e}", file=sys.stderr)
        return 1

    return 0


def main(argv=None):
    """Command-line interface for the 6502 debugger."""
    parser = argparse.ArgumentParser(
        description="6502 Debugger - Debug 6502 assembly code execution",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s program.asm                 # Debug program.asm
  %(prog)s program.asm -s 0x8000       # Start execution at $8000
  %(prog)s program.asm --simple        # Use simple text debugger
        """,
    )

    parser.add_argument("input_file", help="Input assembly file to debug")
    parser.add_argument(
        "-s",
        "--start",
        type=lambda x: int(x, 0),
        default=0x0200,
        help="Start execution address (default: 0x0200)",
    )
    parser.add_argument(
        "--simple", action="store_true", help="Use simple text-based debugger interface"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose assembly output"
    )

    args = parser.parse_args(argv)

    # Check input file exists
    input_path = Path(args.input_file)
    if not input_path.exists():
        print(f"Error: Input file '{args.input_file}' not found.", file=sys.stderr)
        return 1

    # Read and assemble the file
    try:
        with open(input_path, encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading input file: {e}", file=sys.stderr)
        return 1

    # Assemble the code
    assembler = asm6502()
    try:
        assembled_lines, summary = assembler.assemble(lines)
        object_code = assembler.object_code
        symbols = assembler.symbols

        if args.verbose:
            print("=== Assembly Listing ===")
            for line in assembled_lines:
                print(line)
            print("\n=== Assembly Summary ===")
            for line in summary:
                print(line)

        print(
            f"Assembly successful. {len([b for b in object_code if b is not None])} bytes generated."
        )

    except Exception as e:
        print(f"Assembly error: {e}", file=sys.stderr)
        return 1

    # Create simulator and disassembler instances
    try:
        simulator = sim6502(object_code, address=0, symbols=symbols)
        simulator.pc = args.start

        disassembler = dis6502(object_code)
        # Load symbols
        if symbols:
            disassembler.symbols = symbols
            disassembler.labels = {v: k for k, v in symbols.items()}

    except Exception as e:
        print(f"Debugger initialization error: {e}", file=sys.stderr)
        return 1

    print(f"Debugger initialized. Starting at address: ${args.start:04X}")

    # Choose debugger interface
    result = 0
    if args.simple:
        result = simple_debugger(simulator, disassembler, symbols)
    else:
        # Try to use the original termbox-based debugger if available
        try:
            # This would import the original debugger function
            # For now, fall back to simple debugger
            print(
                "Note: Advanced debugger interface not available. Using simple debugger."
            )
            result = simple_debugger(simulator, disassembler, symbols)
        except ImportError:
            print(
                "Note: Advanced debugger interface not available. Using simple debugger."
            )
            result = simple_debugger(simulator, disassembler, symbols)

    print("Debugger session ended.")
    return result


if __name__ == "__main__":
    sys.exit(main())
