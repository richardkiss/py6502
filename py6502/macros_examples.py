#!/usr/bin/env python3
"""
macros_examples.py - Example macro implementations for 6502 assembly

These functions can be used with the macro system:
  .macro text_string = py6502.macros_examples.text_string
  @text_string "hello world"

Macro functions receive:
  - args: list of string arguments
  - context: optional dict with 'org', 'addr', 'labels'

Each function returns:
  - list of bytes
  - OR string (assembly code)
  - OR None
"""


def text_string(args, context=None, pass_num=2):
    """
    Expand a null-terminated text string.

    Usage: @text_string "hello"

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: bytes for string + null terminator
    """
    if not args or len(args) == 0:
        raise ValueError("text_string requires a string argument")

    text_arg = args[0]

    # Remove quotes
    if (text_arg.startswith('"') and text_arg.endswith('"')) or (
        text_arg.startswith("'") and text_arg.endswith("'")
    ):
        text = text_arg[1:-1]
    else:
        text = text_arg

    # Process escape sequences
    text = text.replace("\\n", "\n")
    text = text.replace("\\r", "\r")
    text = text.replace("\\t", "\t")
    text = text.replace("\\0", "\x00")
    text = text.replace("\\\\", "\\")

    # Convert to bytes and add null terminator
    result = [ord(c) for c in text]
    result.append(0)
    return result


def pascal_string(args, context=None, pass_num=2):
    """
    Expand a Pascal-style length-prefixed string.

    Usage: @pascal_string "hello"

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: length byte + string bytes (no null terminator)
    """
    if not args or len(args) == 0:
        raise ValueError("pascal_string requires a string argument")

    text_arg = args[0]

    # Remove quotes
    if (text_arg.startswith('"') and text_arg.endswith('"')) or (
        text_arg.startswith("'") and text_arg.endswith("'")
    ):
        text = text_arg[1:-1]
    else:
        text = text_arg

    # Process escape sequences
    text = text.replace("\\n", "\n")
    text = text.replace("\\r", "\r")
    text = text.replace("\\t", "\t")
    text = text.replace("\\\\", "\\")

    # Length byte + string bytes
    result = [len(text)]
    result.extend([ord(c) for c in text])
    return result


def word_table(args, context=None, pass_num=2):
    """
    Expand a table of 16-bit words (little-endian).

    Usage: @word_table $1234, $5678, label_name

    Args:
        args: list of arguments
        context: optional assembly context (contains labels on pass 2)
        pass_num: assembly pass (1 or 2)

    Returns: bytes for words in little-endian format
    """
    if not args or len(args) == 0:
        raise ValueError("word_table requires at least one argument")

    result = []
    for arg in args:
        arg = arg.strip()

        # Try to resolve label if context provided
        if context and arg in context.get("labels", {}):
            value = context["labels"][arg]
        elif arg.startswith("$"):
            value = int(arg[1:], 16)
        elif arg.startswith("@"):
            value = int(arg[1:], 8)
        else:
            try:
                value = int(arg, 0)
            except ValueError:
                raise ValueError(f"Cannot parse word value: {arg}")

        # Little-endian 16-bit
        result.append(value & 0xFF)
        result.append((value >> 8) & 0xFF)

    return result


def byte_table(args, context=None, pass_num=2):
    """
    Expand a table of 8-bit bytes.

    Usage: @byte_table $12, $34, $56

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: list of bytes
    """
    if not args or len(args) == 0:
        raise ValueError("byte_table requires at least one argument")

    result = []
    for arg in args:
        arg = arg.strip()

        if arg.startswith("$"):
            value = int(arg[1:], 16)
        elif arg.startswith("@"):
            value = int(arg[1:], 8)
        else:
            try:
                value = int(arg, 0)
            except ValueError:
                raise ValueError(f"Cannot parse byte value: {arg}")

        if not (0 <= value <= 255):
            raise ValueError(f"Byte value out of range: {arg}")

        result.append(value)

    return result


def jump_table(args, context=None, pass_num=2):
    """
    Expand a jump table (16-bit addresses in little-endian).
    Used for jump dispatch tables.

    Usage: @jump_table routine_a, routine_b, routine_c

    Args:
        args: list of arguments
        context: optional assembly context (contains labels on pass 2)
        pass_num: assembly pass (1 or 2)

    Returns: bytes for addresses in little-endian format
    """
    if not args or len(args) == 0:
        raise ValueError("jump_table requires at least one argument")

    result = []
    for arg in args:
        arg = arg.strip()

        # Try to resolve label if context provided
        if context and arg in context.get("labels", {}):
            addr = context["labels"][arg]
        elif arg.startswith("$"):
            addr = int(arg[1:], 16)
        else:
            # Assume it's a label name
            if context and arg in context.get("labels", {}):
                addr = context["labels"][arg]
            else:
                raise ValueError(f"Cannot resolve label: {arg}")

        # Jump tables are typically address - 1 (for RTS to work properly)
        addr = addr - 1

        # Little-endian 16-bit
        result.append(addr & 0xFF)
        result.append((addr >> 8) & 0xFF)

    return result


def sine_table(args, context=None, pass_num=2):
    """
    Generate a sine wave lookup table (0-255 mapped to 0-360 degrees).

    Usage: @sine_table
    OR:    @sine_table 256   (number of entries, default 256)

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: 256 bytes representing sine values scaled to 0-255
    """
    import math

    count = 256
    if args and len(args) > 0:
        try:
            count = int(args[0], 0)
        except ValueError:
            pass

    result = []
    for i in range(count):
        angle = (i / count) * 2 * math.pi
        # Scale sine (-1 to 1) to unsigned byte (0 to 255)
        value = int((math.sin(angle) + 1) * 127.5)
        result.append(value & 0xFF)

    return result


def cosine_table(args, context=None, pass_num=2):
    """
    Generate a cosine wave lookup table (0-255 mapped to 0-360 degrees).

    Usage: @cosine_table
    OR:    @cosine_table 256

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: 256 bytes representing cosine values scaled to 0-255
    """
    import math

    count = 256
    if args and len(args) > 0:
        try:
            count = int(args[0], 0)
        except ValueError:
            pass

    result = []
    for i in range(count):
        angle = (i / count) * 2 * math.pi
        # Scale cosine (-1 to 1) to unsigned byte (0 to 255)
        value = int((math.cos(angle) + 1) * 127.5)
        result.append(value & 0xFF)

    return result


def repeat_byte(args, context=None, pass_num=2):
    """
    Repeat a byte N times.

    Usage: @repeat_byte $FF, 16    (repeat $FF 16 times)

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: list of repeated bytes
    """
    if not args or len(args) < 2:
        raise ValueError("repeat_byte requires: @repeat_byte value, count")

    byte_arg = args[0].strip()
    count_arg = args[1].strip()

    # Parse byte value
    if byte_arg.startswith("$"):
        byte_val = int(byte_arg[1:], 16)
    else:
        byte_val = int(byte_arg, 0)

    if not (0 <= byte_val <= 255):
        raise ValueError(f"Byte value out of range: {byte_arg}")

    # Parse count
    count = int(count_arg, 0)
    if count < 0:
        raise ValueError(f"Count cannot be negative: {count_arg}")

    return [byte_val] * count


def raw_hex(args, context=None, pass_num=2):
    """
    Insert raw hex bytes.

    Usage: @raw_hex 48 65 6C 6C 6F   (hex bytes for "Hello")

    Args:
        args: list of arguments
        context: optional assembly context
        pass_num: assembly pass (1 or 2)

    Returns: list of bytes
    """
    if not args or len(args) == 0:
        raise ValueError("raw_hex requires at least one byte")

    result = []
    for arg in args:
        arg = arg.strip()

        if arg.startswith("$"):
            value = int(arg[1:], 16)
        else:
            value = int(arg, 16)

        if not (0 <= value <= 255):
            raise ValueError(f"Byte value out of range: {arg}")

        result.append(value)

    return result
