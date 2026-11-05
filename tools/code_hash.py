#!/usr/bin/env python3
"""Fingerprints for run.sh: tells a code change from a comment or formatting change.

  code_hash.py FILE...   prints "<sha1>  <path>" per file
  code_hash.py --tag     prints "# python X.Y" (ast.dump differs between Python versions)

A .py file is hashed as ast.dump of its parsed source with the module, class and function
docstrings removed, so comments, docstrings, blank lines and formatting do not change the hash.
Any other file (or a .py that does not parse) is hashed as raw bytes.
"""
import ast
import hashlib
import sys

DEFS = (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)


def drop_docstrings(tree):
    for node in ast.walk(tree):
        if not isinstance(node, DEFS):
            continue
        first = node.body[0] if node.body else None
        if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) \
                and isinstance(first.value.value, str):
            node.body = node.body[1:] or [ast.Pass()]


def file_hash(path):
    with open(path, "rb") as f:
        data = f.read()
    if path.endswith(".py"):
        try:
            tree = ast.parse(data, filename=path)
        except (SyntaxError, ValueError):
            return hashlib.sha1(data).hexdigest()
        drop_docstrings(tree)
        return hashlib.sha1(ast.dump(tree).encode()).hexdigest()
    return hashlib.sha1(data).hexdigest()


def main(argv):
    if argv == ["--tag"]:
        print("# python %d.%d" % sys.version_info[:2])
        return 0
    for path in argv:
        print(f"{file_hash(path)}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
