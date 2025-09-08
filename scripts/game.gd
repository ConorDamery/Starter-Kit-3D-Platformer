extends Node

var coins = 0

signal coin_collected

func reset():
	coins = 0

@rpc("any_peer", "call_local")
func collect_coin(count: int):
	coins += count
	coin_collected.emit(coins)
