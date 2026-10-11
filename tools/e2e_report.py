#!/usr/bin/env python3
"""Builds the E2E sweep report (tools/e2e.sh): <run>/report.md.
Adds checks the game can't do itself: script errors in each log, screenshot statistics
(not mostly black / grey), the recorded MKV (ffprobe + full decode), and comparison
with the reference screenshots in /tmp/e2e/ref (created on the first run)."""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ERR = re.compile(r"SCRIPT ERROR|ERROR:|Parse Error")
REF = Path("/tmp/e2e/ref")


def log_errors(log: Path):
    if not log.exists():
        return ["(no log)"]
    lines = log.read_text(errors="replace").splitlines()
    out = []
    for i, ln in enumerate(lines):
        if ERR.search(ln):
            at = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:") else ""
            s = (ln.strip() + " " + at).strip()
            if s not in out:
                out.append(s)
    return out


def image_stats(path: Path):
    im = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    lum = im @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    sat = im.max(axis=2) - im.min(axis=2)
    return {"mean": float(lum.mean()), "std": float(lum.std()), "black": float((lum < 12).mean()),
            "grey": float(((sat < 12) & (lum > 40)).mean())}


def image_check(st, expect):
    if expect == "dark":
        ok = st["std"] > 2.0 and st["black"] < 0.995
    elif expect == "grey":
        ok = st["black"] < 0.6 and st["std"] > 4.0
    else:
        ok = st["black"] < 0.5 and st["std"] > 10.0 and st["grey"] < 0.85
    return ok, "mean %.0f std %.0f black %.0f%% grey %.0f%% (expect %s)" % (
        st["mean"], st["std"], st["black"] * 100, st["grey"] * 100, expect)


def ref_check(tag, path: Path, out: Path, healthy: bool):
    ref = REF / (tag + ".png")
    if not ref.exists() and not healthy:
        return False, "no reference yet, and this run is not healthy enough to become one"
    if not ref.exists():
        shutil.copy(path, ref)
        return True, "reference created"
    a = np.asarray(Image.open(ref).convert("RGB"), dtype=np.float32)
    b = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    if a.shape != b.shape:
        return False, f"size changed {a.shape} -> {b.shape}"
    d = np.abs(a - b)
    rmse = float(np.sqrt((d ** 2).mean()))
    Image.fromarray(np.clip(d * 3, 0, 255).astype(np.uint8)).save(out / "shots" / (tag + "_refdiff.png"))
    return rmse < 25.0, f"RMSE {rmse:.1f} vs reference (changed pixels >40: {(d.max(axis=2) > 40).mean() * 100:.1f}%)"


def mkv_check(path):
    if not path or not Path(path).exists():
        return False, "no MKV file"
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name,width,height:format=duration",
                        "-of", "json", path], capture_output=True, text=True)
    try:
        info = json.loads(p.stdout)
    except json.JSONDecodeError:
        return False, "ffprobe failed: " + p.stderr[:200]
    streams = info.get("streams", [])
    cdur = info.get("format", {}).get("duration", "N/A")
    pts = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "packet=pts_time", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.split()
    dur = float(pts[-1]) if pts else 0.0
    dec = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "null", "-"], capture_output=True, text=True)
    errs = len(dec.stderr.strip().splitlines())
    kinds = sorted(f"{s['codec_type']}:{s['codec_name']}" for s in streams)
    ok = any(k.startswith("video") for k in kinds) and any(k.startswith("audio") for k in kinds) and dur > 4.0 and errs == 0
    return ok, f"{kinds} {len(pts)} video frames over {dur:.1f}s (container duration {cdur}), decode errors {errs} {dec.stderr.strip()[:120]}"


def main(out: Path):
    expect, order = {}, []
    for ln in (out / "jobs.tsv").read_text().splitlines():
        g, tag, exp, _ = ln.split("\t")
        expect[tag] = exp
        order.append((g, tag))
    rows = []  # (job, check, ok, detail)
    unit = out / "logs/unit_tests.log"
    if unit.exists():
        txt = unit.read_text(errors="replace")
        m = re.search(r"(\d+)/(\d+) passed", txt)
        rows.append(("unit_tests", "all unit tests", bool(m) and m.group(1) == m.group(2), m.group(0) if m else "no summary (crashed?)"))
        for f in re.findall(r"FAIL\s+(\S+): (.*)", txt):
            rows.append(("unit_tests", f[0], False, f[1][:200]))
        errs = log_errors(unit)
        rows.append(("unit_tests", "no script errors", not errs, "; ".join(errs[:3])))
    tags = [("menu", t) for t in ["menu_phase1", "menu_fly", "menu_phase2"] if (out / "logs" / (t + ".log")).exists()] + order
    metrics, shots = {}, []
    for g, tag in tags:
        res = out / "results" / (tag + ".json")
        exitf = out / "logs" / (tag + ".exit")
        if not res.exists():
            tail = (out / "logs" / (tag + ".log")).read_text(errors="replace").splitlines()[-4:] if (out / "logs" / (tag + ".log")).exists() else []
            rows.append((tag, "finished", False, "no result (%s): %s" % (exitf.read_text().strip() if exitf.exists() else "?", " / ".join(tail)[:300])))
            continue
        d = json.loads(res.read_text())
        for c in d["checks"]:
            rows.append((tag, c["name"], c["ok"], c["detail"]))
        errs = log_errors(out / "logs" / (tag + ".log"))
        if tag != "menu_fly":
            rows.append((tag, "no script errors", not errs, "; ".join(errs[:4])[:500]))
        if exitf.exists():
            rc = exitf.read_text().split()[0]
            tail = (out / "logs" / (tag + ".log")).read_text(errors="replace").strip().splitlines()[-2:]
            rows.append((tag, "clean exit", rc == "0", f"exit code {rc}: {' / '.join(tail)[:200]}" if rc != "0" else ""))
        metrics[tag] = d.get("metrics", {})
        for s in d.get("shots", []):
            p = Path(s["path"])
            if not p.exists():
                rows.append((tag, "shot " + s["name"], False, "missing " + str(p)))
                continue
            ok, det = image_check(image_stats(p), "dark" if "night" in s["name"] else expect.get(tag, "normal"))
            rows.append((tag, "image " + s["name"], ok, det))
            shots.append(str(p))
            if g == "ref":
                ok, det = ref_check(tag, p, out, all(c["ok"] for c in d["checks"]) and not errs)
                rows.append((tag, "matches reference", ok, det))
        if d.get("scenario") == "record":
            rows.append((tag, "mkv playable (ffprobe/ffmpeg)", *mkv_check(d["metrics"].get("mkv"))))
    write(out, rows, metrics)


def write(out: Path, rows, metrics):
    git = (out / "git.txt").read_text().splitlines()
    jobs = {}
    for job, name, ok, det in rows:
        jobs.setdefault(job, []).append((name, ok, det))
    nf = sum(1 for r in rows if not r[2])
    L = [f"# free-sim E2E sweep — {out.name}", "", f"Commit: `{git[0][:120] if git else '?'}`  ",
         f"Uncommitted files at start: {len(git) - 1}  ", f"**{len(rows) - nf}/{len(rows)} checks passed, {nf} failed, "
         f"{sum(1 for j in jobs.values() if all(c[1] for c in j))}/{len(jobs)} jobs fully green.**", "",
         "## Failures", "", "| Job | Check | Detail |", "|---|---|---|"]
    for job, name, ok, det in rows:
        if not ok:
            L.append(f"| {job} | {name} | {str(det).replace('|', '/')[:400]} |")
    L += ["", "## All jobs", "", "| Job | Result | Checks | Failed checks |", "|---|---|---|---|"]
    for job, cs in jobs.items():
        bad = [c[0] for c in cs if not c[1]]
        L.append(f"| {job} | {'PASS' if not bad else 'FAIL'} | {len(cs) - len(bad)}/{len(cs)} | {', '.join(bad)} |")
    perf = {k: v for k, v in metrics.items() if k.startswith("perf_")}
    if perf:
        L += ["", "## Performance (VABB 27, 1500 ft final, 30 s)", "", "| Preset | Avg FPS | 1% low FPS | p99 ms | Max ms | >50 ms | >100 ms |", "|---|---|---|---|---|---|---|"]
        for k, m in perf.items():
            if "avg_fps" in m:
                L.append(f"| {m['quality']} | {m['avg_fps']:.1f} | {m['low1_fps']:.1f} | {m['p99_ms']:.1f} | {m['max_ms']:.0f} | {m['spikes_50ms']} | {m['spikes_100ms']} |")
    L += ["", "## Gameplay metrics", ""]
    for k, m in metrics.items():
        if m and not k.startswith(("rwy_", "air_", "stand_", "ref", "wx_", "tod_")):
            L.append(f"- **{k}**: " + ", ".join(f"{a}={(round(b, 2) if isinstance(b, float) else b)}" for a, b in m.items())[:900])
    L += ["", "## Start positions", "", "| Job | AGL m | wow | KIAS | hdg | moved m |", "|---|---|---|---|---|---|"]
    for k, m in metrics.items():
        if k.startswith(("rwy_", "air_", "stand_")) and m:
            L.append(f"| {k} | {m.get('agl_m', 0):.2f} | {m.get('wow')} | {m.get('kias', 0):.0f} | {m.get('hdg', 0):.0f} | {m.get('moved_m', 0):.1f} |")
    L += ["", "<details><summary>Every check</summary>", "", "| Job | Check | Result | Detail |", "|---|---|---|---|"]
    for job, name, ok, det in rows:
        L.append(f"| {job} | {name} | {'PASS' if ok else 'FAIL'} | {str(det).replace('|', '/')[:250]} |")
    L += ["", "</details>", "", f"Screenshots: `{out}/shots/`, logs: `{out}/logs/`, references: `{REF}`"]
    (out / "report.md").write_text("\n".join(L) + "\n")
    print(f"report: {len(rows) - nf}/{len(rows)} checks passed; {out / 'report.md'}")


if __name__ == "__main__":
    REF.mkdir(parents=True, exist_ok=True)
    main(Path(sys.argv[1]))
