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


## Foreshorten upright billboards toward/away from camera without rotating them.
static func apply_orientation_pose(node: Node2D, orientation: int) -> void:
	var yaw: float = orientation_yaw(orientation)
	var facing: float = absf(cos(yaw))
	var width: float = lerpf(0.58, 1.0, facing)
	node.scale = Vector2(width, lerpf(0.94, 1.0, facing))
	node.rotation = 0.0
	node.position = Vector2.ZERO
	if cos(yaw) < -0.01:
		node.scale.x = -absf(node.scale.x)
	if orientation % 2 == 1:
		node.modulate = Color(0.97, 0.97, 0.99, 1.0)
	else:
		node.modulate = Color.WHITE
