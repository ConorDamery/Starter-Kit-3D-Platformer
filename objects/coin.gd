extends Node3D

@export var coin_value := 1

var time := 0.0

# Collecting coins

func _on_body_entered(body):
	if !is_multiplayer_authority() or !(body is Player):
		return
	
	Online.session.map_scene.collect_coin.rpc(coin_value)
	Audio.play.rpc("res://sounds/coin.ogg") # Play sound
	
	self.queue_free() # De-spawn
	$Particles.emitting = false # Stop emitting stars

# Rotating, animating up and down

func _process(delta):
	if !is_multiplayer_authority():
		return
	
	rotate_y(2 * delta) # Rotation
	position.y += (cos(time * 5) * 1) * delta # Sine movement
	
	time += delta
