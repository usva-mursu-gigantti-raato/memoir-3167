extends Control
@onready var joinBtn = $Button
var server = preload("res://Server/server.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	if "--server" in OS.get_cmdline_user_args():
		var serverInstance = server.instantiate()
		print("adding server node")
		add_child(serverInstance)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _on_button_pressed() -> void:
	Client.initiate_connection.emit()
	get_tree().change_scene_to_file("res://UI/test.tscn")
	set_process(false)
