extends Node
## Captain Pack auto-detect (core/captain_detect.gd): the pure rules over fixtures, the stored answer, the shared
## profile code, the Controls page's reset and ask-again link. The prompt and the start-screen wiring are in
## tests/test_captain_offer.gd. Scratch paths only: never the real input_bindings.json or options.cfg.

const SCRATCH := "user://test_captain_detect_bindings.json"
const SIDESTICK := {"id": 0, "name": "Thrustmaster TCA Sidestick X Copilot", "guid": "g-stick"}
const QUADRANT := {"id": 1, "name": "Thrustmaster TCA Q-Eng 1&2", "guid": "g-quad"}
const XBOX := {"id": 2, "name": "Xbox Controller", "guid": "g-xbox"}
const LOGI := {"id": 3, "name": "Logitech Extreme 3D", "guid": "g-logi"}

var _keep := {}


func _begin() -> void:
	if _keep.is_empty():
		UserOptions.get_v("captain_pack")  # load the options once, then keep the in-memory value to restore
		_keep = {"state": UserOptions._v.get("captain_pack", ""), "override": Session.interactive_override}
	Session.interactive_override = 0  # UserOptions.set_v stays in memory
	CaptainDetect.bindings_path = SCRATCH
	_clean()


func _clean() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func teardown() -> void:
	if _keep.is_empty():
		return
	UserOptions._v["captain_pack"] = _keep.state
	Session.interactive_override = _keep.override
	CaptainDetect.pads_provider = Callable()
	CaptainDetect.bindings_path = InputBindings.PATH
	_keep = {}
	_clean()


func _generic() -> Dictionary:
	return InputBindings.defaults("joystick")  # what the owner's saved file holds: throttle on axis 3


func _captain() -> Dictionary:
	return InputBindings.defaults(InputProfiles.CAPTAIN_PACK)


func test_present_pads() -> String:
	var cases := [
		[[SIDESTICK, QUADRANT], true], [[SIDESTICK], true], [[QUADRANT], true], [[], false],
		[[XBOX, LOGI], false], [[XBOX, QUADRANT, LOGI], true], [[{"id": 0, "name": "THRUSTMASTER TCA SIDESTICK X", "guid": ""}], true],
		[[{"id": 0, "guid": ""}], false],
	]
	for c in cases:
		if CaptainDetect.present(c[0]) != c[1]:
			return "present(%s) should be %s" % [c[0].map(func(p): return p.get("name", "")), c[1]]
	return ""


func test_names_come_from_the_profile() -> String:
	var want: Array[String] = []
	for dev in InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK].values():
		want.append(str(dev.name).to_lower())
	if CaptainDetect.device_names() != want or want.size() != 2:
		return "device names %s, profile has %s" % [CaptainDetect.device_names(), want]
	var cp := _captain()
	var fp := CaptainDetect.fingerprint()
	for a in CaptainDetect.FINGERPRINT:
		if not fp.has(a) or fp[a] != cp[a].name:
			return "fingerprint %s should be the profile's %s" % [a, cp[a].name]
	return ""


func test_applied() -> String:
	if CaptainDetect.applied(_generic()) or CaptainDetect.applied(InputBindings.defaults("gamepad")) or CaptainDetect.applied({}):
		return "generic, gamepad and empty tables are not the Captain Pack"
	for os_name in ["Linux", "macOS", "Windows"]:
		if not CaptainDetect.applied(InputBindings.defaults(InputProfiles.CAPTAIN_PACK, os_name)):
			return "%s Captain Pack table should count as applied" % os_name
	var t := _captain()
	t.roll.deadzone = 0.2
	t.throttle.deadzone = 0.0
	t.throttle.expo = 0.5
	if not CaptainDetect.applied(t):
		return "a tweaked deadzone / curve is still the Captain Pack"
	for a in CaptainDetect.FINGERPRINT:
		var u := _captain()
		u[a].name = ""  # re-bound with Bind: tied to one pad now
		if CaptainDetect.applied(u):
			return "%s re-bound by hand should not count" % a
		u = _captain()
		u[a].axis = -1
		if CaptainDetect.applied(u):
			return "%s unbound should not count" % a
	return ""


func test_should_offer_truth_table() -> String:
	var pads_list := {"pack": [SIDESTICK, QUADRANT], "none": [XBOX, LOGI]}
	for pk in pads_list:
		for tk in ["generic", "captain"]:
			for st in ["", "applied", "declined"]:
				var table := _generic() if tk == "generic" else _captain()
				var want: bool = pk == "pack" and tk == "generic" and st == ""
				if CaptainDetect.should_offer(pads_list[pk], table, st) != want:
					return "pads=%s table=%s state='%s' should offer %s" % [pk, tk, st, want]
	return ""


func test_silent_upgrade_of_the_state() -> String:
	if CaptainDetect.resolve_state(_captain(), "") != "applied":
		return "an applied table with no answer becomes applied"
	if CaptainDetect.resolve_state(_captain(), "declined") != "declined" or CaptainDetect.resolve_state(_generic(), "") != "":
		return "answers and generic tables are left alone"
	_begin()
	UserOptions._v["captain_pack"] = ""
	CaptainDetect.pads_provider = func(): return [SIDESTICK, QUADRANT]
	InputBindings.save_to(_captain(), SCRATCH)
	if CaptainDetect.offer_now():
		return "no prompt when the saved table is already the Captain Pack"
	if CaptainDetect.state() != "applied":
		return "state should have become applied silently, is '%s'" % CaptainDetect.state()
	return ""


func test_offer_now_follows_pads_table_and_state() -> String:
	_begin()
	UserOptions._v["captain_pack"] = ""
	InputBindings.save_to(_generic(), SCRATCH)
	CaptainDetect.pads_provider = func(): return [XBOX]
	if CaptainDetect.offer_now():
		return "no Captain Pack pad, no offer"
	CaptainDetect.pads_provider = func(): return [SIDESTICK]
	if not CaptainDetect.offer_now():
		return "a sidestick with the generic table should offer"
	CaptainDetect.set_state("declined")
	if CaptainDetect.offer_now():
		return "declined must not offer"
	CaptainDetect.set_state("")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))  # no saved file = the generic defaults
	if not CaptainDetect.offer_now():
		return "no saved file should still offer"
	return ""


func test_apply_to_is_in_place_and_save_bump_bumps() -> String:
	_begin()
	var table := _generic()
	var ref: Dictionary = table.throttle
	var touched := InputProfiles.apply_to(table, InputProfiles.CAPTAIN_PACK)
	if table.throttle != ref or not CaptainDetect.applied(table) or not "flaps_lever" in touched:
		return "apply_to must rewrite the same dictionaries"
	if ref.get("lo") == null:
		return "the throttle dictionary should carry the lever calibration now"
	var rev := int(Props.get_v("input/bindings_rev", 0))
	if not InputBindings.save_bump(table, SCRATCH) or int(Props.get_v("input/bindings_rev", 0)) != rev + 1:
		return "save_bump should save and bump the revision"
	if not CaptainDetect.applied(InputBindings.load_from(SCRATCH)):
		return "the saved file should hold the profile"
	return ""


func test_apply_profile_writes_scratch_and_remembers() -> String:
	_begin()
	UserOptions._v["captain_pack"] = ""
	InputBindings.save_to(_generic(), SCRATCH)
	var rev := int(Props.get_v("input/bindings_rev", 0))
	if not CaptainDetect.apply_profile() or not CaptainDetect.applied(InputBindings.load_from(SCRATCH)):
		return "apply_profile should write the Captain Pack table to the scratch path"
	if CaptainDetect.state() != "applied" or int(Props.get_v("input/bindings_rev", 0)) != rev + 1:
		return "state '%s', revision %d (was %d)" % [CaptainDetect.state(), int(Props.get_v("input/bindings_rev", 0)), rev]
	return ""


func _page() -> HBoxContainer:
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.set("bindings_path", SCRATCH)
	add_child(page)
	return page


func test_controls_reset_buttons_and_the_state() -> String:
	_begin()
	UserOptions._v["captain_pack"] = "declined"
	var page := _page()
	page.call("_reset", "joystick")
	page.call("_reset", "gamepad")
	var err := ""
	if CaptainDetect.state() != "declined":
		err = "the generic resets must leave the state alone, it is '%s'" % CaptainDetect.state()
	elif CaptainDetect.applied(InputBindings.load_from(SCRATCH)):
		err = "joystick reset should save the generic table"
	if err == "":
		var rev := int(Props.get_v("input/bindings_rev", 0))
		page.call("_reset", InputProfiles.CAPTAIN_PACK)
		if CaptainDetect.state() != "applied":
			err = "the Captain Pack button should set applied, is '%s'" % CaptainDetect.state()
		elif not CaptainDetect.applied(InputBindings.load_from(SCRATCH)) or not CaptainDetect.applied(page.get("table")):
			err = "the Captain Pack button should save and show the profile"
		elif int(Props.get_v("input/bindings_rev", 0)) != rev + 1:
			err = "one reset = one revision bump"
	page.free()
	return err


func test_ask_again_link() -> String:
	_begin()
	var link := CaptainAskAgain.new()
	add_child(link)
	var err := ""
	var cases := [["declined", [SIDESTICK], true], ["declined", [XBOX], false], ["", [SIDESTICK], false], ["applied", [QUADRANT], false]]
	for c in cases:
		UserOptions._v["captain_pack"] = c[0]
		CaptainDetect.pads_provider = func(): return c[1]
		link.refresh()
		if link.visible != c[2]:
			err = "link with state '%s' and pads %s should be visible=%s" % [c[0], c[1].size(), c[2]]
			break
	if err == "":
		UserOptions._v["captain_pack"] = "declined"
		CaptainDetect.pads_provider = func(): return [SIDESTICK]
		link.refresh()
		link.pressed.emit()
		if CaptainDetect.state() != "" or not link.disabled:
			err = "pressing the link clears the answer (state '%s')" % CaptainDetect.state()
	link.free()
	return err
