# FlightGear Cessna 172P: corresponding source (GPL-2.0-or-later)

This directory holds the **unmodified original files** from the FlightGear c172p project that free-sim converts into `game/aircraft/c172/models/exterior.glb` and `interior.glb`. Shipping them here satisfies the GPL requirement to provide the corresponding source alongside the converted (object) form.

- **Upstream:** https://github.com/c172p-team/c172p
- **Tag:** `version/2024.1.3`, commit `ee9bc21137cc2f96c5f86886fe908f337923389a`
- **Licence:** GPL-2.0-or-later (see `LICENSE`; per-file attributions in `Thanks`)
- **Authors:** originally by David Megginson; maintained by the c172p team: Gilberto Agostinho, Wayne Bragg, Juan Vera del Campo, onox, Fernando Barbosa (thevirtualfer), Daniel Dubreuil, Jonathan Redpath, Jonathan Schellhase, Tuomas Kuosmanen, Anders Gidenstam, Waldo Kitty, algefaen, Horacio, D-ECHO, Jarl Arntzen, Benedikt Hallinger, Sascha Reißner, Josh Davidson and other contributors.
- **Propeller blade model:** adapted by the c172p team from a model by Syd Adams and Heiko Schulz (c182s project, https://github.com/HHS81/c182s/), GPL-2.0.

## Modifications made by free-sim
The modifications are scripted, so they can be reproduced:
- `tools/blender/convert_c172p.py`:
  - Imports the `.ac` file and removes FlightGear-only objects (click hotspots, light halos, the fast-propeller disc, view blockers).
  - Adds hinge pivots taken from `c172p.xml`, adds normal maps and adjusts roughness.
  - Exports glTF.
- `tools/blender/convert_c172p_interior.py`:
  - Imports the interior, yoke and pedals, removes dome lights and the glass panel, and adds pivots for the yokes, throttle and mixture.
  - Exports glTF.
- In-game glass materials are replaced at runtime (`C172Model.fix_glass`).

## Rebuilding
To regenerate the `.glb` files:
1. Point `data/raw/fg/c172p` at the upstream checkout.
2. Run `blender -b --factory-startup --python tools/blender/convert_c172p.py` (and the `_interior` script).

## Change log (derived data)
- 2026-11-04 (livery masks): `tools/25_livery_masks.py` derives 8-bit grey region masks (`game/aircraft/c172/livery/*.png`: body paint, blue accent, grey pin stripe per atlas) from the unchanged `exterior_fuselage.png`, `exterior_wing.png` and `exterior_tail.png` by colour thresholds. The masks are derived from GPL-2.0-or-later art and are distributed under the same licence. At run time the game recolours a copy of an atlas in memory (`aircraft/common/livery_paint.gd`); no repository texture is changed.
