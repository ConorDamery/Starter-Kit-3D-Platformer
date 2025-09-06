extends Area3D

var time := 0.0
var grabbed := false

# Collecting coins

func _on_body_entered(body):
	if not is_multiplayer_authority():
		return
	
	if body.has_method("collect_coin") and !grabbed:
		body.collect_coin()
		Audio.play.rpc("res://sounds/coin.ogg") # Play sound
		
		self.queue_free() # De-spawn
		$Particles.emitting = false # Stop emitting stars
		
		grabbed = true

# Rotating, animating up and down

func _process(delta):
	if not is_multiplayer_authority():
		return
	
	rotate_y(2 * delta) # Rotation
	position.y += (cos(time * 5) * 1) * delta # Sine movement
	
	time += delta
