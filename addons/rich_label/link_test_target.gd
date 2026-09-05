extends Node

func _rich_label_hovered(label: Control):
	prints("Target hovered!", label)

func _rich_label_unhovered(label: Control):
	prints("Target unhovered!", label)

func _rich_label_clicked(label: Control):
	prints("Target clicked!", label)

func get_tooltip_text():
	return "Hovering over link..."
