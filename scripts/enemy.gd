class_name Enemy
extends CharacterBody2D
## 塔に配置される敵。プレイヤーに踏まれると倒れ、横や下から触れるとダメージを与える。

const SPEED := 70.0
const GRAVITY := 1400.0

var patrol_half_width := 80.0
var start_x := 0.0
var direction := 1

func _ready() -> void:
	start_x = global_position.x
	_build_visuals()
	add_to_group("enemies")

func _build_visuals() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(30, 26)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-15, -13), Vector2(15, -13), Vector2(15, 13), Vector2(-15, 13)])
	poly.color = Color(0.85, 0.25, 0.35)
	add_child(poly)

	var eye_l := Polygon2D.new()
	eye_l.polygon = PackedVector2Array([Vector2(-8, -6), Vector2(-2, -6), Vector2(-2, 0), Vector2(-8, 0)])
	eye_l.color = Color(1, 1, 1)
	add_child(eye_l)

	var eye_r := Polygon2D.new()
	eye_r.polygon = PackedVector2Array([Vector2(2, -6), Vector2(8, -6), Vector2(8, 0), Vector2(2, 0)])
	eye_r.color = Color(1, 1, 1)
	add_child(eye_r)

func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	velocity.x = direction * SPEED
	move_and_slide()
	if global_position.x > start_x + patrol_half_width:
		direction = -1
	elif global_position.x < start_x - patrol_half_width:
		direction = 1

func stomp() -> void:
	queue_free()
