extends RefCounted
## Resident memory of the running test workers, sampled by the launcher about once a second (one OS call for all
## of them): Linux reads /proc/<pid>/status (VmHWM, the peak so far), macOS and the BSDs ask ps, Windows asks
## tasklist. A job's peak is the largest sample; a job shorter than one sample has none and the sizing falls back
## to its default. Returns pid -> bytes; pids it could not read are left out.


static func sample(pids: Array) -> Dictionary:
	var out := {}
	if pids.is_empty():
		return out
	if OS.get_name() == "Linux":
		for pid in pids:
			var f := FileAccess.open("/proc/%d/status" % pid, FileAccess.READ)
			if f == null:
				continue
			for ln in f.get_as_text().split("\n"):
				if ln.begins_with("VmHWM:"):
					out[pid] = _kb(ln.substr(6))
		return out
	var text := []
	if OS.get_name() == "Windows":
		OS.execute("tasklist", ["/FO", "CSV", "/NH"], text)
		return parse_tasklist("\n".join(text), pids)
	OS.execute("ps", ["-o", "pid=,rss=", "-p", ",".join(pids.map(func(p): return str(p)))], text)
	return parse_ps("\n".join(text), pids)


## ps -o pid=,rss= output: "<pid> <kilobytes>" per line.
static func parse_ps(text: String, pids: Array) -> Dictionary:
	var out := {}
	for ln in text.split("\n"):
		var f := Array(ln.strip_edges().split(" ", false))
		if f.size() >= 2 and int(f[0]) in pids:
			out[int(f[0])] = int(f[1]) * 1024
	return out


## tasklist /FO CSV /NH output: "name","pid","session","#","12,345 K" per line.
static func parse_tasklist(text: String, pids: Array) -> Dictionary:
	var out := {}
	for ln in text.split("\n"):
		var f := Array(ln.strip_edges().split("\",\""))
		if f.size() < 5:
			continue
		var pid := int(str(f[1]))
		if pid in pids:
			out[pid] = _kb(str(f[4]).replace(",", "").replace(".", "").replace("\"", ""))
	return out


static func _kb(s: String) -> int:
	return int(s.strip_edges().replace("kB", "").replace("K", "").strip_edges()) * 1024
