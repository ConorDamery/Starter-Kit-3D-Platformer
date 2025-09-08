extends CanvasLayer

@export var coins_label : Label

func _ready() -> void:
	Game.coin_collected.connect(self._on_coin_collected)

func _on_coin_collected(coins):
	coins_label.text = str(coins)

func _on_quit_pressed() -> void:
	Online.end_game()
