class_name RegionMap
extends Control

var drone_point := Vector3.ZERO
const MAP_SCALE := 0.65
const OFFSET := Vector2(245, 175)

func _ready() -> void:
	custom_minimum_size = Vector2(640, 345)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("162735"))
	for x in range(-4, 5):
		draw_line(Vector2(x * 64 * MAP_SCALE + OFFSET.x, 0), Vector2(x * 64 * MAP_SCALE + OFFSET.x, size.y), Color("2c414e"))
	for z in range(-4, 5):
		draw_line(Vector2(0, z * 64 * MAP_SCALE + OFFSET.y), Vector2(size.x, z * 64 * MAP_SCALE + OFFSET.y), Color("2c414e"))
	draw_rect(Rect2(OFFSET + Vector2(-256, -256) * MAP_SCALE, Vector2(256, 512) * MAP_SCALE), Color("875e3f90"))
	draw_rect(Rect2(OFFSET + Vector2(0, -256) * MAP_SCALE, Vector2(128, 512) * MAP_SCALE), Color("38776c90"))
	draw_circle(OFFSET + Vector2(112, -80) * MAP_SCALE, 11, Color("e3bf7c"))
	draw_circle(OFFSET + Vector2(-96, -96) * MAP_SCALE, 9, Color("7a94cf"))
	var player := OFFSET + Vector2(drone_point.x, drone_point.z) * MAP_SCALE
	draw_circle(player, 5, Color("f7f0d5"))
	draw_line(player, player + Vector2(0, -13), Color("f7f0d5"), 2)
