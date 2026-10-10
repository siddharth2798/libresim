class_name Table
## 1-D / 2-D linear table lookup with end clamping (JSBSim semantics).
## t = {row, col, rows: [...], cols: [...]|null, data: [[...]]}


static func _bracket(bp: Array, x: float) -> Array:
	var n := bp.size()
	if n == 1 or x <= bp[0]:
		return [0, 0, 0.0]
	if x >= bp[n - 1]:
		return [n - 1, n - 1, 0.0]
	var i := 0
	while bp[i + 1] < x:
		i += 1
	return [i, i + 1, (x - bp[i]) / (bp[i + 1] - bp[i])]


## Lookup with explicit arguments.
static func eval2(t: Dictionary, x: float, y := 0.0) -> float:
	var r := _bracket(t.rows, x)
	var data: Array = t.data
	if t.cols == null:
		return lerpf(data[r[0]][0], data[r[1]][0], r[2])
	var c := _bracket(t.cols, y)
	var a := lerpf(data[r[0]][c[0]], data[r[0]][c[1]], c[2])
	var b := lerpf(data[r[1]][c[0]], data[r[1]][c[1]], c[2])
	return lerpf(a, b, r[2])


## Lookup with arguments taken from a property context by the table's names.
static func lookup(t: Dictionary, ctx: Dictionary) -> float:
	var x: float = ctx.get(t.row, 0.0)
	var y: float = ctx.get(t.col, 0.0) if t.col != null else 0.0
	return eval2(t, x, y)
