"""The eight logo options: metadata, palettes, fonts."""
from logo_options_lockup import Option
from logo_options_marks_a import THEMES_1, THEMES_2, THEMES_3, THEMES_4, mark_1, mark_2, mark_3, mark_4
from logo_options_marks_b import THEMES_5, THEMES_6, THEMES_7, THEMES_8, lockup_7, mark_5, mark_6, mark_7, mark_8

OPEN_SANS = "Open Sans (Apache-2.0)"
FIRA = "Fira Sans (SIL OFL 1.1)"
SLAB = "Roboto Slab (Apache-2.0)"

OPTIONS = [
    Option(1, "badge", "Badge", "High-wing C172 climbing out in a round badge, horizon tint below",
           "navy, white, orange cheat-line", f"{OPEN_SANS} SemiBold", THEMES_1, "light", mark_1,
           word=("opensans", "Semibold"), tag=("opensans", "Regular"), track=0.0),
    Option(2, "wing-l", "Wing-l", "Top-view light aircraft whose fuselage is the letter l; chevron wings",
           "navy, sky blue", f"{FIRA} SemiBold", THEMES_2, "light", mark_2,
           word=("fira", "SemiBold"), tag=("fira", "Regular"), word_size=116, track=0.005, mark_size=196, mark_bg=True),
    Option(3, "climb-out", "Climb-out", "Two horizon lines with a light aircraft rotating away above them",
           "charcoal, aviation orange", f"{OPEN_SANS} Regular", THEMES_3, "light", mark_3,
           word=("opensans", "Regular"), tag=("opensans", "Regular"), word_size=118, track=0.005, mark_size=240, mark_bg=True),
    Option(4, "ghats", "Ghats", "Flat-topped Sahyadri ridges with an aircraft above, round badge",
           "deep green, cream", f"{SLAB} Bold", THEMES_4, "light", mark_4,
           word=("robotoslab", "Bold"), tag=("opensans", "Regular"), word_size=104, track=0.0),
    Option(5, "runway-09", "Runway 09", "Runway designator 09 over threshold piano keys (VABB 09/27)",
           "asphalt black, white, amber", f"{FIRA} Medium", THEMES_5, "light", mark_5,
           word=("fira", "Medium"), tag=("fira", "Regular"), word_size=116, track=0.03),
    Option(6, "monogram", "Monogram ls", "Heavy ls monogram, the l cut at a climb angle, rounded tile",
           "teal, white", f"{OPEN_SANS} ExtraBold", THEMES_6, "light", mark_6,
           word=("opensans", "ExtraBold"), tag=("opensans", "Regular"), word_size=108, track=-0.005),
    Option(7, "plane-dot", "Plane dot", "Wordmark only: a small aircraft replaces the dot of the i",
           "ink, signal red", f"{FIRA} Medium", THEMES_7, "light", mark_7,
           word=("fira", "Medium"), tag=("fira", "Regular"), word_size=170, track=0.0, custom=lockup_7),
    Option(8, "paper-plane", "Paper plane", "Folded paper plane at the end of a dotted flight path",
           "indigo tints", f"{OPEN_SANS} Bold", THEMES_8, "light", mark_8,
           word=("opensans", "Bold"), tag=("opensans", "Regular"), word_size=108, track=0.0, mark_size=244, mark_bg=True),
]
