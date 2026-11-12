"""Check that every third-party module the data pipeline imports is in tools/requirements.txt.

The pipeline scripts are the .py inputs of the steps in run.sh (IN[..] lines). Local modules in
tools/ are followed, so a helper's imports count too. Every import is checked, also the ones inside
functions. Standard library modules and SYSTEM (GDAL's osgeo, from the OS package) are skipped.

    python3 tools/check_requirements.py        exit 0 when complete, 1 and a list otherwise
"""
import ast
import re
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
SYSTEM = {"osgeo"}  # installed by run.sh preflight through the system package manager


def required_imports(req: Path) -> set[str]:
    names = set()
    for line in req.read_text().splitlines():
        body, _, comment = line.partition("#")
        pkg = body.strip()
        if not pkg:
            continue
        m = re.search(r"import\s+([A-Za-z0-9_]+)", comment)
        names.add(m.group(1) if m else re.split(r"[^A-Za-z0-9_]", pkg)[0])
    return names


def pipeline_scripts(run_sh: Path) -> list[Path]:
    found = re.findall(r"tools/([A-Za-z0-9_]+\.py)", "\n".join(
        l for l in run_sh.read_text().splitlines() if l.startswith("IN[")))
    return sorted({TOOLS / f for f in found if (TOOLS / f).exists()})


def imports_of(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(), str(path))
    out = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            out.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            out.add(node.module.split(".")[0])
    return out


def missing(scripts: list[Path], have: set[str]) -> dict[str, set[str]]:
    seen, todo, need = set(), list(scripts), {}
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        for mod in imports_of(p):
            local = TOOLS / f"{mod}.py"
            if local.exists():
                todo.append(local)
            elif mod in sys.stdlib_module_names or mod in SYSTEM or mod in have:
                continue
            else:
                need.setdefault(mod, set()).add(p.name)
    return need


def main() -> int:
    have = required_imports(TOOLS / "requirements.txt")
    scripts = pipeline_scripts(TOOLS.parent / "run.sh")
    if not scripts:
        print("no pipeline scripts found in run.sh")
        return 1
    need = missing(scripts, have)
    for mod, users in sorted(need.items()):
        print(f"missing from tools/requirements.txt: {mod} (imported by {', '.join(sorted(users))})")
    if not need:
        print(f"requirements complete for {len(scripts)} pipeline scripts")
    return 1 if need else 0


if __name__ == "__main__":
    sys.exit(main())
