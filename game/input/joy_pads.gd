class_name JoyPads
extends RefCounted
## Connected pads, read once a frame. A Captain Pack is two devices, and every bound
## axis used to ask macOS for the name and guid again. The list is the same until the next frame.


static var _frame := -1
static var _list: Array = []


static func connected() -> Array:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_list = []
		for d in Input.get_connected_joypads():
			_list.append({"id": d, "name": Input.get_joy_name(d), "guid": Input.get_joy_guid(d)})
	return _list
