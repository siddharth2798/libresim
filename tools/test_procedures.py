"""Self-check for the SID / STAR parsers (tools/procedures_aip.py). Plain asserts, also collected by pytest if installed.
Run: python3 tools/test_procedures.py. No data/ files, network or pdftotext needed: the text is in the layout pdftotext gives."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import procedures_aip as pa  # noqa: E402

SID = """
     SID PPN3A - RWY 27
      Serial Path         Waypoint      Fly-         Course        Distance  Turn            Altitude       Speed        VPA      Navigation
     Number Descriptor    Identifier    Over         ºM(ºT)         (NM)    Direction           (ft)        Limit        (%)     Specification
        10        VA                             270.27(269.52)                              +1700                        7        RNAV 1
        20        DF      BB150                                                      L       +6000                                 RNAV 1
        30        TF      BB155                 173.90(173.15)     10.55                    -FL120                                 RNAV 1
                                                                                            +FL110
        40        TF      NM557                 084.27(083.52)     20.01                    +FL150                                 RNAV 1
        70        TF      PPN                   116.10(115.35)     31.27                    @FL280                                 RNAV 1
"""

STAR = """
     STAR OPAKA 3K RWY 27
      Serial    Path          Waypoint      Fly-            Course         Distance     Turn        Altitude     Speed     VPA    Navigation
       10           IF         OPAKA                                                                                               RNAV 1
       20          TF          VELKO                   258.34°(257.59°)     55.83                   +FL120      -230.00            RNAV 1
       40          TF          BB259                   246.30°(245.55°)     11.00                   @FL110      @190.00            RNAV 1
       60          VM                                  180.00°(179.25°)                                                            RNAV 1
       10          HM          VELKO        Y          255.00°(254.25°)     10.00          L        -FL180      -230.00            RNAV1
                                                                                                    +FL100
"""

CONV = """
                                       OPAKA 2A      28       Climb on runway Hdg to D 5.0 PPN at or above 2900', Climbing turn right Hdg 077° to intercept R030.
                                       AVKOR 2A      28       Climb on runway Hdg to 5000' atPDG not below 5.5% , Climbing turn left Hdg 123° to intercept R175.
"""


def test_sid_table():
    p = pa.parse_tables(SID)
    assert len(p) == 1 and p[0]["kind"] == "SID" and p[0]["name"] == "PPN3A" and p[0]["rwy"] == "27"
    legs = p[0]["legs"]
    assert [g["fix"] for g in legs] == ["BB150", "BB155", "NM557", "PPN"]  # the VA leg has no fix
    assert legs[0] == {"fix": "BB150", "lo_ft": 6000}
    assert legs[1]["lo_ft"] == 11000 and legs[1]["hi_ft"] == 12000  # a window on two lines
    assert legs[3]["lo_ft"] == 28000 and legs[3]["hi_ft"] == 28000


def test_star_table():
    p = pa.parse_tables(STAR)
    assert len(p) == 1 and p[0]["name"] == "OPAKA3K"
    legs = p[0]["legs"]
    assert [g["fix"] for g in legs] == ["OPAKA", "VELKO", "BB259"]  # the holding after the VM leg is not part of it
    assert legs[1] == {"fix": "VELKO", "lo_ft": 12000, "spd_kt": 230}
    assert legs[2]["lo_ft"] == legs[2]["hi_ft"] == 11000 and legs[2]["spd_kt"] == 190
    assert abs(p[0]["vectors_true"] - 179.25) < 1e-6


def test_waypoints():
    w = pa.parse_waypoints("    8     BB104    N 19:05:21.34 E 073:00:55.26    52    BB266     N 19:12:18.57 E 073:18:43.00")
    assert set(w) == {"BB104", "BB266"}
    assert abs(w["BB104"][0] - (19 + 5 / 60 + 21.34 / 3600)) < 1e-6 and abs(w["BB104"][1] - (73 + 55.26 / 3600)) < 1e-6


def test_conventional():
    r = pa.parse_conventional(CONV)
    assert [x["name"] for x in r] == ["OPAKA2A", "AVKOR2A"]
    assert r[0]["rwy"] == "28" and r[0]["end"] == "OPAKA" and r[0]["dme"] == (5.0, "PPN", 2900)
    assert r[1]["dme"] is None


def test_dme_fix():
    assert pa.dme_ident(271.4, 5.0) == "D271E"
    hit = pa.ray_circle((0.0, 0.0), 270.0, (1000.0, 0.0), 3000.0)  # start 1 km west of the VOR, fly west: 2 km more
    assert abs(hit[0] + 2000.0) < 1e-6 and abs(hit[1]) < 1e-6


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("test_procedures: ok")
