#!/usr/bin/env python3
"""GDScript extractor for graphify: puts game/ (*.gd, *.gdshader, *.tscn) into graphify-out/graph.json.

graphify has no GDScript parser. This reads the game with regexes (no model calls), merges the
result into the existing graph, reclusters, relabels and rewrites GRAPH_REPORT.md and graph.html.
Re-running replaces the nodes it made earlier and keeps the rest.

  $(cat graphify-out/.graphify_python) tools/gd_graph.py        # repo root, after /graphify .
  $(cat graphify-out/.graphify_python) tools/gd_graph.py --dry  # only print what it found

Nodes: one per script / shader / scene, per func and inner class ("name()"), per signal, per
resource json/tres file, and per property-tree path used as a literal (Props.get_f("fdm/ias_mps")).
Edges (confidence EXTRACTED):
  contains         file -> func / inner class / signal
  inherits         `extends Foo` / `extends "res://x.gd"`
  references       preload()/load() of a res:// file, scene ext_resource
  uses             a class_name, autoload (Props, Session, ...) or preload alias named in the code
  calls            Foo.func() (static/autoload), or a call to a func of the same file
  reads_property / writes_property   Props.get_*/has vs Props.set_v with a literal path
Not resolved: calls through instance variables (fdm.step()), dynamic load() paths, property
paths built at run time, signal connections.
"""
import argparse
import json
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

RE_FUNC = re.compile(r"^(\s*)(?:static\s+)?func\s+(\w+)")
RE_CLASS_NAME = re.compile(r"^class_name\s+(\w+)")
RE_EXTENDS = re.compile(r"^extends\s+(\S+)")
RE_INNER = re.compile(r"^class\s+(\w+)")
RE_SIGNAL = re.compile(r"^\s*signal\s+(\w+)")
RE_ALIAS = re.compile(r'^\s*const\s+(\w+)\s*(?::=|=)\s*(?:preload|load)\(\s*"([^"]+)"')
RE_LOAD = re.compile(r'\b(?:preload|load)\(\s*"(res://[^"]+)"')
RE_PROP = re.compile(r'\bProps\.(get_f|get_b|get_v|set_v|has)\(\s*&?"([^"]+)"')
RE_UPPER = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")
RE_STATIC = re.compile(r"\b([A-Z]\w*)\.(\w+)\(")
RE_LOCAL = re.compile(r"(?<![.\w])([a-z_]\w*)\(")
RE_EXT_RES = re.compile(r'\[ext_resource[^\]]*path="(res://[^"]+)"')
KEYWORDS = {"if", "elif", "while", "for", "match", "func", "return", "and", "or", "not", "in", "is", "as", "await",
            "print", "preload", "load", "assert", "super", "range", "str", "int", "float", "bool", "len"}
ORIGIN = "gdscript"


def make_id(*parts):
    from graphify.build import make_id as mk
    return mk(*parts)


def scrub(line):
    """The line without comments and string contents."""
    out, q, i = [], "", 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                i += 1
            elif c == q:
                q = ""
        elif c in "\"'":
            q = c
        elif c == "#":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def game_files(root):
    try:
        names = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "game"], cwd=root, capture_output=True, text=True, check=True).stdout.split()
    except (OSError, subprocess.CalledProcessError):
        names = [str(p.relative_to(root)) for p in (root / "game").rglob("*") if p.is_file()]
    return sorted(n for n in names if n.endswith((".gd", ".gdshader", ".tscn")))


def res_path(res):
    return "game/" + res[len("res://"):]


def autoloads(root):
    out = {}
    for m in re.finditer(r'^(\w+)="\*?(res://[^"]+)"', (root / "game/project.godot").read_text(), re.M):
        out[m.group(1)] = res_path(m.group(2))
    return out


class Builder:
    def __init__(self, root):
        self.root = root
        self.files = game_files(root)
        self.auto = autoloads(root)
        self.nodes, self.edges, self._seen = {}, [], set()
        self.fid = {f: make_id(f) for f in self.files}
        self.class_file = {}  # class_name -> file
        self.funcs = defaultdict(dict)  # file -> {func name: id}
        self.text = {f: (root / f).read_text(errors="replace").splitlines() for f in self.files}

    def node(self, nid, label, src, loc=None, ftype="code", callable_=False, **extra):
        if nid not in self.nodes:
            n = {"id": nid, "label": label, "file_type": ftype, "source_file": src, "source_location": loc, "_origin": ORIGIN}
            if callable_:
                n["_callable"] = True
            n.update(extra)
            self.nodes[nid] = n
        return nid

    def edge(self, a, b, rel, src, line):
        key = (a, b, rel)
        if a != b and key not in self._seen:
            self._seen.add(key)
            self.edges.append({"source": a, "target": b, "relation": rel, "confidence": "EXTRACTED", "confidence_score": 1.0,
                               "source_file": src, "source_location": f"L{line}", "weight": 1.0, "_origin": ORIGIN})

    def target(self, res, src):
        """Node id of a res:// file, created for json/tres resources, None if it is not part of the graph."""
        p = res_path(res)
        if p in self.fid:
            return self.fid[p]
        if p.endswith((".json", ".tres")) and (self.root / p).is_file():
            return self.node(make_id(p), Path(p).name, p, None, "document")
        return None

    def first_pass(self):
        for f in self.files:
            fid = self.node(self.fid[f], Path(f).name, f, "L1")
            if not f.endswith(".gd"):
                continue
            inner = None
            for i, raw in enumerate(self.text[f], 1):
                code = scrub(raw)
                m = RE_CLASS_NAME.match(code)
                if m:
                    self.class_file[m.group(1)] = f
                    self.nodes[fid]["class_name"] = m.group(1)
                if code and not code[0].isspace():
                    m = RE_INNER.match(code)
                    inner = m.group(1) if m else None
                    if m:
                        self.edge(fid, self.node(make_id(f, m.group(1)), m.group(1), f, f"L{i}", callable_=True), "contains", f, i)
                m = RE_FUNC.match(code)
                if m:
                    owner = inner if inner and m.group(1) else None
                    name = f"{owner}.{m.group(2)}" if owner else m.group(2)
                    nid = self.node(make_id(f, name), f"{name}()", f, f"L{i}", callable_=True)
                    self.edge(fid, nid, "contains", f, i)
                    if not owner:
                        self.funcs[f][m.group(2)] = nid
                m = RE_SIGNAL.match(code)
                if m:
                    self.edge(fid, self.node(make_id(f, "signal", m.group(1)), f"signal {m.group(1)}", f, f"L{i}"), "contains", f, i)

    def second_pass(self):
        for f in self.files:
            fid = self.fid[f]
            if f.endswith(".tscn"):
                for i, raw in enumerate(self.text[f], 1):
                    for res in RE_EXT_RES.findall(raw):
                        t = self.target(res, f)
                        if t:
                            self.edge(fid, t, "references", f, i)
                continue
            if f.endswith(".gd"):
                self.script(f, fid)

    def script(self, f, fid):
        alias = {}
        cur = fid
        for i, raw in enumerate(self.text[f], 1):
            m = RE_ALIAS.match(raw)
            if m:
                t = self.target(m.group(2), f)
                if t:
                    alias[m.group(1)] = t
            for res in RE_LOAD.findall(raw):
                t = self.target(res, f)
                if t:
                    self.edge(fid, t, "references", f, i)
            for verb, path in RE_PROP.findall(raw):
                pid = self.node(make_id("property", path), path, "game/core/props.gd", None, "concept")
                self.edge(fid, pid, "writes_property" if verb == "set_v" else "reads_property", f, i)
            code = scrub(raw)
            m = RE_EXTENDS.match(code)
            if m:
                t = self.class_target(m.group(1), alias)
                if t is None and '"res://' in raw:
                    t = self.target(raw.split('"')[1], f)
                if t:
                    self.edge(fid, t, "inherits", f, i)
            m = RE_FUNC.match(code)
            if m:
                cur = self.funcs[f].get(m.group(2), fid) if not m.group(1) else fid
            elif code and not code[0].isspace():
                cur = fid
            for name in set(RE_UPPER.findall(code)):
                t = self.class_target(name, alias)
                if t and t != fid:
                    self.edge(fid, t, "uses", f, i)
            for cls, fn in RE_STATIC.findall(code):
                tf = self.class_file.get(cls) or self.auto.get(cls)
                if tf in self.funcs and fn in self.funcs[tf] and tf != "game/core/props.gd":  # the accessors would be the top hubs; reads/writes_property say more
                    self.edge(cur, self.funcs[tf][fn], "calls", f, i)
            for fn in RE_LOCAL.findall(code):
                if fn not in KEYWORDS and fn in self.funcs[f] and not RE_FUNC.match(code):
                    self.edge(cur, self.funcs[f][fn], "calls", f, i)

    def class_target(self, name, alias):
        if name in alias:
            return alias[name]
        f = self.class_file.get(name) or self.auto.get(name)
        return self.fid.get(f) if f else None

    def build(self):
        self.first_pass()
        self.second_pass()
        return {"nodes": list(self.nodes.values()), "edges": self.edges, "hyperedges": [], "input_tokens": 0, "output_tokens": 0}


def community_labels(G, comms, old_names):
    """Keep the hand-written labels of communities that survive, name the new ones after folder + biggest node."""
    labels, used = {}, Counter()
    for cid, members in comms.items():
        old = Counter(old_names[n] for n in members if n in old_names)
        real = [n for n in members if G.nodes[n].get("file_type") != "concept"] or members
        top = max(real, key=lambda n: G.degree(n))
        if old and old.most_common(1)[0][1] >= max(3, 0.5 * sum(old.values())) and len(old) <= 3:
            base = old.most_common(1)[0][0]
        else:
            dirs = Counter("/".join(G.nodes[n].get("source_file", "").split("/")[:-1][:3]) or "repo" for n in real)
            base = f"{dirs.most_common(1)[0][0]}: {G.nodes[top].get('label', top)}"
        used[base] += 1
        labels[cid] = base if used[base] == 1 else f"{base} ({G.nodes[top].get('label', top)})"
    return labels


def merge(root, out):
    from graphify.build import build_merge
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    from graphify.detect import detect
    from graphify.export import to_json
    from graphify.report import generate
    gpath = out / "graph.json"
    old = json.loads(gpath.read_text())
    old_names = {n["id"]: n["community_name"] for n in old["nodes"] if n.get("community_name") and n.get("_origin") != ORIGIN}
    prune = sorted({n["source_file"] for n in old["nodes"] if n.get("_origin") == ORIGIN})
    b = Builder(root)
    ext = b.build()
    G = build_merge([ext], gpath, prune_sources=prune or None, root=root, directed=False, dedup=False)
    comms = cluster(G)
    coh = score_all(G, comms)
    labels = community_labels(G, comms, old_names)
    det = detect(root)
    det["files"]["code"] = list(det["files"].get("code", [])) + [str(root / f) for f in b.files if not f.endswith(".tscn")]
    det["total_files"] = sum(len(v) for v in det["files"].values())
    gods, sur = god_nodes(G), surprising_connections(G, comms)
    questions = suggest_questions(G, comms, labels)
    if not to_json(G, comms, str(gpath), community_labels=labels, force=True):
        raise SystemExit("graph.json was not written")
    (out / "GRAPH_REPORT.md").write_text(generate(G, comms, coh, labels, gods, sur, det, {"input": 0, "output": 0}, str(root), suggested_questions=questions))
    (out / ".graphify_labels.json").write_text(json.dumps({str(k): v for k, v in labels.items()}))
    subprocess.run(["graphify", "export", "html"], cwd=root, check=False)
    print(f"graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(comms)} communities")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", default="graphify-out")
    ap.add_argument("--dry", action="store_true", help="only print the counts")
    a = ap.parse_args()
    root, out = Path(a.root).resolve(), Path(a.out)
    if a.dry:
        ext = Builder(root).build()
        print(f"{len(ext['nodes'])} nodes, {len(ext['edges'])} edges", dict(Counter(e["relation"] for e in ext["edges"])))
        return
    merge(root, out.resolve() if out.is_absolute() else root / out)


if __name__ == "__main__":
    main()
