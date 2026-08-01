class_name OrientedVisual
extends Node2D
## Shows one of eight pre-built orientation layers for camera-relative art.


var _layers: Array[Node2D] = []
var _current_index: int = -1
var _hover_highlight: bool = false
var _selection_outline: bool = false


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
	_apply_ring_states(_layers[_current_index])


func get_orientation() -> int:
	return _current_index


func set_hover_highlight(on: bool) -> void:
	_hover_highlight = on
	if _current_index >= 0 and _current_index < _layers.size():
		_apply_ring_states(_layers[_current_index])


func set_selection_outline(on: bool) -> void:
	_selection_outline = on
	if _current_index >= 0 and _current_index < _layers.size():
		_apply_ring_states(_layers[_current_index])


func _apply_ring_states(layer: Node2D) -> void:
	var figure: Node2D = layer.get_child(0) as Node2D if layer.get_child_count() > 0 else null
	if figure == null:
		return
	var hover_ring: CanvasItem = figure.get_node_or_null("HoverRing") as CanvasItem
	if hover_ring != null:
		hover_ring.visible = _hover_highlight
	var select_ring: CanvasItem = figure.get_node_or_null("SelectRing") as CanvasItem
	if select_ring != null:
		select_ring.visible = _selection_outline
