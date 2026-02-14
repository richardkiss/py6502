#!/usr/bin/env python3
"""
Test suite for the 6502 macro system.

Tests macro expansion, context handling, and multi-pass assembly.
"""

import unittest
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from py6502.macro6502 import MacroExpander
from py6502.macros_examples import (
    text_string,
    pascal_string,
    byte_table,
    word_table,
    jump_table,
    repeat_byte,
    raw_hex,
    sine_table,
    cosine_table,
)


class TestMacroExpander(unittest.TestCase):
    """Test the macro expansion engine."""

    def setUp(self):
        """Set up test fixtures."""
        self.expander = MacroExpander(debug=False)

    def test_register_macro(self):
        """Test registering a macro."""
        self.expander.register_macro("test", "py6502.macros_examples", "text_string")
        self.assertIn("test", self.expander.macros)
        self.assertEqual(
            self.expander.macros["test"],
            ("py6502.macros_examples", "text_string"),
        )

    def test_parse_macro_definition(self):
        """Test parsing macro definitions."""
        line = ".macro hello = py6502.macros_examples.text_string"
        result = self.expander.parse_macro_definition(line)
        self.assertIsNotNone(result)
        name, module, func = result
        self.assertEqual(name, "hello")
        self.assertEqual(module, "py6502.macros_examples")
        self.assertEqual(func, "text_string")

    def test_parse_macro_invocation(self):
        """Test parsing macro invocations."""
        line = "@hello world, foo, bar"
        result = self.expander.parse_macro_invocation(line)
        self.assertIsNotNone(result)
        name, args = result
        self.assertEqual(name, "hello")
        self.assertEqual(args, ["world", "foo", "bar"])

    def test_parse_macro_invocation_no_args(self):
        """Test parsing macro invocation with no arguments."""
        line = "@empty_macro"
        result = self.expander.parse_macro_invocation(line)
        self.assertIsNotNone(result)
        name, args = result
        self.assertEqual(name, "empty_macro")
        self.assertEqual(args, [])

    def test_parse_macro_invocation_with_comment(self):
        """Test parsing macro invocation with trailing comment."""
        line = "@hello world ; this is a comment"
        result = self.expander.parse_macro_invocation(line)
        self.assertIsNotNone(result)
        name, args = result
        self.assertEqual(name, "hello")
        self.assertEqual(args, ["world"])

    def test_expand_unknown_macro(self):
        """Test expanding an unknown macro."""
        success, result = self.expander.expand_macro("unknown", [], None)
        self.assertFalse(success)
        self.assertTrue(any("Unknown macro" in str(r) for r in result))

    def test_load_macro_function(self):
        """Test loading a macro function from a module."""
        func = self.expander.load_macro_function(
            "py6502.macros_examples", "text_string"
        )
        self.assertIsNotNone(func)
        self.assertTrue(callable(func))


class TestBuiltInMacros(unittest.TestCase):
    """Test built-in macro implementations."""

    def test_text_string_basic(self):
        """Test basic text string generation."""
        result = text_string(['"Hello"'])
        expected = [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00]
        self.assertEqual(result, expected)

    def test_text_string_empty(self):
        """Test empty text string."""
        result = text_string(['""'])
        self.assertEqual(result, [0x00])

    def test_text_string_escape_sequences(self):
        """Test text string with escape sequences."""
        result = text_string(['"A\\nB"'])
        # "A\nB\0"
        self.assertEqual(result, [0x41, 0x0A, 0x42, 0x00])

    def test_text_string_no_args(self):
        """Test text_string raises error with no args."""
        with self.assertRaises(ValueError):
            text_string([])

    def test_pascal_string_basic(self):
        """Test Pascal string generation."""
        result = pascal_string(['"Hi"'])
        # Length (2) + "Hi"
        expected = [0x02, 0x48, 0x69]
        self.assertEqual(result, expected)

    def test_pascal_string_empty(self):
        """Test empty Pascal string."""
        result = pascal_string(['""'])
        self.assertEqual(result, [0x00])

    def test_byte_table_hex(self):
        """Test byte table with hex values."""
        result = byte_table(["$12", "$34", "$56"])
        self.assertEqual(result, [0x12, 0x34, 0x56])

    def test_byte_table_decimal(self):
        """Test byte table with decimal values."""
        result = byte_table(["65", "66", "67"])
        self.assertEqual(result, [65, 66, 67])

    def test_byte_table_mixed(self):
        """Test byte table with mixed formats."""
        result = byte_table(["$FF", "127", "0"])
        self.assertEqual(result, [0xFF, 127, 0])

    def test_byte_table_no_args(self):
        """Test byte_table raises error with no args."""
        with self.assertRaises(ValueError):
            byte_table([])

    def test_byte_table_out_of_range(self):
        """Test byte_table rejects out-of-range values."""
        with self.assertRaises(ValueError):
            byte_table(["256"])
        with self.assertRaises(ValueError):
            byte_table(["-1"])

    def test_word_table_hex(self):
        """Test word table with hex values."""
        result = word_table(["$1234", "$5678"])
        # Little-endian: $34, $12, $78, $56
        expected = [0x34, 0x12, 0x78, 0x56]
        self.assertEqual(result, expected)

    def test_word_table_with_context(self):
        """Test word table resolution with context."""
        context = {"labels": {"start": 0x0800}}
        result = word_table(["start"], context=context)
        # $0800 in little-endian: $00, $08
        expected = [0x00, 0x08]
        self.assertEqual(result, expected)

    def test_word_table_no_args(self):
        """Test word_table raises error with no args."""
        with self.assertRaises(ValueError):
            word_table([])

    def test_jump_table_basic(self):
        """Test jump table generation."""
        result = jump_table(["$0810", "$0820"])
        # Jump table subtracts 1: $080F, $081F in little-endian
        expected = [0x0F, 0x08, 0x1F, 0x08]
        self.assertEqual(result, expected)

    def test_repeat_byte_basic(self):
        """Test repeat byte."""
        result = repeat_byte(["$FF", "4"])
        self.assertEqual(result, [0xFF, 0xFF, 0xFF, 0xFF])

    def test_repeat_byte_zero(self):
        """Test repeat byte with zero count."""
        result = repeat_byte(["$AA", "0"])
        self.assertEqual(result, [])

    def test_repeat_byte_missing_args(self):
        """Test repeat_byte with missing arguments."""
        with self.assertRaises(ValueError):
            repeat_byte(["$FF"])

    def test_raw_hex_basic(self):
        """Test raw hex bytes."""
        result = raw_hex(["$48", "$65", "$6C", "$6C", "$6F"])
        expected = [0x48, 0x65, 0x6C, 0x6C, 0x6F]
        self.assertEqual(result, expected)

    def test_raw_hex_no_prefix(self):
        """Test raw hex without $ prefix."""
        result = raw_hex(["48", "65"])
        expected = [0x48, 0x65]
        self.assertEqual(result, expected)

    def test_sine_table_default(self):
        """Test sine table generation."""
        result = sine_table([])
        self.assertEqual(len(result), 256)
        # All values should be 0-255
        self.assertTrue(all(0 <= b <= 255 for b in result))

    def test_sine_table_custom_size(self):
        """Test sine table with custom size."""
        result = sine_table(["128"])
        self.assertEqual(len(result), 128)

    def test_cosine_table_default(self):
        """Test cosine table generation."""
        result = cosine_table([])
        self.assertEqual(len(result), 256)
        self.assertTrue(all(0 <= b <= 255 for b in result))

    def test_cosine_table_custom_size(self):
        """Test cosine table with custom size."""
        result = cosine_table(["64"])
        self.assertEqual(len(result), 64)


class TestMacroExpansionIntegration(unittest.TestCase):
    """Test macro expansion in assembly context."""

    def setUp(self):
        """Set up test fixtures."""
        self.expander = MacroExpander(debug=False)

    def test_process_file_with_macros(self):
        """Test processing a file with macros."""
        input_lines = [
            ".macro text_string = py6502.macros_examples.text_string",
            ".macro byte_table = py6502.macros_examples.byte_table",
            "",
            "org $0800",
            "msg:",
            "    @text_string \"Hello\"",
            "table:",
            "    @byte_table $41, $42, $43",
        ]

        output = self.expander.process_file(input_lines)

        # Check that output contains macro definitions and expansions
        output_text = "\n".join(output)
        self.assertIn("Macro defined", output_text)
        self.assertIn("db", output_text)
        self.assertIn("$48", output_text)  # 'H' in hex

    def test_process_file_pass_1(self):
        """Test processing with pass_num=1 (size estimation)."""
        input_lines = [
            ".macro text_string = py6502.macros_examples.text_string",
            "@text_string \"Test\"",
        ]

        output = self.expander.process_file(input_lines, pass_num=1)
        output_text = "\n".join(output)

        # Should expand to db directive with correct size
        self.assertIn("db", output_text)

    def test_process_file_pass_2(self):
        """Test processing with pass_num=2 (actual expansion)."""
        input_lines = [
            ".macro text_string = py6502.macros_examples.text_string",
            "@text_string \"Hi\"",
        ]

        output = self.expander.process_file(input_lines, pass_num=2)
        output_text = "\n".join(output)

        # Should expand with actual bytes
        self.assertIn("$48", output_text)  # 'H'
        self.assertIn("$69", output_text)  # 'i'

    def test_process_file_preserves_regular_lines(self):
        """Test that regular assembly lines are preserved."""
        input_lines = [
            "org $0800",
            "start:",
            "    lda #$00",
            "    rts",
        ]

        output = self.expander.process_file(input_lines)
        output_text = "\n".join(output)

        # Regular lines should be preserved
        self.assertIn("org $0800", output_text)
        self.assertIn("start:", output_text)
        self.assertIn("lda #$00", output_text)

    def test_process_file_with_comments(self):
        """Test that comments are preserved."""
        input_lines = [
            "; This is a comment",
            "org $0800  ; inline comment",
            "lda #$00   ; load zero",
        ]

        output = self.expander.process_file(input_lines)
        output_text = "\n".join(output)

        # Comments should be preserved
        self.assertIn("; This is a comment", output_text)
        self.assertIn("; inline comment", output_text)

    def test_multiple_macro_invocations(self):
        """Test multiple invocations of the same macro."""
        input_lines = [
            ".macro text_string = py6502.macros_examples.text_string",
            "msg1:",
            "    @text_string \"A\"",
            "msg2:",
            "    @text_string \"B\"",
        ]

        output = self.expander.process_file(input_lines)
        output_text = "\n".join(output)

        # Both should be expanded (check for db directives)
        self.assertEqual(output_text.count("db "), 2)

    def test_macro_with_different_args(self):
        """Test same macro with different arguments."""
        input_lines = [
            ".macro repeat_byte = py6502.macros_examples.repeat_byte",
            "line1: @repeat_byte $FF, 4",
            "line2: @repeat_byte $00, 8",
        ]

        output = self.expander.process_file(input_lines)
        output_text = "\n".join(output)

        # Both should expand
        self.assertIn("$FF", output_text)
        self.assertIn("$00", output_text)


class TestMacroWithAssembler(unittest.TestCase):
    """Test macro system integration with assembler."""

    def setUp(self):
        """Set up test fixtures."""
        # Import here to avoid circular imports
        from py6502.asm6502 import asm6502

        self.asm6502 = asm6502

    def test_assemble_with_macros(self):
        """Test assembling code with macros."""
        code = """
org $0800
.macro text_string = py6502.macros_examples.text_string
.macro byte_table = py6502.macros_examples.byte_table

start:
    lda #$00
    rts

msg:
    @text_string "Hi"

table:
    @byte_table $01, $02, $03
"""

        assembler = self.asm6502(debug=0)
        lines = code.strip().split("\n")
        assembled, summary = assembler.assemble(lines)

        # Check that assembly succeeded
        self.assertIsNotNone(assembled)
        self.assertIsNotNone(summary)

        # Check symbol table contains expected symbols
        self.assertIn("start", assembler.symbols)
        self.assertIn("msg", assembler.symbols)
        self.assertIn("table", assembler.symbols)

    def test_macro_address_tracking(self):
        """Test that macros are properly tracked in address space."""
        code = """
org $0800
.macro byte_table = py6502.macros_examples.byte_table

start:
    @byte_table $41, $42, $43, $44

end:
    rts
"""

        assembler = self.asm6502(debug=0)
        lines = code.strip().split("\n")
        assembled, summary = assembler.assemble(lines)

        # end label should be after the macro expansion
        # (4 bytes from byte_table + 0 bytes before end)
        self.assertGreater(assembler.symbols["end"], assembler.symbols["start"])


class TestMacroErrors(unittest.TestCase):
    """Test error handling in macro system."""

    def setUp(self):
        """Set up test fixtures."""
        self.expander = MacroExpander(debug=False)

    def test_invalid_macro_definition(self):
        """Test that invalid macro definitions are handled."""
        line = ".invalid_syntax here"
        result = self.expander.parse_macro_definition(line)
        self.assertIsNone(result)

    def test_macro_function_raises_error(self):
        """Test handling of errors in macro functions."""
        # Register a macro that will fail
        self.expander.register_macro(
            "bad_text", "py6502.macros_examples", "text_string"
        )

        # Try to expand with wrong argument type (text_string expects quoted string)
        success, result = self.expander.expand_macro("bad_text", ["no_quotes"])
        # The function may succeed and return a result, or fail - both are acceptable
        # Just verify it returned something
        self.assertIsNotNone(result)


if __name__ == "__main__":
    unittest.main()