extends RefCounted
## How many test workers this computer can run at once (tests/parallel/run_parallel.gd). Read from the machine at
## every run, never fixed: one worker per logical core minus one (left for the launcher, the OS and the threads a
## test starts), no more than the memory the OS reports free can hold, never more than the jobs queued, and at
## least one. TEST_JOBS=N overrides the count (TEST_JOBS=1 runs the plain single process).
## Memory: each job's peak resident size is measured while it runs (par_rss.gd) and kept in the timings cache;
## the typical worker is the 75th percentile of the queued jobs' estimated peaks, and a job starts only while the
## running jobs' estimates plus its own fit the budget (fits()). With no history DEFAULT_PEAK is assumed: the heaviest
## suite measured (the full "Fly" flows, test_real_flight_start) peaked at about 1.1 GB resident in a headless
## Godot 4.7 worker, light suites at about 0.2-0.3 GB.

const DEFAULT_PEAK := 1200 * 1024 * 1024
const RESERVE := 512 * 1024 * 1024  # left to the OS and the launcher when sizing by memory


## The machine as Godot reports it: logical cores and available memory in bytes (-1 when the OS does not say).
static func machine() -> Dictionary:
	var mem := OS.get_memory_info()
	var avail := int(mem.get("available", -1))
	if avail <= 0:
		avail = int(mem.get("free", -1))
	return {"cores": OS.get_processor_count(), "available": avail, "physical": int(mem.get("physical", -1))}


## cores, available (bytes or -1), typical_peak (bytes per worker), jobs (queued), override (TEST_JOBS, 0 = auto).
## Returns {workers, by_cores, by_memory (-1 = unknown), budget (bytes for jobs, -1 = unknown), why}.
static func workers(cores: int, available: int, typical_peak: int, jobs: int, override: int) -> Dictionary:
	var by_cores := maxi(1, cores - 1)
	var budget := maxi(0, available - RESERVE) if available > 0 else -1
	var by_memory := maxi(1, budget / maxi(1, typical_peak)) if budget >= 0 else -1
	var n := by_cores if by_memory < 0 else mini(by_cores, by_memory)
	var why := "%d logical cores - 1 = %d" % [cores, by_cores]
	if by_memory >= 0:
		why += "; %.1f GB available - %.1f GB reserve fits %d workers of %.2f GB" % [_gb(available), _gb(RESERVE), by_memory, _gb(typical_peak)]
	else:
		why += "; free memory unknown, not capped by memory"
	if override > 0:
		n = override
		why = "TEST_JOBS=%d (%s)" % [override, why]
	if jobs < n:
		why += "; only %d jobs" % jobs
	n = maxi(1, mini(n, maxi(1, jobs)))
	return {"workers": n, "by_cores": by_cores, "by_memory": by_memory, "budget": budget, "why": why}


## The typical worker peak: 75th percentile of the measured job peaks, DEFAULT_PEAK with none.
static func typical_peak(peaks: Array) -> int:
	if peaks.is_empty():
		return DEFAULT_PEAK
	var s := peaks.duplicate()
	s.sort()
	return int(s[mini(s.size() - 1, int(s.size() * 0.75))])


## May a job with this estimated peak start now? Always when nothing runs; otherwise the running jobs' estimated
## peaks plus this one must fit the budget (budget -1: memory unknown, only the worker count limits).
static func fits(running_peaks: Array, peak: int, budget: int) -> bool:
	if running_peaks.is_empty() or budget < 0:
		return true
	var sum := peak
	for p in running_peaks:
		sum += int(p)
	return sum <= budget


static func _gb(b: int) -> float:
	return float(b) / (1024.0 * 1024.0 * 1024.0)
