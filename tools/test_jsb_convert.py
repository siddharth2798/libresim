"""Self-check for the JSBSim converter (plain asserts; also collected by pytest if installed).
Run: tools/.venv/bin/python tools/test_jsb_convert.py     (tests needing data/raw skip themselves when it is absent)"""
import importlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import common as c  # noqa: E402
import jsb_expr as x  # noqa: E402

conv = importlib.import_module("06_jsbsim_to_json")


def E(s):
    return ET.fromstring(s)


def test_ops():
    e = x.expr(E("<ifthen><lt><property>a</property><value>1</value></lt><sin><value>0</value></sin><pow><value>2</value><value>3</value></pow></ifthen>"))
    assert e["op"] == "ifthen" and e["args"][0]["op"] == "lt" and e["args"][2]["op"] == "pow"
    assert x.expr(E("<nq><value>1</value><value>2</value></nq>"))["op"] == "ne"
    assert x.expr(E("<property>-a/b</property>")) == {"op": "neg", "args": [{"p": "a/b"}]}
    for bad in ("<integral><value>1</value></integral>", "<switch/>"):
        try:
            x.expr(E(bad))
            raise AssertionError("should be unsupported: " + bad)
        except ValueError:
            pass


def test_tables():
    t1 = x.table(E('<table><independentVar lookup="row">r</independentVar><tableData>0 1\n1 3</tableData></table>'))
    assert t1["rows"] == [0, 1] and t1["data"] == [[1], [3]] and t1["col"] is None
    t2 = x.table(E('<table><independentVar lookup="row">r</independentVar><independentVar lookup="column">c</independentVar>'
                   '<tableData>  0 1\n0 1 2\n5 3 4</tableData></table>'))
    assert t2["cols"] == [0, 1] and t2["rows"] == [0, 5] and t2["data"] == [[1, 2], [3, 4]]
    body = ('<table><independentVar lookup="row">r</independentVar><independentVar lookup="column">c</independentVar>'
            '<independentVar lookup="table">t</independentVar>%s</table>')
    same = x.table(E(body % '<tableData breakPoint="0"> 0 1\n0 1 2</tableData><tableData breakPoint="1"> 0 1\n0 5 6</tableData>'))
    assert same["layers"] == [0, 1] and same["rows"] == [0] and same["data"] == [[[1, 2]], [[5, 6]]]
    rag = x.table(E(body % '<tableData breakPoint="0"> 0 1\n0 1 2</tableData><tableData breakPoint="1"> 0 1\n5 5 6</tableData>'))
    assert rag["rows"] is None and rag["layer_rows"] == [[0], [5]]


def test_units():
    e = E('<m><wingarea unit="FT2">100</wingarea><x>1</x></m>')
    assert abs(x.val(e, "wingarea", x.AREA) - 9.290304) < 1e-9
    try:
        x.val(e, "x", x.AREA)
        raise AssertionError("unit-less value must be refused")
    except ValueError:
        pass
    assert x.unit_loc(E('<location unit="M"><x>1</x><y>2</y><z>3</z></location>')) == [1.0, 2.0, 3.0]
    assert abs(x.unit_loc(E("<location><x>10</x><y>0</y><z>0</z></location>"))[0] - 0.254) < 1e-12  # default inch


def test_c172_byte_identical():
    src = c.RAW / "jsbsim" / "src"
    if not src.exists():
        print("skip c172 (no data/raw/jsbsim)")
        return
    spec = conv.SPECS["c172"]
    root = ET.parse(src / "aircraft" / "c172p" / "c172p.xml").getroot()
    dst = c.ROOT / "game" / "aircraft" / "c172"
    assert json.dumps(conv.aero(root), indent=1) == (dst / "aero.json").read_text(), "c172 aero.json changed"
    assert json.dumps(conv.config(root, spec), indent=1) == (dst / "config.json").read_text(), "c172 config.json changed"


def test_a320():
    src = c.RAW / "fg" / "a320"
    if not (src / "FDE").exists():
        print("skip a320 (run tools/22_a320_fetch.sh)")
        return
    import jsb_a320
    a, cfg = jsb_a320.build(conv.SPECS["a320"], src)
    assert len(cfg["engines"]) == 2 and cfg["apu"]["model"] == "APS3200"
    e = cfg["engines"][0]
    assert abs(e["thrust_n"] - 120102.0) < 5 and e["type"] == "turbine" and e["thrust_table"]["cols"][0] == -10000
    assert len(cfg["gear"]) == 15 and sum(g["retractable"] for g in cfg["gear"]) == 3
    assert [d["lever"] for d in cfg["controls"]["flaps"]["detents"]] == ["0", "1", "1+F", "2", "3", "FULL"]
    assert len(cfg["tanks"]) == 8 and abs(cfg["mass"]["empty_kg"] - 43277.0) < 1
    assert a["axes"].keys() == {"LIFT", "DRAG", "SIDE", "ROLL", "PITCH", "YAW"}
    assert "fcs/spoiler-left-deg" in a["aero_inputs"]["from_systems"]
    assert any("layers" in str(f) for ax in a["axes"].values() for f in ax), "3-D slat tables expected"
    assert all(u["why"] for u in cfg["unconverted"])


if __name__ == "__main__":
    for n, f in list(globals().items()):
        if n.startswith("test_"):
            f()
            print("ok", n)
