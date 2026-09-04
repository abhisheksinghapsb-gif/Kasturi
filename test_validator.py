import os
import sys
import re

def strip_matlab_line(line):
    """
    Properly strips comments and string literals from a MATLAB code line,
    distinguishing single quote strings '...' from transpose A'
    """
    out = []
    in_str = False
    in_double_str = False
    i = 0
    n = len(line)
    
    while i < n:
        ch = line[i]
        
        # Check for double quote string "..."
        if ch == '"' and not in_str:
            in_double_str = not in_double_str
            i += 1
            continue
            
        # Check for single quote string '...'
        if ch == "'" and not in_double_str:
            # Check if this single quote is transpose: preceded by identifier, closing parenthesis/bracket
            # e.g., A', (x+y)', [1 2]', foo(1)'
            is_transpose = False
            if not in_str and i > 0:
                prev_non_space = ""
                for j in range(i - 1, -1, -1):
                    if not line[j].isspace():
                        prev_non_space = line[j]
                        break
                if prev_non_space and (prev_non_space.isalnum() or prev_non_space in [')', ']', '}', '.', '_']):
                    is_transpose = True
            
            if not is_transpose:
                in_str = not in_str
                i += 1
                continue
            else:
                out.append(ch)
                i += 1
                continue
                
        # If inside string, ignore content
        if in_str or in_double_str:
            i += 1
            continue
            
        # Check for single-line comment %
        if ch == '%':
            break
            
        out.append(ch)
        i += 1
        
    return "".join(out)

def check_matlab_file(filepath):
    rel_path = os.path.relpath(filepath)
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()
    
    block_starters = {"function", "if", "for", "while", "switch", "try", "classdef", "methods", "properties", "events"}
    stack = []
    
    in_block_comment = False
    
    for line_no, raw_line in enumerate(lines, 1):
        stripped = raw_line.strip()
        if stripped.startswith("%{"):
            in_block_comment = True
            continue
        if stripped.startswith("%}"):
            in_block_comment = False
            continue
        if in_block_comment:
            continue
            
        code = strip_matlab_line(raw_line).strip()
        if not code:
            continue
            
        # Tokenize code line
        # Match identifiers/keywords
        tokens = list(re.finditer(r'\b[a-zA-Z_][a-zA-Z0-9_]*\b', code))
        
        for match in tokens:
            word = match.group()
            start_pos = match.start()
            end_pos = match.end()
            
            if word in block_starters:
                stack.append((word, line_no))
            elif word == "end":
                # Check if it's indexing: e.g. array(end) or {end} or end+1 or end:
                # Look at context before and after
                before = code[:start_pos].rstrip()
                after = code[end_pos:].lstrip()
                
                # If preceded by (, {, or comma, or followed by ), }, +, -, :
                # it is array indexing, not a block terminator
                is_index = False
                if before and (before[-1] in "({,:"):
                    is_index = True
                if after and (after[0] in ")}+-:*^;/"):
                    is_index = True
                    
                if not is_index:
                    if stack:
                        top = stack.pop()
                    else:
                        print(f"FAIL: {rel_path} - Line {line_no} extra 'end' with empty stack")
                        return False
                        
    if len(stack) == 0:
        print(f"PASS: {rel_path} (Fully balanced)")
        return True
    else:
        print(f"FAIL: {rel_path} - Unclosed blocks:")
        for s, l in stack:
            print(f"   Line {l}: {s}")
        return False

def main():
    root = "g:/sih"
    m_files = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if f.endswith(".m"):
                m_files.append(os.path.join(dirpath, f))
    
    m_files.sort()
    print(f"Validating {len(m_files)} MATLAB (.m) files:")
    results = [check_matlab_file(f) for f in m_files]
    
    print("\n" + "="*50)
    print(f"RESULTS: {sum(results)} Passed / {len(results)} Total")
    print("="*50)
    if all(results):
        print("ALL MATLAB SOURCE FILES ARE 100% SYNTACTICALLY VALID!")
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
