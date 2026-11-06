extends Node
## Real calls for the owner's airports. Not part of the test suite.
##   tools/check_live_weather.sh
## Runs as a scene so the Props autoload exists (a -s script does not load it).


const IDS := ["VABB", "VOCI", "VOGO", "VAPO"]

var _i := 0
var _src: LiveSources


func _ready() -> void:
	_src = LiveSources.new()
	add_child(_src)
	_src.finished.connect(_on)
	_next()


func _next() -> void:
	if _i >= IDS.size():
		get_tree().quit()
		return
	var id: String = IDS[_i]
	var place := LivePlace.of(id)
	print("---- %s  %.2f N  %.2f E  elev %.0f m" % [id, place.lat, place.lon, place.elev_m])
	_src.start(place, 270.0, true, "Fair")


func _on(r: Dictionary) -> void:
	print(str(r.get("status", "")))
	print("tier %s" % str(r.get("tier", "")))
	var w: Dictionary = r.get("weather", {})
	for k in ["wind_dir_deg", "wind_kt", "gust_kt", "temp_c", "dewpoint_c", "qnh_hpa", "visibility_m", "cloud_cover", "cloud_base_ft", "precip", "storms", "icing", "convection", "turbulence"]:
		if w.has(k):
			print("  %s = %s" % [k, w[k]])
	if str(w.get("live_metar", "")) != "":
		print("  METAR %s" % str(w.live_metar))
	_i += 1
	_next()
