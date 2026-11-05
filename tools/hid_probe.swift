// Raw HID capture for joysticks, throttles and gamepads on macOS (IOKit), independent of Godot.
// Used to calibrate the Thrustmaster TCA Captain Pack (game/core/input_profiles.gd) when Godot cannot list the pads.
//
//   swiftc -O tools/hid_probe.swift -o /tmp/hid_probe   (once)
//   /tmp/hid_probe /tmp/pads.log                        guided: names each control to move and waits for Enter
//   /tmp/hid_probe /tmp/pads.log 420 --free             no guide: logs for 420 s, type a marker + Enter per control
//
// Guided mode: every step prints what to do, waits for Enter, logs MARK START, and after the next Enter
// logs MARK END, so each log line belongs to one control. Lines (tab separated):
//   DEV   <index> <product> vendor=<id> product=<id>
//   ELEM  <dev> <order> axis|button|hat page=<p> usage=<u> min=<a> max=<b>   elements in descriptor order
//   VAL   <t> <dev> <order> <kind> usage=<u> raw=<v> norm=<-1..1>            every change
//   MARK  <t> <text>
// "order" counts the elements of the same kind in descriptor order of that device. Godot (SDL3) numbers
// buttons by usage number - 1 but axes by ascending HID usage, which differs from descriptor order on the
// TCA quadrant: its order 0,1,2,3 is Godot axis 0,1,2,5 (check with tests/probe_pads.gd). The START / END
// markers of the guided mode can be off by one step against the real movements: read the log by content.
import Foundation
import IOKit.hid

let logPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/pads.log"
let free = CommandLine.arguments.contains("--free")
let seconds = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 420 : 420
FileManager.default.createFile(atPath: logPath, contents: nil)
let out = FileHandle(forWritingAtPath: logPath)!
let start = Date()
let lock = NSLock()
func log(_ s: String) {
	lock.lock(); defer { lock.unlock() }
	out.write((s + "\n").data(using: .utf8)!)
	print(s)
	fflush(stdout)
}
func now() -> String { String(format: "%.2f", Date().timeIntervalSince(start)) }

struct Elem { var kind: String; var order: Int; var page: Int; var usage: Int; var min: Int; var max: Int }
var devices: [IOHIDDevice] = []
var elems: [[IOHIDElementCookie: Elem]] = []
var last: [String: Int] = [:]

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let match: [[String: Any]] = [4, 5, 8].map { [kIOHIDDeviceUsagePageKey as String: 1, kIOHIDDeviceUsageKey as String: $0] }
IOHIDManagerSetDeviceMatchingMultiple(mgr, match as CFArray)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { print("cannot open HID manager"); exit(1) }

let valueCallback: IOHIDValueCallback = { _, _, _, value in
	let el = IOHIDValueGetElement(value)
	let dev = IOHIDElementGetDevice(el)
	guard let di = devices.firstIndex(where: { $0 == dev }), let e = elems[di][IOHIDElementGetCookie(el)] else { return }
	let raw = IOHIDValueGetIntegerValue(value)
	let key = "\(di):\(e.kind):\(e.order)"
	if last[key] == raw { return }
	last[key] = raw
	let span = Double(e.max - e.min)
	let norm = span > 0 ? (Double(raw - e.min) / span) * 2.0 - 1.0 : 0.0
	log("VAL\t\(now())\t\(di)\t\(e.order)\t\(e.kind)\tusage=\(e.usage)\traw=\(raw)\tnorm=\(String(format: "%.3f", norm))")
}

let devs = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
for d in devs.sorted(by: { (IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String ?? "") < (IOHIDDeviceGetProperty($1, kIOHIDProductKey as CFString) as? String ?? "") }) {
	let di = devices.count
	devices.append(d)
	let name = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "?"
	let vid = IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? Int ?? 0
	let pid = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0
	log("DEV\t\(di)\t\(name)\tvendor=\(vid)\tproduct=\(pid)")
	var map: [IOHIDElementCookie: Elem] = [:]
	var counts: [String: Int] = [:]
	let all = (IOHIDDeviceCopyMatchingElements(d, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
	for el in all {
		let type = IOHIDElementGetType(el)
		guard type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Axis || type == kIOHIDElementTypeInput_Button else { continue }
		let page = Int(IOHIDElementGetUsagePage(el)), usage = Int(IOHIDElementGetUsage(el))
		var kind = ""
		if page == 9 { kind = "button" } else if page == 1 && usage == 0x39 { kind = "hat" } else if page == 1 && usage >= 0x30 && usage <= 0x38 { kind = "axis" } else { continue }
		let order = counts[kind, default: 0]
		counts[kind] = order + 1
		let mn = IOHIDElementGetLogicalMin(el), mx = IOHIDElementGetLogicalMax(el)
		map[IOHIDElementGetCookie(el)] = Elem(kind: kind, order: order, page: page, usage: usage, min: mn, max: mx)
		log("ELEM\t\(di)\t\(order)\t\(kind)\tpage=\(page)\tusage=\(usage)\tmin=\(mn)\tmax=\(mx)")
	}
	elems.append(map)
}
IOHIDManagerRegisterInputValueCallback(mgr, valueCallback, nil)
if devices.isEmpty { log("NO HID JOYSTICKS FOUND") }

let steps: [(String, String, Int)] = [
	("THRUST1_CLICKS", "Thrust lever 1 (left) ONLY: from IDLE push forward to the FIRST click (CLB) and HOLD 5 s, then to the SECOND click (FLX/MCT) and HOLD 5 s, then to TOGA and HOLD 5 s, then back to IDLE and HOLD 5 s.", 40),
	("THRUST2_CLICKS", "Thrust lever 2 (right) ONLY: the same: CLB hold 5 s, FLX/MCT hold 5 s, TOGA hold 5 s, back to IDLE hold 5 s.", 40),
	("SPEEDBRAKE_FOUR", "Speed brake lever: fully retracted (hold 5 s), then position 2 (hold 5 s), position 3 (hold 5 s), position 4 fully deployed (hold 5 s), then back to retracted (hold 5 s).", 45),
]
if free {
	FileHandle.standardInput.readabilityHandler = { h in
		if let s = String(data: h.availableData, encoding: .utf8) {
			for line in s.split(separator: "\n") { log("MARK\t\(now())\t\(line)") }
		}
	}
	Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
		if Date().timeIntervalSince(start) >= seconds { log("DONE"); exit(0) }
	}
} else {
	Thread.detachNewThread {
		print("\nGuided capture: \(steps.count) steps. For each: read it, press Enter, then GO: do it while the countdown runs. Keep other controls still.\n")
		for (i, step) in steps.enumerated() {
			print("Step \(i + 1)/\(steps.count)  \(step.1)\n  Press Enter, then start moving (\(step.2) s)")
			_ = readLine()
			log("MARK\t\(now())\tSTART \(step.0)")
			print("  GO")
			var left = step.2
			while left > 0 {
				Thread.sleep(forTimeInterval: 5)
				left -= 5
				if left > 0 { print("  ... \(left) s left") }
			}
			log("MARK\t\(now())\tEND \(step.0)")
			print("  STOP\n")
		}
		log("DONE")
		exit(0)
	}
}
RunLoop.main.run()
