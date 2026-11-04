class_name ControlsFilter
extends RefCounted
## The search box of the Controls page: pure rules, no nodes. A query is split at spaces into words; a row matches when
## every word is found (case does not matter) in the row's texts: its action name, its id, and what is bound to it.
## "" matches everything. Used by controls_page.gd to show and hide rows live.

const NO_MATCH := "No match"


## The query as lower-case words ("  Pitch  UP " -> ["pitch", "up"]).
static func words(query: String) -> PackedStringArray:
	return query.strip_edges().to_lower().split(" ", false)


## True when every word of `query` occurs in at least one of `texts` (all of them together, so "pitch w" can
## match the name "Pitch up" plus the key "W"). An empty query matches.
static func matches(query: String, texts: Array) -> bool:
	var w := words(query)
	if w.is_empty():
		return true
	var hay := " ".join(texts.map(func(t): return str(t).to_lower().replace("_", " ")))
	for x in w:
		if not hay.contains(x):
			return false
	return true


## How many of `rows` (each an Array of texts) match.
static func count(query: String, rows: Array) -> int:
	return rows.filter(func(r): return matches(query, r)).size()


## "3 of 17" while a query is typed, "" when it is empty.
static func summary(query: String, shown: int, total: int) -> String:
	return "" if words(query).is_empty() else (NO_MATCH if shown == 0 else "%d of %d" % [shown, total])
