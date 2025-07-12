#!/usr/bin/env python3
"""
Command-line interface for the py6502 simulator.
"""

import argparse
import sys
from pathlib import Path

from py6502.asm6502 import asm6502
from py6502.sim6502 import sim6502

# 6502 opcodes that can change PC (branches, jumps, subroutine calls)
BRANCHING_OPCODES = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0, 0x4C, 0x6C, 0x20}


def main(argv=None):
    """Command-line interface for the 6502 simulator."""
    parser = argparse.ArgumentParser(
        description="6502 Simulator - Execute 6502 assembly code",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s program.asm                 # Assemble and run
  %(prog)s program.asm -s 0x8000       # Start execution at $8000
  %(prog)s program.asm -d              # Debug mode (step by step)
  %(prog)s program.asm --steps 1000    # Limit to 1000 steps
        """,
    )

    parser.add_argument("input_file", help="Input assembly file to simulate")
    parser.add_argument(
        "-s",
        "--start",
        type=lambda x: int(x, 0),
        default=0x0200,
        help="Start execution address (default: 0x0200)",
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Debug mode - show each instruction"
    )
    parser.add_argument(
        "--steps",
        type=int,
        default=10000,
        help="Maximum number of steps (default: 10000)",
    )
    parser.add_argument(
        "-i",
        "--interactive",
        action="store_true",
        help="Interactive mode - pause after each instruction",
    )
    parser.add_argument("--trace", help="Write execution trace to file")

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
        assembler.assemble(lines)
        object_code = assembler.object_code
        symbols = assembler.symbols
        print(
            f"Assembly successful. {len([b for b in object_code if b is not None])} bytes generated."
        )
    except Exception as e:
        print(f"Assembly error: {e}", file=sys.stderr)
        return 1

    # Create simulator instance
    try:
        simulator = sim6502(object_code, address=0, symbols=symbols)
        simulator.pc = args.start
    except Exception as e:
        print(f"Simulator initialization error: {e}", file=sys.stderr)
        return 1

    print(f"Starting simulation at address: ${args.start:04X}")
    if args.debug or args.interactive:
        print("Debug mode enabled. Showing CPU state for each instruction.")

    # Open trace file if requested
    trace_file = None
    if args.trace:
        try:
            trace_file = open(args.trace, "w", encoding="utf-8")
            trace_file.write("Step\tPC\tA\tX\tY\tSP\tFlags\tInstruction\n")
        except Exception as e:
            print(f"Error opening trace file: {e}", file=sys.stderr)
            return 1

    step_count = 0

    try:
        while step_count < args.steps:
            # Get current state
            pc = simulator.pc
            a_reg = simulator.a
            x_reg = simulator.x
            y_reg = simulator.y
            sp = simulator.sp
            flags = simulator.cc

            # Get current instruction for display
            current_opcode = simulator.memory_map.Read(pc)

            # Show debug info if requested
            if args.debug or args.interactive:
                print(
                    f"Step {step_count:5d}: PC=${pc:04X} A=${a_reg:02X} X=${x_reg:02X} Y=${y_reg:02X} SP=${sp:02X} F=${flags:02X}"
                )

            # Write to trace file if requested
            if trace_file:
                trace_file.write(
                    f"{step_count}\t${pc:04X}\t${a_reg:02X}\t${x_reg:02X}\t${y_reg:02X}\t${sp:02X}\t${flags:02X}\t${current_opcode:02X}\n"
                )

            # Interactive mode - wait for user input
            if args.interactive:
                try:
                    user_input = (
                        input("Press Enter to continue, 'q' to quit: ").strip().lower()
                    )
                    if user_input == "q":
                        break
                except KeyboardInterrupt:
                    break

            # Check for BRK instruction before executing
            if current_opcode == 0x00:  # BRK
                print(f"BRK instruction encountered at step {step_count}")
                break

            # Execute one instruction
            try:
                simulator.execute()
            except Exception as e:
                print(f"Execution error at step {step_count}: {e}", file=sys.stderr)
                break

            step_count += 1

            # Check for infinite loop (PC didn't change and not a branch/jump)
            if simulator.pc == pc and current_opcode not in BRANCHING_OPCODES:
                print(f"Warning: Possible infinite loop detected at step {step_count}")
                if not args.interactive:
                    break
                    break

    except KeyboardInterrupt:
        print(f"\nSimulation interrupted by user at step {step_count}")

    # Close trace file
    if trace_file:
        trace_file.close()
        print(f"Execution trace written to: {args.trace}")

    # Final state
    print(f"\nSimulation completed after {step_count} steps")
    print("Final CPU state:")
    print(f"  PC = ${simulator.pc:04X}")
    print(f"  A  = ${simulator.a:02X} ({simulator.a})")
    print(f"  X  = ${simulator.x:02X} ({simulator.x})")
    print(f"  Y  = ${simulator.y:02X} ({simulator.y})")
    print(f"  SP = ${simulator.sp:02X}")
    print(
        f"  Flags = ${simulator.cc:02X} (N:{(simulator.cc >> 7) & 1} V:{(simulator.cc >> 6) & 1} B:{(simulator.cc >> 4) & 1} D:{(simulator.cc >> 3) & 1} I:{(simulator.cc >> 2) & 1} Z:{(simulator.cc >> 1) & 1} C:{simulator.cc & 1})"
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
