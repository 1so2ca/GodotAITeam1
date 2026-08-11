class_name Enemy
extends CharacterBody2D
## 塔に配置される敵。プレイヤーに踏まれると倒れ、横や下から触れるとダメージを与える。

const SPEED := 70.0
const GRAVITY := 1400.0

# --- 衝突レイヤー（main.gd と揃える。ロケット中の判定にも使う） ---
const LAYER_PLATFORM := 1
const LAYER_WALL := 2
const LAYER_ENEMY := 4

const ENEMY_TEXTURE := preload("res://assets/enemy.png")
# enemy.png の不透明範囲（Python/Pillowで検出）。余白を切り出して使う
const ENEMY_OPAQUE_REGION := Rect2(89.0, 9.0, 1363.0, 1015.0)
const ENEMY_RENDER_WIDTH := 44.0

var patrol_half_width := 80.0
var start_x := 0.0
var direction := 1
var sprite: Sprite2D

func _ready() -> void:
	start_x = global_position.x
	_build_visuals()
	add_to_group("enemies")
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_PLATFORM | LAYER_WALL

func _build_visuals() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(30, 26)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var atlas := AtlasTexture.new()
	atlas.atlas = ENEMY_TEXTURE
	atlas.region = ENEMY_OPAQUE_REGION
	var scale_factor := ENEMY_RENDER_WIDTH / ENEMY_OPAQUE_REGION.size.x

	sprite = Sprite2D.new()
	sprite.texture = atlas
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	velocity.x = direction * SPEED
	move_and_slide()
	if global_position.x > start_x + patrol_half_width:
		direction = -1
	elif global_position.x < start_x - patrol_half_width:
		direction = 1
	sprite.scale.x = absf(sprite.scale.x) * direction

func stomp() -> void:
	queue_free()
