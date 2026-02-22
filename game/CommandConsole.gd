extends Control
class_name CommandConsole

# Optional component if you want a reusable console later.
# Not used by Game.tscn currently.

signal line_submitted(line: String)

@export var output_richtext_path: NodePath
@export var input_line_path: NodePath

var _output: RichTextLabel
var _input: LineEdit

func _ready() -> void:
	_output = _get_richtext(output_richtext_path, "Output")
	_input = _get_line_edit(input_line_path, "CommandInput")
	if _input != null:
		_input.text_submitted.connect(_on_submit)

func log_line(s: String) -> void:
	if _output != null:
		_output.append_text(s + "\n")
	print(s)

func _on_submit(text: String) -> void:
	var line: String = text.strip_edges()
	if _input != null:
		_input.text = ""
	if line.is_empty():
		return
	line_submitted.emit(line)

func _get_richtext(path: NodePath, fallback_name: String) -> RichTextLabel:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var v: RichTextLabel = node as RichTextLabel
	if v == null:
		push_error("CommandConsole: Missing RichTextLabel '%s'." % fallback_name)
	return v

func _get_line_edit(path: NodePath, fallback_name: String) -> LineEdit:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var v: LineEdit = node as LineEdit
	if v == null:
		push_error("CommandConsole: Missing LineEdit '%s'." % fallback_name)
	return v
