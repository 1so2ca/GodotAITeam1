extends Node
## ゲーム内スコア（チャンネル登録者数）を管理するオートロード。
## 仕様: docs/spec/03_viewer_score_system.md

signal subscriber_changed(total: int, delta: int, reason: String)
signal game_won

const GOAL: int = 100_000_000

var subscriber_count: float = 0.0
var won: bool = false

func _ready() -> void:
	_setup_input_map()

func _setup_input_map() -> void:
	_bind_action("move_left", [KEY_A, KEY_LEFT], JOY_BUTTON_DPAD_LEFT)
	_bind_action("move_right", [KEY_D, KEY_RIGHT], JOY_BUTTON_DPAD_RIGHT)
	_bind_action("jump", [KEY_SPACE, KEY_W, KEY_UP], JOY_BUTTON_A)

func _bind_action(action_name: String, keys: Array, joy_button: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action_name, ev)
	var jev := InputEventJoypadButton.new()
	jev.button_index = joy_button
	InputMap.action_add_event(action_name, jev)

func add_subscribers(amount: float, reason: String = "") -> void:
	if won or amount <= 0.0:
		return
	subscriber_count += amount
	subscriber_changed.emit(int(subscriber_count), int(round(amount)), reason)
	_check_win()

func lose_subscribers(amount: float, reason: String = "") -> void:
	if won or amount <= 0.0:
		return
	var before := subscriber_count
	subscriber_count = max(subscriber_count - amount, 0.0)
	var actual_delta := subscriber_count - before
	if actual_delta != 0.0:
		subscriber_changed.emit(int(subscriber_count), int(round(actual_delta)), reason)

func _check_win() -> void:
	if not won and subscriber_count >= GOAL:
		won = true
		subscriber_count = GOAL
		game_won.emit()

func reset() -> void:
	subscriber_count = 0.0
	won = false
