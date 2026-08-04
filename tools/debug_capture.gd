class_name DebugCapture
extends Node

## Takes a series of screenshots while the game runs and prints the model state
## from the SAME frame.
##
## The pairing is the point: a picture alone cannot tell you whether a wrong
## position came from the logic or from the drawing. Numbers alone cannot tell
## you the sprite is drawn behind the floor. Together they pin it down.

signal finished

@export var output_dir: String = ""
@export var interval: float = 0.5
@export var shot_count: int = 4
## Wait before the first shot. Needed to catch anything that only happens once
## the situation develops - a melee swing cannot be photographed while the
## enemies are still walking in from the rim.
@export var start_delay: float = 0.0

## Returns a one-line description of the world state, printed alongside each
## shot. Set by whoever owns the scene.
var state_provider: Callable

func start() -> void:
	_run()

func _run() -> void:
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout

	for index in shot_count:
		await get_tree().create_timer(interval).timeout
		# The viewport holds no image until a frame has actually been drawn.
		await RenderingServer.frame_post_draw

		var image := get_viewport().get_texture().get_image()
		var path := output_dir.path_join("frame_%02d.png" % index)
		var error := image.save_png(path)

		var state := ""
		if state_provider.is_valid():
			state = str(state_provider.call())
		print("[capture %02d] t=%.1fs  png=%s  %s" % [index, (index + 1) * interval, error, state])

	finished.emit()
