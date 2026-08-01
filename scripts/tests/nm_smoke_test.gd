extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var is_client: bool = "--client" in OS.get_cmdline_user_args()
	var nm: Node = root.get_node("/root/NetworkManager")
	var connected: bool = false
	if is_client:
		nm.connection_succeeded.connect(func() -> void: connected = true)
		nm.connection_failed.connect(func() -> void: print("client connection_failed"))
		var err: Error = nm.join_game("127.0.0.1", 17998)
		print("client join err=", err)
	else:
		nm.peer_connected.connect(func(id: int) -> void:
			print("host saw peer ", id)
			connected = true
		)
		var err: Error = nm.host_game(17998)
		print("host err=", err)

	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if connected:
			print("SUCCESS is_client=", is_client, " online=", nm.is_connected_online())
			quit(0)
			return
		if is_client and nm.peer and nm.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			print("CLIENT STATUS CONNECTED")
			quit(0)
			return
		await process_frame
	print("TIMEOUT is_client=", is_client, " online=", nm.is_connected_online())
	quit(1)
