class_name TaxiRoute
extends RefCounted
## A* over an airport taxi graph (airport_ops.json "taxi": nodes {id: [x, y]}, edges [a, b, ref, ..., kind]).


## Returns {path: [[x, y], ...] from the node nearest `from` to the node nearest `to`, via: taxiway refs used},
## or {} if no route. Runway edges are not used.
static func find(g: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	if g.is_empty():
		return {}
	var adj := {}
	for e in g.edges:
		if e[4] == "runway":
			continue  # don't taxi along runways unless unavoidable
		for pair in [[e[0], e[1]], [e[1], e[0]]]:
			if not adj.has(pair[0]):
				adj[pair[0]] = []
			adj[pair[0]].append([pair[1], str(e[2])])
	var nearest := func(p: Vector2) -> String:
		var best := ""
		var bd := INF
		for id in adj:
			var q: Array = g.nodes[id]
			var d := p.distance_squared_to(Vector2(q[0], q[1]))
			if d < bd:
				bd = d
				best = id
		return best
	var s: String = nearest.call(from)
	var t: String = nearest.call(to)
	if s == "" or t == "":
		return {}
	var pos := func(id: String) -> Vector2: return Vector2(g.nodes[id][0], g.nodes[id][1])
	var open := {s: true}
	var came := {}
	var gs := {s: 0.0}
	var tp: Vector2 = pos.call(t)
	while not open.is_empty():
		var cur := ""
		var bf := INF
		for id in open:
			var f: float = gs[id] + (pos.call(id) as Vector2).distance_to(tp)
			if f < bf:
				bf = f
				cur = id
		if cur == t:
			break
		open.erase(cur)
		for nb in adj.get(cur, []):
			var ng: float = gs[cur] + (pos.call(cur) as Vector2).distance_to(pos.call(nb[0]))
			if ng < gs.get(nb[0], INF):
				gs[nb[0]] = ng
				came[nb[0]] = [cur, nb[1]]
				open[nb[0]] = true
	if not came.has(t) and s != t:
		return {}
	var path: Array = [pos.call(t)]
	var refs: Array[String] = []
	var c := t
	while came.has(c):
		var r: String = came[c][1]
		if r != "" and (refs.is_empty() or refs[-1] != r):
			refs.append(r)
		c = came[c][0]
		path.push_front(pos.call(c))
	refs.reverse()
	return {"path": path, "via": refs}
