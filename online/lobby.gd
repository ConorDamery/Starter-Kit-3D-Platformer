extends Control

@export var player_name_le : LineEdit

@export var connect_panel : PanelContainer
@export var players_panel : PanelContainer

@export var lobby_name_le : LineEdit
@export var lobby_addr_le : LineEdit

@export var host_btn : Button
@export var join_btn : Button
@export var start_btn : Button
@export var add_btn : Button

@export var lobby_list : ItemList
@export var player_list : ItemList

@export var map_label : Label
@export var map_selection : OptionButton

@export var error_dialog : AcceptDialog

var _map_list: Dictionary
var _lobby_list: Dictionary
var _lobby_selected := -1

func _ready():
	call_deferred("_late_ready")

func _late_ready():
	player_name_le.text = Online.player_name
	player_name_le.editable = Online.online_backend != Online.OnlineBackend.STEAM
	player_name_le.text_changed.emit(player_name_le.text)
	
	Online.connection_failed.connect(self._on_connection_failed)
	Online.connection_succeded.connect(self._on_connection_succeded)
	Online.lobby_list_changed.connect(self._on_lobby_list_changed)
	Online.player_list_changed.connect(self._on_player_list_changed)
	Online.game_started.connect(self._on_game_started)
	Online.game_ended.connect(self._on_game_ended)
	Online.game_error.connect(self._on_game_error)
	Online.game_log.connect(self._on_game_log)
	
	lobby_list.item_selected.connect(self._on_lobby_selected)
	
	var idx = 0
	for map_name in Online.session.config.game_maps.keys():
		map_selection.add_item(map_name)
		_map_list[idx] = map_name
		idx += 1
	
	map_selection.item_selected.emit(0)

func _on_connection_failed():
	connect_panel.show()
	players_panel.hide()
	host_btn.disabled = false

func _on_connection_succeded():
	connect_panel.hide()
	players_panel.show()

func _on_lobby_list_changed():
	_lobby_selected = -1
	join_btn.disabled = true
	
	lobby_list.clear()
	lobby_list.clear()
	for lby_info in Online.lobbies.values():
		var idx = lobby_list.add_item("%s [%d/%d]" % [lby_info["lobby_name"], lby_info["lobby_num_players"], lby_info["lobby_max_players"]])
		_lobby_list[idx] = lby_info["id"]

func _on_player_list_changed():
	player_list.clear()
	for player_name in Online.players.values():
		player_list.add_item(player_name if player_name != Online.player_name else player_name + " (you)")

func _on_game_started():
	self.hide()

func _on_game_ended():
	Online.request_lobbies()
	
	connect_panel.show()
	players_panel.hide()
	start_btn.disabled = true
	self.show()

func _on_game_error(what: String):
	error_dialog.dialog_text = what
	error_dialog.popup_centered()
	host_btn.disabled = false

func _on_game_log(what: String):
	print("GAME LOG: " + what)

func _on_lobby_selected(index: int):
	_lobby_selected = _lobby_list[index]
	join_btn.disabled = _lobby_selected < 0

func _on_player_name_changed(new_text: String) -> void:
	lobby_name_le.text = new_text + "'s Lobby"
	lobby_name_le.text_changed.emit(lobby_name_le.text)

func _on_lobby_name_changed(new_text: String) -> void:
	host_btn.disabled = new_text.is_empty()

func _on_lobby_addr_changed(new_text: String) -> void:
	add_btn.disabled = new_text.is_empty()

func _on_host_pressed() -> void:
	Online.create_host(player_name_le.text, lobby_name_le.text)
	
	connect_panel.hide()
	players_panel.show()
	map_label.show()
	map_selection.show()
	
	start_btn.disabled = false

func _on_join_pressed() -> void:
	if _lobby_selected < 0:
		return
	
	# Use the selected lobby info
	Online.create_client(player_name_le.text, _lobby_selected)
	
	connect_panel.hide()
	players_panel.show()
	map_label.hide()
	map_selection.hide()

func _on_start_pressed() -> void:
	Online.start_game()

func _on_quit_pressed() -> void:
	Online.end_game()

func _on_refresh_pressed() -> void:
	Online.request_lobbies()

func _on_add_lobby_pressed() -> void:
	var parts = lobby_addr_le.text.split(":")
	if parts.size() != 2:
		return
	
	var lby_addr = parts[0]
	var lby_port = int(parts[1])
	var lby_id = multiplayer.multiplayer_peer.generate_unique_id()
	Online.lan_add_lobby(lby_id, lby_addr, lby_port, "Temp Lobby", 0, 0)
	Online.lobby_list_changed.emit()

func _on_map_selected(index: int) -> void:
	Online.lobby_map = _map_list[index]
