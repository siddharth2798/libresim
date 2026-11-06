extends Node
## Control-tower cabs (world/control_tower.gd): one cab per cluster of tower points,
## roof level with the aerodrome beacon.


func test_one_cab_per_cluster_roof_level_with_the_beacon() -> String:
	if ControlTower.CAB_ROOF != AirportBeacon.MAST:
		return "cab roof %.1f m, beacon mast %.1f m" % [ControlTower.CAB_ROOF, AirportBeacon.MAST]
	var root := Node3D.new()
	add_child(root)
	var solids := OpsSolids.new("test_tower")
	var towers := [{"x": 10.0, "y": 20.0}, {"x": 12.0, "y": 22.0}, {"x": 80.0, "y": 20.0}]
	ControlTower.place_all(root, solids, towers, func(_x, _y): return 5.0)
	var parts := 0
	var roofs := 0
	for c in root.get_children():
		if not c is MeshInstance3D:
			continue
		parts += 1
		var cyl := (c as MeshInstance3D).mesh as CylinderMesh
		if cyl == null or absf(cyl.height - 0.7) > 0.01:
			continue
		roofs += 1
		var top: float = (c as MeshInstance3D).position.y + cyl.height * 0.5
		if absf(top - (5.0 + ControlTower.CAB_ROOF)) > 0.02:
			ObstacleRegistry.remove_group("test_tower")
			root.queue_free()
			return "cab roof at %.2f m, want %.2f m" % [top, 5.0 + ControlTower.CAB_ROOF]
	ObstacleRegistry.remove_group("test_tower")
	root.queue_free()
	if parts != 8 or roofs != 2:
		return "%d parts and %d roofs, want 8 and 2 (two towers, the close pair merged)" % [parts, roofs]
	return ""
