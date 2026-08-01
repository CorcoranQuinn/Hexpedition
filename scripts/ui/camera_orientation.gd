class_name CameraOrientation
extends RefCounted
## Maps camera yaw to one of eight billboard orientations:
## even indices (0,2,4,6) = settled cardinal views; odd = mid-rotation blends.

const ORIENTATION_COUNT: int = 8
const CARDINAL_STEP: float = PI * 0.5
const MID_STEP: float = PI * 0.25


static func get_orientation_index(yaw: float, is_rotating: bool) -> int:
	var angle: float = fposmod(yaw, TAU)
	if is_rotating:
		var mid_idx: int = int(round(angle / MID_STEP)) % ORIENTATION_COUNT
		if mid_idx % 2 == 0:
			mid_idx = (mid_idx + 1) % ORIENTATION_COUNT
		return mid_idx
	var cardinal_idx: int = int(round(angle / CARDINAL_STEP)) * 2
	return cardinal_idx % ORIENTATION_COUNT


static func orientation_yaw(index: int) -> float:
	return float(index) * MID_STEP


static func apply_orientation_pose(node: Node2D, orientation: int) -> void:
	var yaw: float = orientation_yaw(orientation)
	var facing: float = cos(yaw)
	var side: float = sin(yaw)
	node.scale = Vector2(0.78 + 0.22 * absf(facing), 0.86 + 0.14 * absf(side))
	node.rotation = side * 0.16
	node.position.x = side * 3.0
	if orientation % 2 == 1:
		node.modulate = Color(1.0, 1.0, 1.0, 0.94)
