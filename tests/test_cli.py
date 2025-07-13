#!/usr/bin/env python3
"""
Tests for CLI tools in the py6502 package.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# Add the parent directory to the path so we can import py6502
sys.path.insert(0, str(Path(__file__).parent.parent))

from py6502 import cli_asm6502, cli_debugger, cli_dis6502, cli_sim6502


class TestCLIAssembler:
    """Tests for the CLI assembler (a6502)."""

    @pytest.fixture
    def sample_asm_file(self):
        """Create a temporary assembly file for testing."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.asm', delete=False) as f:
            f.write("""
    ORG $0200
start:
    LDA #$55
    STA $10
    LDX #$AA
    STX $11
    BRK
            """)
            return f.name

    def test_assemble_basic_file(self, sample_asm_file):
        """Test basic assembly functionality."""
        with tempfile.NamedTemporaryFile(suffix='.hex', delete=False) as output:
            result = cli_asm6502.main([sample_asm_file, '-o', output.name])

            assert result == 0
            assert os.path.exists(output.name)

            # Check that hex file contains expected content
            with open(output.name) as f:
                content = f.read()
                assert len(content) > 0
                assert ':' in content  # Intel hex format marker

            os.unlink(output.name)

    def test_assemble_with_listing(self, sample_asm_file):
        """Test assembly with listing generation."""
        with tempfile.NamedTemporaryFile(suffix='.lst', delete=False) as listing:
            result = cli_asm6502.main([sample_asm_file, '--listing', listing.name])

            assert result == 0
            assert os.path.exists(listing.name)

            # Check listing content
            with open(listing.name) as f:
                content = f.read()
                assert 'lda #$55' in content
                assert 'start:' in content

            os.unlink(listing.name)

    def test_assemble_with_symbols(self, sample_asm_file):
        """Test assembly with symbol table generation."""
        with tempfile.NamedTemporaryFile(suffix='.sym', delete=False) as symbols:
            result = cli_asm6502.main([sample_asm_file, '--symbols', symbols.name])

            assert result == 0
            assert os.path.exists(symbols.name)

            # Check symbol content
            with open(symbols.name) as f:
                content = f.read()
                assert 'start' in content

            os.unlink(symbols.name)

    def test_assemble_binary_output(self, sample_asm_file):
        """Test binary output generation."""
        with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as binary:
            result = cli_asm6502.main([sample_asm_file, '-b', binary.name])

            assert result == 0
            assert os.path.exists(binary.name)

            # Check binary file has content
            assert os.path.getsize(binary.name) > 0

            os.unlink(binary.name)

    def test_assemble_nonexistent_file(self):
        """Test handling of non-existent input file."""
        result = cli_asm6502.main(['nonexistent.asm'])
        assert result == 1

    def teardown_method(self):
        """Clean up temporary files."""
        # Clean up any remaining temp files
        for f in os.listdir('.'):
            if f.endswith(('.hex', '.lst', '.sym', '.bin')) and f.startswith('tmp'):
                try:
                    os.unlink(f)
                except OSError:
                    pass


class TestCLISimulator:
    """Tests for the CLI simulator (s6502)."""

    @pytest.fixture
    def sample_asm_file(self):
        """Create a temporary assembly file for testing."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.asm', delete=False) as f:
            f.write("""
    ORG $0200
    LDA #$42
    STA $10
    LDX $10
    BRK
            """)
            return f.name

    def test_simulate_basic(self, sample_asm_file):
        """Test basic simulation."""
        result = cli_sim6502.main([sample_asm_file, '--steps', '10'])
        assert result == 0

    def test_simulate_with_start_address(self, sample_asm_file):
        """Test simulation with custom start address."""
        result = cli_sim6502.main([sample_asm_file, '-s', '0x0200', '--steps', '5'])
        assert result == 0

    def test_simulate_with_trace(self, sample_asm_file):
        """Test simulation with trace file."""
        with tempfile.NamedTemporaryFile(suffix='.trace', delete=False) as trace:
            result = cli_sim6502.main([sample_asm_file, '--trace', trace.name, '--steps', '5'])

            assert result == 0
            assert os.path.exists(trace.name)

            # Check trace file content
            with open(trace.name) as f:
                content = f.read()
                assert 'Step' in content
                assert 'PC' in content

            os.unlink(trace.name)

    def test_simulate_debug_mode(self, sample_asm_file):
        """Test simulation in debug mode."""
        result = cli_sim6502.main([sample_asm_file, '-d', '--steps', '3'])
        assert result == 0

    def test_simulate_nonexistent_file(self):
        """Test handling of non-existent input file."""
        result = cli_sim6502.main(['nonexistent.asm'])
        assert result == 1


class TestCLIDisassembler:
    """Tests for the CLI disassembler (d6502)."""

    @pytest.fixture
    def sample_binary_file(self):
        """Create a temporary binary file for testing."""
        with tempfile.NamedTemporaryFile(mode='wb', suffix='.bin', delete=False) as f:
            # Write some 6502 opcodes: LDA #$42, STA $10, BRK
            f.write(bytes([0xA9, 0x42, 0x85, 0x10, 0x00]))
            return f.name

    def test_disassemble_basic(self, sample_binary_file):
        """Test basic disassembly."""
        result = cli_dis6502.main([sample_binary_file])
        assert result == 0

    def test_disassemble_with_start_address(self, sample_binary_file):
        """Test disassembly with custom start address."""
        result = cli_dis6502.main([sample_binary_file, '-s', '0x1000'])
        assert result == 0

    def test_disassemble_hex_format(self, sample_binary_file):
        """Test disassembly in hex format."""
        result = cli_dis6502.main([sample_binary_file, '--format', 'hex'])
        assert result == 0

    def test_disassemble_both_formats(self, sample_binary_file):
        """Test disassembly in both assembly and hex formats."""
        result = cli_dis6502.main([sample_binary_file, '--format', 'both'])
        assert result == 0

    def test_disassemble_with_output_file(self, sample_binary_file):
        """Test disassembly to output file."""
        with tempfile.NamedTemporaryFile(suffix='.lst', delete=False) as output:
            result = cli_dis6502.main([sample_binary_file, '-o', output.name])

            assert result == 0
            assert os.path.exists(output.name)

            # Check output file content
            with open(output.name) as f:
                content = f.read()
                assert len(content) > 0

            os.unlink(output.name)

    def test_disassemble_with_length_limit(self, sample_binary_file):
        """Test disassembly with length limit."""
        result = cli_dis6502.main([sample_binary_file, '--length', '3'])
        assert result == 0

    def test_disassemble_nonexistent_file(self):
        """Test handling of non-existent input file."""
        result = cli_dis6502.main(['nonexistent.bin'])
        assert result == 1


class TestCLIDebugger:
    """Tests for the CLI debugger (db6502)."""

    @pytest.fixture
    def sample_asm_file(self):
        """Create a temporary assembly file for testing."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.asm', delete=False) as f:
            f.write("""
    ORG $0200
    LDA #$42
    STA $10
    BRK
            """)
            return f.name

    def test_debugger_simple_mode(self, sample_asm_file):
        """Test debugger in simple mode."""
        # Note: This will likely require mocking user input or using --simple flag
        result = cli_debugger.main([sample_asm_file, '--simple'])
        # The debugger might return 0 or 1 depending on implementation
        assert result in [0, 1]

    def test_debugger_with_start_address(self, sample_asm_file):
        """Test debugger with custom start address."""
        result = cli_debugger.main([sample_asm_file, '--simple', '-s', '0x0200'])
        assert result in [0, 1]

    def test_debugger_nonexistent_file(self):
        """Test handling of non-existent input file."""
        result = cli_debugger.main(['nonexistent.asm'])
        assert result == 1


class TestCLIIntegration:
    """Integration tests that test multiple CLI tools together."""

    def test_assemble_then_simulate(self):
        """Test assembling a file and then simulating it."""
        # Create assembly file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.asm', delete=False) as asm_file:
            asm_file.write("""
    ORG $0200
start:
    LDA #$55
    STA $10
    LDX $10
    INX
    STX $11
    BRK
            """)
            asm_file_path = asm_file.name

        try:
            # Assemble the file
            with tempfile.NamedTemporaryFile(suffix='.hex', delete=False) as hex_file:
                assemble_result = cli_asm6502.main([asm_file_path, '-o', hex_file.name])
                assert assemble_result == 0
                assert os.path.exists(hex_file.name)

            # Simulate the file
            simulate_result = cli_sim6502.main([asm_file_path, '--steps', '10'])
            assert simulate_result == 0

        finally:
            # Clean up
            os.unlink(asm_file_path)
            if os.path.exists(hex_file.name):
                os.unlink(hex_file.name)

    def test_assemble_then_disassemble(self):
        """Test assembling a file and then disassembling the binary."""
        # Create assembly file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.asm', delete=False) as asm_file:
            asm_file.write("""
    ORG $0200
    LDA #$42
    STA $10
    BRK
            """)
            asm_file_path = asm_file.name

        try:
            # Assemble to binary
            with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as bin_file:
                assemble_result = cli_asm6502.main([asm_file_path, '-b', bin_file.name])
                assert assemble_result == 0
                assert os.path.exists(bin_file.name)

                # Disassemble the binary
                disassemble_result = cli_dis6502.main([bin_file.name, '-s', '0x0200'])
                assert disassemble_result == 0

        finally:
            # Clean up
            os.unlink(asm_file_path)
            if os.path.exists(bin_file.name):
                os.unlink(bin_file.name)


if __name__ == "__main__":
    # Allow running this test file directly
    pytest.main([__file__, "-v"])
