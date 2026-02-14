#!/usr/bin/env python3
"""
macro6502.py - Macro expansion preprocessor for 6502 assembly

Supports:
  .macro name = module.function     - Define a macro using an external Python function
  @name arg1, arg2, ...             - Invoke a macro

Macro functions receive:
  - args: list of string arguments from the invocation
  - context: optional dict with 'org', 'addr', 'labels'

Macro functions return:
  - list of bytes (0-255)
  - OR string (will be assembled)
  - OR None (expands to nothing)
"""

import re
import sys
import importlib.util


class MacroExpander:
    def __init__(self, debug=False):
        self.macros = {}  # macro_name -> (module_path, function_name)
        self.debug = debug
        
    def register_macro(self, name, module_path, function_name):
        """Register a macro: name -> (module_path, function_name)"""
        self.macros[name] = (module_path, function_name)
        if self.debug:
            print(f"[MACRO] Registered: {name} = {module_path}.{function_name}")
    
    def load_macro_function(self, module_path, function_name):
        """Dynamically load a Python function from a module.
        
        Args:
            module_path: Python module path (e.g., "py6502.macros_examples")
            function_name: Function name in the module
        """
        try:
            # Handle Python module path (e.g., "py6502.macros_examples")
            parts = module_path.split('.')
            module = __import__(module_path, fromlist=[parts[-1]])
            
            if not hasattr(module, function_name):
                raise AttributeError(f"Function '{function_name}' not found in {module_path}")
            
            return getattr(module, function_name)
        except Exception as e:
            raise RuntimeError(f"Failed to load macro function {module_path}.{function_name}: {e}")
    
    def parse_macro_definition(self, line):
        """
        Parse: .macro name = module.function
        Returns (name, module_path, function_name) or None
        """
        match = re.match(r'^\s*\.macro\s+(\w+)\s*=\s*(.+)\.(\w+)\s*$', line)
        if match:
            name = match.group(1)
            module_path = match.group(2)
            function_name = match.group(3)
            return (name, module_path, function_name)
        return None
    
    def parse_macro_invocation(self, line):
        """
        Parse: @name arg1, arg2, ...
        Returns (name, [args]) or None
        """
        match = re.match(r'^\s*@(\w+)\s*(.*?)\s*(?:;.*)?$', line)
        if match:
            name = match.group(1)
            args_str = match.group(2).strip()
            
            if args_str:
                # Split by comma, strip whitespace
                args = [arg.strip() for arg in args_str.split(',')]
            else:
                args = []
            
            return (name, args)
        return None
    
    def expand_macro(self, name, args, context=None, pass_num=2):
        """
        Expand a macro invocation.
        
        Args:
            name: macro name
            args: list of string arguments
            context: optional dict with 'org', 'addr', 'labels'
            pass_num: assembly pass (1 or 2)
                      Pass 1: return size estimate or placeholder bytes
                      Pass 2: return actual bytes with resolved labels
        
        Returns: (success, result_lines or result_bytes)
        """
        if name not in self.macros:
            return False, [f"ERROR: Unknown macro '{name}'"]
        
        module_path, function_name = self.macros[name]
        
        try:
            func = self.load_macro_function(module_path, function_name)
        except RuntimeError as e:
            return False, [f"ERROR: {e}"]
        
        try:
            # Try calling with context and pass_num first
            import inspect
            sig = inspect.signature(func)
            kwargs = {}
            if 'context' in sig.parameters:
                kwargs['context'] = context
            if 'pass_num' in sig.parameters:
                kwargs['pass_num'] = pass_num
            
            result = func(args, **kwargs)
        except Exception as e:
            return False, [f"ERROR: Macro '{name}' failed: {e}"]
        
        # Convert result to assembly lines
        if result is None:
            return True, []
        elif isinstance(result, (list, tuple)):
            # List of bytes
            if all(isinstance(b, int) and 0 <= b <= 255 for b in result):
                # Format as db directive
                hex_bytes = ', '.join(f'${b:02X}' for b in result)
                return True, [f"db {hex_bytes}"]
            else:
                return False, ["ERROR: Macro returned non-byte values"]
        elif isinstance(result, str):
            # Assembly code string
            return True, result.split('\n')
        else:
            return False, ["ERROR: Macro returned invalid type"]
    
    def process_file(self, input_lines, context_builder=None, pass_num=2):
        """
        Process assembly file, expanding macros.
        
        Args:
            input_lines: list of assembly source lines
            context_builder: optional callable(line_num, org, labels) -> dict
                            to build context for each macro invocation
            pass_num: assembly pass (1 or 2)
                      Pass 1: macros return size estimates
                      Pass 2: macros return actual bytes
        
        Returns: list of expanded lines
        """
        output = []
        current_org = None
        labels = {}
        
        for i, line in enumerate(input_lines):
            # Track .org directives
            org_match = re.match(r'^\s*\.org\s+(\$[0-9A-Fa-f]+)', line)
            if org_match:
                current_org = int(org_match.group(1), 16)
            
            # Track labels
            label_match = re.match(r'^(\w+):\s*', line)
            if label_match:
                if current_org is not None:
                    labels[label_match.group(1)] = current_org
            
            # Check for macro definition
            macro_def = self.parse_macro_definition(line)
            if macro_def:
                name, module_path, function_name = macro_def
                self.register_macro(name, module_path, function_name)
                output.append(f"; Macro defined: {name}")
                continue
            
            # Check for macro invocation
            macro_inv = self.parse_macro_invocation(line)
            if macro_inv:
                name, args = macro_inv
                
                # Build context if builder provided
                context = {}
                if context_builder:
                    context = context_builder(i, current_org, labels)
                elif current_org is not None:
                    context = {'org': current_org, 'labels': labels}
                
                success, result_lines = self.expand_macro(name, args, context, pass_num=pass_num)
                
                if success:
                    output.extend(result_lines)
                    if self.debug:
                        print(f"[MACRO] Expanded @{name} (pass {pass_num})")
                else:
                    output.extend(result_lines)
                    if self.debug:
                        print(f"[MACRO] Failed to expand @{name} (pass {pass_num})")
                continue
            
            # Regular line
            output.append(line)
        
        return output


def main():
    """Command-line interface"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Macro expansion preprocessor for 6502 assembly'
    )
    parser.add_argument('input', help='Input assembly file')
    parser.add_argument('-o', '--output', help='Output file (default: stdout)')
    parser.add_argument('-d', '--debug', action='store_true', help='Debug output')
    parser.add_argument('-p', '--pass', type=int, default=2, dest='pass_num',
                        help='Assembly pass (1 or 2, default: 2)')
    
    args = parser.parse_args()
    
    try:
        with open(args.input, 'r') as f:
            input_lines = f.readlines()
    except IOError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(1)
    
    expander = MacroExpander(debug=args.debug)
    output_lines = expander.process_file(input_lines, pass_num=args.pass_num)
    
    output_text = '\n'.join(output_lines)
    
    if args.output:
        try:
            with open(args.output, 'w') as f:
                f.write(output_text)
            print(f"Expanded assembly written to: {args.output}")
        except IOError as e:
            print(f"Error writing file: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print(output_text)


if __name__ == '__main__':
    main()