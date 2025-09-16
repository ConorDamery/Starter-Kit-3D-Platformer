extends Resource
class_name SessionConfig

@export_subgroup("Properties")
@export var maps: Dictionary[String, MapConfig]

@export_subgroup("Auto Spawn List")
@export var player_spawn_list: Array[Resource]
@export var dynamic_spawn_list: Array[Resource]
