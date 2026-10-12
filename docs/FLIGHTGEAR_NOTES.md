# FlightGear: reusable assets, licences and roadmap (researched 2026-10-10)

## Reusable assets
- **C172 exterior + cockpit**
  - Source: https://github.com/c172p-team/c172p (tag `version/2024.1.3`). It is a 172**P**; the panel differs from our 172S.
  - Exterior: `Models/c172-common.ac` plus PNG textures in `Models/`.
  - Steam cockpit: `Models/Interior/Panel/c172p-panel/c172p-interior.ac`. Instruments are in `Models/Interior/Panel/Instruments/*`.
  - Licence: GPL-2.0-or-later (some files CC-BY/CC0, listed in the repo's `Thanks` file).
- **Converting:** Blender add-on NikolaiVChr/Blender-AC3D (branch `4.3`) → import `.ac` → export `.glb`.
  - XML animations and effects are lost. Keep the object names so GDScript can animate the parts.
  - FlightGear axes are X aft, Y right, Z up, so add a root rotation in Godot.
- **Sounds:** the c172p engine sounds derive from Freesound #322321 (CC0). Download that original instead of the GPL repo copy.

## Licensing in plain terms
- **Local/private use:** no obligations.
- **Distributing with c172p assets:**
  - Ship their source (`.ac` and XML, plus our converted files) and the GPL text and credits, and note our modifications.
  - Simplest route: license libresim as GPL-2.0-or-later, or ship the GPL assets as a separate pack.
- **Imagery:** s2cloudless 2024 is CC BY-NC-SA, so the bundle can't be sold. The 2016 layer (CC BY) is the alternative if commercial use is ever wanted.

## FlightGear roadmap (stable 2024.1.x; next major release has no date)
- **In `next`:**
  - HDR/PBR compositor with GTAO and aerial perspective
  - volumetric voxel clouds (since 2026-03)
  - WS3.0 scenery as the default
  - OpenXR VR (preliminary)
  - Qt6 launcher and Canvas GUI
- **No visible work on:** new ATC, CPDLC, Vulkan, or a multiplayer overhaul.

## Where libresim can get there first
1. Photoreal satellite terrain out of the box (we already have it).
2. Offline neural-TTS ATC with Mumbai/Pune phraseology (Piper).
3. First-class VR through Godot OpenXR.
4. Monsoon weather: volumetric clouds, rain on the windshield, Ghats ridge lift (ridge lift already done).
5. Guided lessons tied to POH checklists, with automatic debriefs from the property tree.
6. One-click small download: a single binary plus a regional pack.
7. Touch/tablet port.
8. A PBR cockpit with modelled instrument errors (the errors are already done).
