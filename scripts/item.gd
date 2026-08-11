class_name Item
extends Area2D
## フロアに一定確率で落ちているアイテム。取得すると一定時間だけ効果を発揮する。
## だれ防止・スピード感アップが狙い。

enum Kind { INVINCIBLE, JUMP_BOOST, ROCKET }

const DURATIONS := {
	Kind.INVINCIBLE: 10.0,
	Kind.JUMP_BOOST: 10.0,
	Kind.ROCKET: 3.0,
}
const COLORS := {
	Kind.INVINCIBLE: Color(1.0, 0.95, 0.3),
	Kind.JUMP_BOOST: Color(0.35, 1.0, 0.45),
	Kind.ROCKET: Color(1.0, 0.4, 0.2),
}
const LABELS := {
	Kind.INVINCIBLE: "無敵",
	Kind.JUMP_BOOST: "JUMP×3",
	Kind.ROCKET: "ロケット",
}

signal collected(kind: int)

var kind: int = Kind.INVINCIBLE

# プレイヤーの衝突レイヤー（main.gd/player.gd と揃える）
const LAYER_PLAYER := 8

func _ready() -> void:
	_build_visuals()
	collision_mask = LAYER_PLAYER
	body_entered.connect(_on_body_entered)

func _build_visuals() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(26, 26)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -15), Vector2(15, 0), Vector2(0, 15), Vector2(-15, 0)])
	poly.color = COLORS[kind]
	add_child(poly)

	var label := Label.new()
	label.text = LABELS[kind]
	label.add_theme_font_size_override("font_size", 10)
	label.position = Vector2(-20, -32)
	add_child(label)

	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(poly, "rotation", TAU, 2.0).as_relative()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.apply_item_effect(kind, DURATIONS[kind])
		collected.emit(kind)
		queue_free()
