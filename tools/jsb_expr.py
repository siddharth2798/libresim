"""JSBSim XML helpers shared by 06_jsbsim_to_json.py: numbers, units, <table>, <function> expression trees.

Expression tree (aero.json "functions" / "axes", engine and fcs functions in config.json), evaluated by game/fdm/aero.gd:
  number
  {"p": "property/name"}
  {"op": NAME, "args": [expr, ...]}
  {"table": TABLE}
TABLE (1-D, 2-D or 3-D; JSBSim lookup row / column / table):
  {"row": prop|null, "col": prop|null, "rows": [...], "cols": [...]|null, "data": [[...]]}              1-D / 2-D
  {"row": prop, "col": prop, "layer": prop, "rows": [...], "cols": [...], "layers": [...],
   "data": [[[...]]]}                                                          3-D: data[layer][row][col]
  3-D with different row breakpoints per layer (FADEC limit tables): "rows": null and "layer_rows": [[...] per layer];
  evaluate each layer with its own rows (clamped), then interpolate between layers.
For 1-D data is [[v], [v], ...] (one value per row); 2-D data[row][col]; JSBSim lookup (clamped linear interpolation
in every dimension) is what aero.gd already does for 1-D / 2-D; the 3-D case interpolates the layer too.

Operator set (JSBSim <function> elements) and what aero.gd must implement:
  n-ary:    sum, product, min, max, avg
  binary:   difference, quotient, pow, atan2, mod, lt, le, gt, ge, eq, ne ("nq" in JSBSim), and, or (n-ary)
  unary:    abs, sqrt, exp, ln, log2, log10, sin, cos, tan, asin, acos, atan, floor, ceil, fraction, neg, not,
            toradians, todegrees
  ternary:  ifthen (cond, then, else)  cond is non-zero = true
  other:    interpolate1d (args: x, then x0, y0, x1, y1 ... pairs, clamped), integral / derivative / lag are stateful and
            NOT converted (recorded in "unconverted"; the A320 aerodynamics do not use them)
  property names are JSBSim ones; a leading "-" in <property> is emitted as {"op": "neg", "args": [{"p": ...}]}.
"""
import xml.etree.ElementTree as ET

LENGTH = {"IN": 0.0254, "FT": 0.3048, "M": 1.0, "CM": 0.01, "KM": 1000.0}
MASS = {"LBS": 0.45359237, "KG": 1.0}
FORCE = {"LBS": 4.4482216152605, "N": 1.0}
AREA = {"FT2": 0.09290304, "M2": 1.0}
SLUGFT2 = {"SLUG*FT2": 1.35581795, "KG*M2": 1.0}
SPRING = {"LBS/FT": 14.5939029, "N/M": 1.0}
DAMP = {"LBS/FT/SEC": 14.5939029, "N/M/SEC": 1.0}
VOLUME_L = {"LTR": 1.0, "GAL": 3.785411784}
OPS = {
    "sum", "product", "min", "max", "avg", "difference", "quotient", "pow", "atan2", "mod",
    "lt", "le", "gt", "ge", "eq", "nq", "ne", "and", "or", "not", "abs", "sqrt", "exp", "ln", "log2", "log10",
    "sin", "cos", "tan", "asin", "acos", "atan", "floor", "ceil", "fraction", "toradians", "todegrees",
    "ifthen", "interpolate1d",
}
OP_RENAME = {"nq": "ne"}
UNSUPPORTED = {"integral", "derivative", "lag_filter", "random", "urandom", "switch", "clipto"}


def parse(path):
    """Parse an XML file keeping comments (they name tanks), tolerating a BOM."""
    return ET.parse(path, parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))).getroot()


def txt(e, tag, default=None, conv=float):
    x = e.find(tag)
    return conv(x.text.strip()) if x is not None and x.text else default


def loc(e, scale=0.0254):
    return [txt(e, a) * scale for a in "xyz"]


def unit_loc(e):
    """Location with its own unit attribute (default inch, JSBSim's default for structure)."""
    return loc(e, LENGTH[e.get("unit", "IN")])


def val(e, tag, table, default=None):
    """Child number scaled by its unit attribute from `table` (unit must be listed: no silent guess)."""
    x = e.find(tag)
    if x is None or not x.text:
        return default
    u = x.get("unit")
    if u is None:
        raise ValueError(f"<{tag}> has no unit attribute; refusing to guess")
    return float(x.text.strip()) * table[u.upper()]


def table(t):
    iv = {i.get("lookup", "row"): i.text.strip() for i in t.findall("independentVar")}
    blocks = t.findall("tableData")

    def rows_of(b):
        return [[float(v) for v in ln.split()] for ln in b.text.strip().splitlines() if ln.strip()]

    if "table" in iv:  # 3-D: one <tableData breakPoint=".."> per layer
        layers, data, layer_rows, cols = [], [], [], None
        for b in blocks:
            r = rows_of(b)
            cols = cols or r[0]
            assert cols == r[0], "3-D table layers differ in column breakpoints"
            layers.append(float(b.get("breakPoint")))
            layer_rows.append([v[0] for v in r[1:]])
            data.append([v[1:] for v in r[1:]])
        out = {"row": iv["row"], "col": iv["column"], "layer": iv["table"], "cols": cols, "layers": layers, "data": data}
        if all(lr == layer_rows[0] for lr in layer_rows):
            out["rows"] = layer_rows[0]
        else:  # ragged: every layer has its own row breakpoints (lookup is clamped inside each layer)
            out["rows"], out["layer_rows"] = None, layer_rows
        return out
    rows = rows_of(blocks[0])
    if "column" in iv:  # 2-D: first line = column breakpoints
        cols, body = rows[0], rows[1:]
        return {"row": iv["row"], "col": iv["column"], "cols": cols,
                "rows": [r[0] for r in body], "data": [r[1:] for r in body]}
    return {"row": iv.get("row"), "col": None, "cols": None,
            "rows": [r[0] for r in rows], "data": [[r[1]] for r in rows]}


def expr(e):
    if e.tag == "property":
        n = e.text.strip()
        return {"op": "neg", "args": [{"p": n[1:]}]} if n.startswith("-") else {"p": n}
    if e.tag == "value":
        return float(e.text)
    if e.tag == "pi":
        return 3.141592653589793
    if e.tag == "table":
        return {"table": table(e)}
    if e.tag in OPS:
        return {"op": OP_RENAME.get(e.tag, e.tag), "args": [expr(x) for x in e if x.tag not in ("description", ET.Comment)]}
    raise ValueError(f"unsupported JSBSim element <{e.tag}>")


def function(f):
    body = [x for x in f if x.tag not in ("description", ET.Comment)]
    assert len(body) == 1, f.get("name")
    return {"name": f.get("name"), "desc": (f.findtext("description") or "").strip(), "f": expr(body[0])}


def try_function(f, unconverted, where):
    """function(f), or None and an entry in `unconverted` when it uses something we do not translate."""
    try:
        return function(f)
    except (ValueError, AssertionError) as ex:
        unconverted.append({"where": where, "name": f.get("name"), "why": str(ex)})
        return None


def aero(root):
    """<aerodynamics> -> aero.json body (JSBSim native units: psf, ft, rad; forces lbf, moments lbf*ft)."""
    a = root.find("aerodynamics") if root.tag != "aerodynamics" else root
    lim = lambda t: ({"min": txt(a.find(t), "min"), "max": txt(a.find(t), "max")} if a.find(t) is not None else None)
    out = {
        "units": "JSBSim native (psf, ft, rad); forces lbf, moments lbf*ft",
        "alpha_limits_rad": lim("alphalimits"),
        "stall_hysteresis": lim("hysteresis_limits"),
        "functions": [function(f) for f in a.findall("function")],
        "axes": {ax.get("name"): [function(f) for f in ax.findall("function")] for ax in a.findall("axis")},
    }
    props = {p.text.strip(): float(p.get("value")) for p in a.findall("property") if p.get("value") is not None}
    if props:  # <property value="0">name</property>: declared aerodynamics inputs with their initial value
        out["properties"] = props
    return out


def cond_text(e):
    """Text of a <test> without its XML comments (comment-aware parse splits it into text + comment tails)."""
    return (e.text or "") + "".join(c.tail or "" for c in e if c.tag is ET.Comment)
