extends ZinoTest

func test_centerline_passes_through_control_points() -> void:
	var road: Dictionary = ZinoEntities.circuit_road()["road"]
	var c := ZinoRoadBuilder.sample_centerline(road)
	var pts: PackedVector3Array = c.points
	var samples: int = road["samplesPerSegment"]
	check_eq(pts.size(), road["points"].size() * samples, "closed loop sample count")
	for i in road["points"].size():
		check(pts[i * samples].distance_to(ZinoFormat.v3(road["points"][i])) < 0.001, "passes control point %d" % i)

func test_circuit_length_is_plausible() -> void:
	var road: Dictionary = ZinoEntities.circuit_road()["road"]
	var length := ZinoRoadBuilder.centerline_length(road)
	# Straights 2*(140-44) + 2*(70-44) = 244 m, four quarter circles of r=22 = 138 m -> about 382 m.
	check_near(length, 382.0, 15.0, "circuit length")

func test_open_road_builds_mesh_and_collision() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var road: Dictionary = ZinoEntities.road([Vector3(0, 0, 0), Vector3(0, 0, -50), Vector3(20, 0, -100)], "R", 10.0, false)["road"]
	var body := ZinoRoadBuilder.build(root, road)
	var mi := root.get_node("RoadMesh") as MeshInstance3D
	check(mi != null and mi.mesh.get_surface_count() >= 2, "road mesh has slab and markings")
	check(body.get_child_count() == 1, "collision shape created")
	await tree.physics_frame
	await tree.physics_frame
	# A downward ray onto the road centre must hit the road top surface.
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 5, -20), Vector3(0, -5, -20))
	var hit := space.intersect_ray(q)
	check(not hit.is_empty(), "ray hits road")
	if not hit.is_empty():
		check_near(hit.position.y, ZinoRoadBuilder.SURFACE_LIFT, 0.02, "road top height")
		check(hit.normal.y > 0.9, "hit the top face from above (normal %s)" % str(hit.normal))
	root.free()
