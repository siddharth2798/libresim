class_name Table
## 1-D / 2-D / 3-D linear table lookup with end clamping (JSBSim semantics).
## t = {row, col, rows: [...], cols: [...]|null, data: [[...]]}; a 3-D table adds `layer` (property),
## `layers` (breakpoints) and data[layer][row][col]; its rows are shared (`rows`) or per layer
## (`rows: null`, `layer_rows[layer]`). Property names are read from a context with Expr.read.


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


## One row x col plane (cols null: a column of values).
static func _plane(rows: Array, cols: Variant, data: Array, x: float, y: float) -> float:
	var r := _bracket(rows, x)
	if cols == null:
		return lerpf(data[r[0]][0], data[r[1]][0], r[2])
	var c := _bracket(cols, y)
	var a := lerpf(data[r[0]][c[0]], data[r[0]][c[1]], c[2])
	var b := lerpf(data[r[1]][c[0]], data[r[1]][c[1]], c[2])
	return lerpf(a, b, r[2])


## Lookup with explicit arguments.
static func eval2(t: Dictionary, x: float, y := 0.0) -> float:
	return _plane(t.rows, t.cols, t.data, x, y)


## 3-D lookup: each layer's plane, then linear between the two layers around z.
static func eval3(t: Dictionary, x: float, y: float, z: float) -> float:
	var l := _bracket(t.layers, z)
	var a := _layer(t, l[0], x, y)
	if l[2] == 0.0:
		return a
	return lerpf(a, _layer(t, l[1], x, y), l[2])


static func _layer(t: Dictionary, i: int, x: float, y: float) -> float:
	var rows: Array = t.rows if t.get("rows") != null else t.layer_rows[i]
	return _plane(rows, t.cols, t.data[i], x, y)


## Lookup with arguments taken from a property context by the table's names.
static func lookup(t: Dictionary, ctx: Dictionary) -> float:
	var x := Expr.read(ctx, t.row)
	var y := Expr.read(ctx, t.col) if t.col != null else 0.0
	if t.get("layer") != null:
		return eval3(t, x, y, Expr.read(ctx, t.layer))
	return eval2(t, x, y)
