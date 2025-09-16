extends CanvasLayer

@export var coins_label : Label

func _on_quit_pressed() -> void:
	Online.end_game()
