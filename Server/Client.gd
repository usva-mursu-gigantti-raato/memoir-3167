extends Node2D
signal message_queue(msg)
signal initiate_connection

var websocket_url = "ws://localhost:9080"
enum connectionState {NONE, INITIALIZED, CONNECTED, AUTHENTICATED, DISCONNECTED, CLOSED}
# Our WebSocketClient instance.
var socket = WebSocketPeer.new()
var msgQueue:Array = []
var incomingMsg:Array = []
var connState = connectionState.NONE

func _ready():
	# Initiate connection to the given URL.
	message_queue.connect(_on_message_queue)
	initiate_connection.connect(_on_initiate_connection)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if connState == connectionState.CONNECTED:
		socket.poll()
		# get_ready_state() tells you what state the socket is in.
		var state = socket.get_ready_state()

		# `WebSocketPeer.STATE_OPEN` means the socket is connected and ready
		# to send and receive data.
		if state == WebSocketPeer.STATE_OPEN:
			flushMsgQueue()
			while socket.get_available_packet_count():
				var packet = socket.get_packet()
				if socket.was_string_packet():
					var packet_text = packet.get_string_from_utf8()
					print("< Got text data from server: %s" % packet_text)
					incomingMsg.append(packet_text)
				else:
					print("< Got binary data from server: %d bytes" % packet.size())

		# `WebSocketPeer.STATE_CLOSING` means the socket is closing.
		# It is important to keep polling for a clean close.
		elif state == WebSocketPeer.STATE_CLOSING:
			connState = connectionState.CLOSED
		# `WebSocketPeer.STATE_CLOSED` means the connection has fully closed.
		# It is now safe to stop polling.
		elif state == WebSocketPeer.STATE_CLOSED:
			# The code will be `-1` if the disconnection was not properly notified by the remote peer.
			var code = socket.get_close_code()
			print("WebSocket closed with code: %d. Clean: %s" % [code, code != -1])
			connState = connectionState.DISCONNECTED

func _on_message_queue(msg) -> void:
	print("Message to queue: ", msg)
	msgQueue.append(msg)
	pass

func flushMsgQueue():
	while !msgQueue.is_empty():
		socket.send_text(msgQueue.pop_front())

func _on_initiate_connection():
	connState = connectionState.INITIALIZED
	print("Connection initiated")
	var err = socket.connect_to_url(websocket_url)
	if err == OK:
		print("Connecting to %s..." % websocket_url)
		connState = connectionState.CONNECTED
	else:
		push_error("Unable to connect.")
		#set_process(false)
