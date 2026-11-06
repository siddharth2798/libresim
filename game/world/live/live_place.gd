class_name LivePlace
extends RefCounted
## The airport the live fetch asks about: rounded later by the source URLs. Position comes from the
## same ENU frame as the rest of the sim.


static func of(icao: String) -> Dictionary:
	var db := NavDatabase.new()
	var a := db.airport(icao)
	var ll := Geo.to_latlon(float(a.get("x", 0.0)), float(a.get("y", 0.0))) if not a.is_empty() else Vector2(Geo.LAT0, Geo.LON0)
	var cities = Paths.load_res_json("res://world/airport_cities.json")
	var city := str(cities.get(icao, "")) if cities is Dictionary else ""
	var label := city if city != "" else str(a.get("name", icao))
	return {"lat": ll.x, "lon": ll.y, "elev_m": float(a.get("elev_m", 0.0)), "name": label, "icao": icao}
