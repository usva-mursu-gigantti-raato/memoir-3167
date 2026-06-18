extends Node

# The port we will listen to.
const PORT = 9080

# Our TCP Server instance.
var _tcp_server = TCPServer.new()

# Our connected peers list.
var _peers: Dictionary[int, WebSocketPeer] = {}

var last_peer_id := 1
var broadcastMsg:Array = []

func _ready():
	# Start listening on the given port.
	var err = _tcp_server.listen(PORT)
	if err == OK:
		print("[Server] server started.")
	else:
		push_error("[Server] unable to start server.")
		set_process(false)

func _physics_process(delta: float) -> void:
	while _tcp_server.is_connection_available():
		last_peer_id += 1
		print("[Server] + Peer %d connected." % last_peer_id)
		var ws = WebSocketPeer.new()
		ws.accept_stream(_tcp_server.take_connection())
		_peers[last_peer_id] = ws
	flushBroadcastMsg()
	# Iterate over all connected peers using "keys()" so we can erase in the loop
	for peer_id in _peers.keys():
		var peer = _peers[peer_id]

		peer.poll()

		var peer_state = peer.get_ready_state()
		if peer_state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count():
				var packet = peer.get_packet()
				if peer.was_string_packet():
					var packet_text = packet.get_string_from_utf8()
					print("[Server] < Got text data from peer %d: %s ... echoing" % [peer_id, packet_text])
					# Echo the packet back.
					broadcastMsg.append("peer-" + str(peer_id) + ": " + packet_text)
				else:
					print("[Server] < Got binary data from peer %d: %d ... echoing" % [peer_id, packet.size()])
					# Echo the packet back.
					peer.send(packet)
		elif peer_state == WebSocketPeer.STATE_CLOSED:
			# Remove the disconnected peer.
			_peers.erase(peer_id)
			var code = peer.get_close_code()
			var reason = peer.get_close_reason()
			print("[Server] - Peer %s closed with code: %d, reason %s. Clean: %s" % [peer_id, code, reason, code != -1])

func flushBroadcastMsg():
	if broadcastMsg.is_empty():
		return
	while !broadcastMsg.is_empty():
		var msg = broadcastMsg.pop_front()
		for peer_id in _peers.keys():
			var peer = _peers[peer_id]
			peer.send_text(msg)
