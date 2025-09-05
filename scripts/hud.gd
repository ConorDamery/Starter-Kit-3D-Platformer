extends CanvasLayer

func _on_coin_collected(coins):
	$Coins.text = str(coins)

func _on_quit_pressed() -> void:
	Online.end_game()
