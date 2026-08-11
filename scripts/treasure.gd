class_name Treasure
extends Area2D
## 金銀財宝の入手演出。取得すると登録者数が一気に増加する（演出上のスコア加算）。
## 仕様: docs/spec/01_concept.md, 03_viewer_score_system.md

signal collected(amount: float)

var amount := 3_000_000.0

# プレイヤーの衝突レイヤー（main.gd/player.gd と揃える）
const LAYER_PLAYER := 8

func _ready() -> void:
	_build_visuals()
	collision_mask = LAYER_PLAYER
	body_entered.connect(_on_body_entered)

func _build_visuals() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(26, 22)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-13, -11), Vector2(13, -11), Vector2(13, 11), Vector2(-13, 11)])
	poly.color = Color(0.95, 0.8, 0.15)
	add_child(poly)

	var lid := Polygon2D.new()
	lid.polygon = PackedVector2Array([Vector2(-13, -11), Vector2(13, -11), Vector2(10, -18), Vector2(-10, -18)])
	lid.color = Color(0.75, 0.55, 0.1)
	add_child(lid)

	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(self, "position:y", -6.0, 0.8).as_relative()
	tw.tween_property(self, "position:y", 6.0, 0.8).as_relative()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		GameState.add_subscribers(amount, "財宝入手")
		collected.emit(amount)
		queue_free()
