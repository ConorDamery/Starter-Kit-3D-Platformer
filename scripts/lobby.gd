extends Control

@export var player_name_le : LineEdit

@export var connect_panel : PanelContainer
@export var players_panel : PanelContainer

@export var lobby_name_le : LineEdit
@export var lobby_addr_le : LineEdit

@export var enet_host_btn : Button
@export var enet_join_btn : Button
@export var enet_start_btn : Button

@export var enet_lobby_list : ItemList
@export var enet_player_list : ItemList

@export var error_dialog : AcceptDialog

var lobby_list: Dictionary
var selected_lobby_index := -1

func _ready() -> void:
	
	Online.connection_failed.connect(self._on_connection_failed)
	Online.connection_succeded.connect(self._on_connection_succeded)
	Online.lobby_list_changed.connect(self._on_lobby_list_changed)
	Online.player_list_changed.connect(self._on_player_list_changed)
	Online.game_started.connect(self._on_game_started)
	Online.game_ended.connect(self._on_game_ended)
	Online.game_error.connect(self._on_game_error)
	Online.game_log.connect(self._on_game_log)
	
	enet_lobby_list.item_selected.connect(self._on_lobby_selected)

func _on_connection_failed():
	connect_panel.show()
	players_panel.hide()
	enet_host_btn.disabled = false

func _on_connection_succeded():
	connect_panel.hide()
	players_panel.show()

func _on_lobby_list_changed():
	selected_lobby_index = -1
	enet_join_btn.disabled = true
	
	lobby_list.clear()
	enet_lobby_list.clear()
	for lby_info in Online.lobbies.values():
		var idx = enet_lobby_list.add_item("%s [%d/%d]" % [lby_info["lobby_name"], lby_info["lobby_num_players"], lby_info["lobby_max_players"]])
		lobby_list[idx] = lby_info

func _on_player_list_changed():
	enet_player_list.clear()
	for player_name in Online.players.values():
		enet_player_list.add_item(player_name if player_name != Online.player_name else player_name + " (you)")

func _on_game_started():
	get_tree().get_root().get_node("Lobby").hide()

func _on_game_ended():
	Online.request_lobbies()
	
	connect_panel.show()
	players_panel.hide()
	get_tree().get_root().get_node("Lobby").show()

func _on_game_error(what: String):
	error_dialog.dialog_text = what
	error_dialog.popup_centered()
	enet_host_btn.disabled = false

func _on_game_log(what: String):
	print("GAME LOG: " + what)

func _on_lobby_selected(index: int):
	selected_lobby_index = index
	enet_join_btn.disabled = selected_lobby_index < 0

func _on_enet_host_pressed() -> void:
	Online.create_enet_host(player_name_le.text, lobby_name_le.text)
	connect_panel.hide()
	players_panel.show()
	enet_start_btn.disabled = false

func _on_enet_join_pressed() -> void:
	if selected_lobby_index < 0:
		# We use the explicit lobby address
		var parts = lobby_addr_le.text.split(":")
		var addr = parts[0]
		var port = int(parts[1])
		Online.create_enet_client(player_name_le.text, addr, port)
		
	else:
		# Use the selected lobby info
		var lby_info = lobby_list[selected_lobby_index]
		Online.create_enet_client(player_name_le.text, lby_info["addr"], lby_info["port"])
	
	connect_panel.hide()
	players_panel.show()

func _on_enet_start_pressed() -> void:
	Online.start_game()

func _on_enet_quit_pressed() -> void:
	Online.end_game()

func _on_refresh_pressed() -> void:
	Online.request_lobbies()

func _on_lobby_name_changed(new_text: String) -> void:
	enet_host_btn.disabled = new_text.is_empty()

func _on_lobby_addr_changed(new_text: String) -> void:
	enet_join_btn.disabled = new_text.is_empty()
	selected_lobby_index = -1
	enet_lobby_list.deselect_all()
