extends Node
## In-flight notes about cloud: going into or out of cloud posts nothing (the view and the instruments already
## show it). The storm wind shear warning stays. Code: ui/notifications.gd `_poll_weather`.


func _cards(notes: Notifications) -> Array:
	return notes._cards.map(func(c): return c.key)


func test_no_note_when_entering_or_leaving_cloud() -> String:
	var notes := Notifications.new()
	add_child(notes)
	Props.set_v("environment/ac_in_cloud", false)
	Props.set_v("environment/storm_shear_mps", 0.0)
	notes._poll_weather(30.0)
	Props.set_v("environment/ac_in_cloud", true)
	notes._poll_weather(30.0)  # past the 20 s quiet time, so a note would be posted
	Props.set_v("environment/ac_in_cloud", false)
	notes._poll_weather(30.0)
	var keys := _cards(notes)
	if not keys.is_empty():
		return "cloud entry and exit post nothing, got cards %s" % [keys]
	return ""


func test_storm_wind_shear_note_stays() -> String:
	var notes := Notifications.new()
	add_child(notes)
	Props.set_v("environment/storm_shear_mps", 9.0)
	notes._poll_weather(30.0)
	var keys := _cards(notes)
	Props.set_v("environment/storm_shear_mps", 0.0)
	if not keys.has("shear"):
		return "the wind shear warning is still posted in a storm, got %s" % [keys]
	return ""
