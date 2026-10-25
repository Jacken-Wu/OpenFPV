extends SceneTree
var failed := 0
var checked := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func run() -> void:
	check(AboutMenu.license_status().ok, "complete project and engine license texts are available offline")
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._show_pause_menu()
	check(game.menu is PauseMenu, "pause menu opens")
	game.menu.about_requested.emit()
	check(game.menu is AboutMenu and game.paused, "about button opens credits while game remains paused")
	var panel: AboutMenu = game.menu
	check(panel.tabs.get_tab_count() == 2, "project and engine licenses have separate tabs")
	for index in 2:
		panel.tabs.current_tab = index
		await process_frame
		var text := panel.tabs.get_child(index) as TextEdit
		check(not text.editable and text.text.length() > 1000, "license tab contains readable full text " + str(index))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := ProjectSettings.globalize_path("res://../.local/test-results/about022")
			DirAccess.make_dir_recursive_absolute(path)
			check(root.get_texture().get_image().save_png(path.path_join("license%d.png" % index)) == OK, "license tab capture " + str(index))
	panel.closed.emit()
	check(game.menu is PauseMenu and game.paused, "back returns to pause menu without resuming flight")
	game.queue_free()
	await create_timer(0.2).timeout
	print("ABOUT_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
