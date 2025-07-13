"""
py6502 - A Python-based 6502 assembler, simulator, disassembler, and debugger.

This package provides comprehensive tools for working with 6502 assembly code:
- Assembler (asm6502): Assemble 6502 assembly code
- Simulator (sim6502): Simulate 6502 CPU execution
- Disassembler (dis6502): Disassemble 6502 machine code
- Debugger (debugger): Debug 6502 code execution

CLI tools are available as:
- a6502: Assembler
- s6502: Simulator
- d6502: Disassembler
- db6502: Debugger
"""

__version__ = "1.0.0"
__author__ = "David Johnston"
__email__ = "dj@deadhat.com"

# Import main modules for convenience
from . import asm6502
from . import sim6502
from . import dis6502
