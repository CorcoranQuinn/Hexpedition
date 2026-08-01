class_name OrientedVisual
extends Node2D
## Shows one of eight pre-built orientation layers for camera-relative art.


var _layers: Array[Node2D] = []
var _current_index: int = -1


func setup(layers: Array[Node2D]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_layers.clear()
	_current_index = -1
	for layer in layers:
		layer.visible = false
		add_child(layer)
		_layers.append(layer)


func set_orientation(index: int) -> void:
	if _layers.is_empty():
		return
	var clamped: int = posmod(index, _layers.size())
	if clamped == _current_index:
		return
	if _current_index >= 0 and _current_index < _layers.size():
		_layers[_current_index].visible = false
	_current_index = clamped
	_layers[_current_index].visible = true


func get_orientation() -> int:
	return _current_index
