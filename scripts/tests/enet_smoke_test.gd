extends SceneTree

const PORT := 17999


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var is_client: bool = "--client" in OS.get_cmdline_user_args()
	var peer := ENetMultiplayerPeer.new()
	var err: Error
	if is_client:
		err = peer.create_client("127.0.0.1", PORT)
		print("client create err=", err)
	else:
		err = peer.create_server(PORT, 1)
		print("server create err=", err)
	var mp: MultiplayerAPI = get_multiplayer()
	mp.multiplayer_peer = peer

	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var status: int = peer.get_connection_status()
		if is_client:
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				print("CLIENT CONNECTED")
				quit(0)
				return
		else:
			if mp.get_peers().size() > 0:
				print("HOST PEER CONNECTED ", mp.get_peers())
				quit(0)
				return
		await process_frame
	print("TIMEOUT is_client=", is_client, " status=", peer.get_connection_status())
	quit(1)
