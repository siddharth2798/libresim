extends Node
## The Training page (ui/menu/training_page.gd, lesson_card.gd, lesson_info.gd): the lesson texts, the cards with the
## stars you earned, the chosen lesson's detail, the help level and START LESSON. Progress is read from a scratch file
## (TrainingLogic.save_path is redirected), never from the player's user://training.json.

const STARS := "user://_training_page_stars.json"

var _keep := {}
var _nodes: Array[Node] = []


func _begin(stars := {}) -> void:
	if _keep.is_empty():
		_keep = {"setup": Session.setup, "stars": TrainingLogic.save_path}
	Session.setup = Session.DEFAULT.duplicate(true)
	TrainingLogic.save_path = STARS
	var f := FileAccess.open(STARS, FileAccess.WRITE)
	f.store_string(JSON.stringify(stars))
	f.close()


func _page() -> Control:
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/training_page.gd"))
	add_child(p)
	_nodes.append(p)
	return p


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if not _keep.is_empty():
		Session.end_lesson()
		Session.setup = _keep.setup
		TrainingLogic.save_path = _keep.stars
		_keep = {}
	if FileAccess.file_exists(STARS):
		DirAccess.remove_absolute(STARS)


func test_lesson_info_texts() -> String:
	var take := TrainingLogic.find("takeoff")
	var land := TrainingLogic.find("landing")
	var chips := LessonInfo.chips(take)
	if chips != ["About 5 minutes", "5 steps", "VAPO runway 28", "Clear · 10:00 · wind 280/4"]:
		return "takeoff chips: %s" % [chips]
	if LessonInfo.where(take) != "On VAPO runway 28, engine running.":
		return "where (runway): " + LessonInfo.where(take)
	if LessonInfo.where(land) != "In the air on the approach to VAPO runway 28 (3 nm out, 1000 ft, 80 kt).":
		return "where (air): " + LessonInfo.where(land)
	if LessonInfo.markers(take) != "Markers: centreline marker." or LessonInfo.markers(TrainingLogic.find("cruise")) != "":
		return "markers: '%s'" % LessonInfo.markers(take)
	if LessonInfo.markers(land) != "Markers: centreline marker, glide-path rings, aim point.":
		return "markers (landing): " + LessonInfo.markers(land)
	if LessonInfo.step_titles(take)[0] != "Full power" or LessonInfo.learn(take).size() != 3:
		return "steps / learn"
	if LessonInfo.aircraft_name(take) != "Cessna 172S":
		return "aircraft name: '%s'" % LessonInfo.aircraft_name(take)
	if LessonInfo.aircraft_name({}) != "":
		return "a lesson for any aircraft names none"
	if PageStyles.stars_text(0) != "not flown yet" or PageStyles.stars_text(2) != "★★☆" or PageStyles.stars_text(9) != "★★★":
		return "stars text"
	return ""


func test_training_page_cards_show_stars() -> String:
	_begin({"takeoff": 3, "cruise": 1})
	var p := _page()
	if p._cards.size() != TrainingLogic.lessons_for("c172").size() or p._cards.size() < 3:
		return "one card per lesson of the aircraft: %d" % p._cards.size()
	if p._cards[0]._stars.text != "★★★" or p._cards[1]._stars.text != "★☆☆" or p._cards[2]._stars.text != "not flown yet":
		return "stars: %s | %s | %s" % [p._cards[0]._stars.text, p._cards[1]._stars.text, p._cards[2]._stars.text]
	if not p._cards[0].button_pressed or p._title.text != "Takeoff":
		return "the first lesson starts chosen"
	return ""


func test_training_page_choose_lesson_and_help() -> String:
	_begin()
	var p := _page()
	var changes := [0]
	p.changed.connect(func(): changes[0] += 1)
	p._cards[1].pressed.emit()
	if p._title.text != "Cruise" or not p.summary().begins_with("Cruise  ·  Full guidance") or changes[0] != 1:
		return "choosing Cruise: '%s' / '%s'" % [p._title.text, p.summary()]
	if p._chips.get_child_count() != 4 or p._steps.get_child_count() != 7:
		return "chips %d, steps %d" % [p._chips.get_child_count(), p._steps.get_child_count()]
	p._help[1].pressed.emit()
	if p._assist != "light" or p._assist_note.text != "Step card, hints and callouts. No gauges or markers." or not p.summary().ends_with("Hints only"):
		return "help level: %s '%s'" % [p._assist, p.summary()]
	return ""


func test_training_page_start_begins_the_lesson() -> String:
	_begin()
	var p := _page()
	var started := [false]
	p.start_requested.connect(func(): started[0] = true)
	p._cards[2].pressed.emit()
	p._help[2].pressed.emit()
	p.start()
	if not started[0] or Session.training != "landing" or Session.assist != "off":
		return "start: %s '%s' '%s'" % [started[0], Session.training, Session.assist]
	return ""


# ---- "Where you start" on the airport diagram (lesson_map.gd) --------------------------------

func _fake() -> Array:
	return [{"icao": "VAXX", "runways": [{"length": 1800.0, "width": 30.0, "ends": [
		{"ident": "09", "x": -900.0, "y": 0.0, "heading_true": 90.0}, {"ident": "27", "x": 900.0, "y": 0.0, "heading_true": 270.0}]}],
		"taxiways": [PackedVector2Array([Vector2(0, 0), Vector2(0, 100)])]}]


func test_lesson_map_geometry_runway_and_air_starts() -> String:
	var rw := {"setup": {"airport": "VAXX", "runway": "27", "start": "runway"}}
	var a := LessonMap.spec(rw, _fake())
	if not a.ok or a.runway != "27" or a.runways.size() != 1 or a.taxiways.size() != 1:
		return "runway start spec: %s" % [a]
	var thr := Vector2(900.0, 0.0)
	var f := Vector2(sin(deg_to_rad(270.0)), cos(deg_to_rad(270.0)))
	if not a.start.pos.is_equal_approx(thr + f * 25.0) or a.start.from != Vector2.INF or float(a.start.heading) != 270.0 or a.start.label != "":
		return "runway start: 25 m past the threshold, no approach track: %s" % [a.start]
	var air := LessonMap.spec({"setup": {"airport": "VAXX", "runway": "09", "start": "air", "air_nm": 6.0}}, _fake())
	if not air.ok or not air.start.pos.is_equal_approx(Vector2(-900.0, 0.0) - Vector2(1.0, 0.0) * 6.0 * 1852.0) or not air.start.from.is_equal_approx(Vector2(-900.0, 0.0)) or air.start.label != "6 nm out":
		return "air start: 6 nm out on the extended centreline: %s" % [air.start]
	for bad in [{"setup": {"airport": "NOPE", "runway": "27"}}, {"setup": {"airport": "VAXX", "runway": "99"}}, {}]:
		if LessonMap.spec(bad, _fake()).ok:
			return "an unknown airport or runway must give ok = false: %s" % [bad]
	return ""


func test_training_page_draws_the_lessons_start_on_a_small_diagram() -> String:
	if LessonMap.airport("VAPO").is_empty():
		return ""  # the lessons fly at Pune: nothing to draw without data/processed
	_begin()
	var p := _page()
	var d: AirportDiagram = p._diagram
	if d == null or not d.read_only or d.mouse_filter != Control.MOUSE_FILTER_IGNORE or d.custom_minimum_size.y > 200.0 or d.custom_minimum_size.y < 100.0:
		return "a compact read-only diagram: %s" % [d]
	var l: Dictionary = p._lessons[0]
	if not d.visible or d.selected_runway != str(l.setup.runway) or d.runways.is_empty() or d.start.is_empty() or d.start.from != Vector2.INF:
		return "lesson 0 (%s %s): runway %s, start %s" % [l.setup.airport, l.setup.start, d.selected_runway, d.start]
	if not LessonInfo.where(l).begins_with("On VAPO runway"):
		return "the text stays: " + LessonInfo.where(l)
	var k := 1  # Cruise: in the air, 6 nm out
	p._cards[k].pressed.emit()
	var l2: Dictionary = p._lessons[k]
	if d.selected_runway != str(l2.setup.runway) or d.start.from == Vector2.INF or d.start.label != "%s nm out" % FailuresLogic.fmt(float(l2.setup.air_nm)):
		return "lesson %d (%s): runway %s, start %s" % [k, l2.setup.start, d.selected_runway, d.start]
	if p._where.text != LessonInfo.where(l2):
		return "the 'where' text follows too"
	return ""


func test_training_page_hides_the_diagram_when_the_airport_is_unknown() -> String:
	var d := AirportDiagram.new()
	d.read_only = true
	add_child(d)
	_nodes.append(d)
	LessonMap.apply(d, LessonMap.spec({"setup": {"airport": "NOPE", "runway": "27"}}, _fake()))
	if d.visible:
		return "no airport data: the diagram is hidden (the text remains)"
	LessonMap.apply(d, LessonMap.spec({"setup": {"airport": "VAXX", "runway": "27", "start": "runway"}}, _fake()))
	return "" if d.visible and d.selected_runway == "27" else "known airport: shown with runway 27 lit"
