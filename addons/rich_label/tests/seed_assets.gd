extends SceneTree
## Creates placeholder assets used by smoke_test.gd. Run before importing:
##   godot --headless --path . -s res://addons/rich_label/tests/seed_assets.gd

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/images")
	DirAccess.make_dir_recursive_absolute("res://assets/scenes")

	var png := "res://assets/images/test_icon.png"
	if not FileAccess.file_exists(png):
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.9, 0.4, 0.9))
		img.save_png(png)
		print("seeded ", png)

	var scn := "res://assets/scenes/test_box.tscn"
	if not FileAccess.file_exists(scn):
		var f := FileAccess.open(scn, FileAccess.WRITE)
		f.store_string('[gd_scene format=3]\n\n[node name="TestBox" type="Control"]\ncustom_minimum_size = Vector2(48, 24)\n')
		f.close()
		print("seeded ", scn)

	quit(0)
