class_name TeamRegistry
extends RefCounted

static var TEAMS: Array[TeamDefinition] = []


static func _static_init() -> void:
	if not TEAMS.is_empty():
		return
	TEAMS = [
		_build_team(0, "Sentinels", Color(0.45, 0.62, 0.85), 6,
			"Defensive bulwark with healing leader and bastion tile.",
			"sentinel_leader", ["sentinel_follower", "sentinel_follower"], "sentinel_bastion"),
		_build_team(1, "Veilborne", Color(0.62, 0.48, 0.82), 5,
			"Mobile recon faction that reveals the board.",
			"veil_leader", ["veil_follower", "veil_follower"], "veil_mirror"),
		_build_team(2, "Emberclad", Color(0.88, 0.45, 0.28), 4,
			"Aggressive raiders with high burst damage.",
			"ember_leader", ["ember_follower", "ember_follower"], "ember_forge"),
		_build_team(3, "Swarmbound", Color(0.52, 0.78, 0.38), 5,
			"Summoner hive that spawns AI-controlled minions.",
			"swarm_leader", ["swarm_follower", "swarm_follower"], "swarm_hive"),
	]


static func _build_team(id: int, name: String, color: Color, max_rp: int,
		desc: String, leader: String, followers: Array, tile_id: String) -> TeamDefinition:
	var t := TeamDefinition.new()
	t.team_id = id
	t.team_name = name
	t.team_color = color
	t.max_resource_points = max_rp
	t.description = desc
	t.leader_type_id = leader
	t.follower_type_ids.clear()
	for follower_id in followers:
		t.follower_type_ids.append(String(follower_id))
	t.unique_tile_type_id = tile_id
	return t


static func get_team(team_id: int) -> TeamDefinition:
	_static_init()
	for t in TEAMS:
		if t.team_id == team_id:
			return t
	return TEAMS[0]


static func get_all_teams() -> Array[TeamDefinition]:
	_static_init()
	return TEAMS


static func pick_random_team_id(exclude: int = -1) -> int:
	_static_init()
	var candidates: Array[int] = []
	for team in TEAMS:
		if team.team_id != exclude:
			candidates.append(team.team_id)
	if candidates.is_empty():
		return TEAMS[0].team_id
	return candidates[randi() % candidates.size()]
