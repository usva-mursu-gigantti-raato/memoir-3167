extends Node2D
@onready var msgNode = $TextEdit
@onready var responseNode = $TextEdit2

func _process(delta: float) -> void:
	if !Client.incomingMsg.is_empty():
		responseNode.text += Client.incomingMsg.pop_front() + "\n"

func _on_send() -> void:
	if !msgNode.text.is_empty():
		Client.message_queue.emit(msgNode.text)
