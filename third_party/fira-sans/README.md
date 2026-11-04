# Fira Sans: the libresim UI font (SIL OFL 1.1)

libresim's menus and in-game panels are set in Fira Sans. The font files are shipped **unmodified and not renamed**.

- **Source of the files:** https://github.com/google/fonts/tree/main/ofl/firasans (Google Fonts), version 4.203.
- **Upstream:** https://github.com/mozilla/Fira (Mozilla Foundation and Telefonica S.A.; designed by Carrois Apostrophe and Edenspiekermann).
- **Licence:** SIL Open Font License, Version 1.1 (`OFL.txt`; `OFL-upstream-bBoxType.txt` is the upstream copy). Free to use, embed and
  redistribute; not to be sold by itself; Reserved Font Name "Fira" (see `FONT-NOTICE.txt`).
- **Shipped:** the four weights below, in `game/ui/fonts/` (the files used by the game; this folder keeps the licence and notice).
  The OFL text also goes into the `licenses/` folder of every release archive (`packaging/licenses/fira-sans-OFL.txt`).
- **Unmodified:** the TTFs are byte-identical to the download (checked by sha256 below). Godot only imports them as `FontFile` resources.

| File | sha256 |
|---|---|
| FiraSans-Regular.ttf | `c29556a2719bf613ef3d5e070e40d903a8965d9c081beca1375dc1e6e0f93c23` |
| FiraSans-Medium.ttf | `cbc1842cbed8c1d1146ba7c9db97d8f28c9bedfd25f41c5b0e1259ca48622328` |
| FiraSans-SemiBold.ttf | `db0321f83eb3e9f527b8af384a1b3fefdc1039cf2b06fd39b3f61492bda9561c` |
| FiraSans-Bold.ttf | `a4d8e149ecdd4874a0726eb0af894488b3b31c423d6b0017c8f415ed1b795b45` |

The "libresim" wordmark and the "09/27" mark in `game/branding/` use Fira Sans letter shapes converted to outlines
(`tools/branding/`); that is artwork, covered in `CREDITS.md`.
