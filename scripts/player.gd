class_name Player
extends CharacterBody2D
## プレイヤー：移動・ジャンプ・踏みつけ戦闘・被弾を扱う。
## 仕様: docs/spec/02_gameplay.md（操作方法）, 03_viewer_score_system.md（被弾ペナルティ）

signal took_damage
signal stomped_enemy

const SPEED := 260.0
const JUMP_VELOCITY := -560.0 * 1.1
const GRAVITY := 1400.0 * 0.8
# const BOUNCE_VELOCITY := -380.0
const BOUNCE_VELOCITY := JUMP_VELOCITY
const MAX_FALL_SPEED := 900.0

const DAMAGE_PENALTY := 2_000_000.0
const HITSTUN_TIME := 0.5
const INVULN_TIME := 1.2

const IDLE_GRACE := 2.5
const IDLE_DRAIN_PER_SEC := 300_000.0

const JUMP_BUFFER_FRAMES := 3

const JUMP_BOOST_MULTIPLIER := 3.0
const ROCKET_SPEED := 700.0

# --- 衝突レイヤー（ロケット中は足場(LAYER_PLATFORM)だけ貫通する） ---
const LAYER_PLATFORM := 1
const LAYER_WALL := 2
const LAYER_ENEMY := 4
const LAYER_PLAYER := 8
const MASK_NORMAL := LAYER_PLATFORM | LAYER_WALL | LAYER_ENEMY
const MASK_ROCKET := LAYER_WALL | LAYER_ENEMY

const SFX_JUMP := preload("res://assets/player_jump.wav")
const SFX_DAMAGE := preload("res://assets/player_damaged2.wav")
const SFX_ENEMY_KILLED := preload("res://assets/enemy_killed2.wav")

var jump_sfx: AudioStreamPlayer
var damage_sfx: AudioStreamPlayer
var enemy_killed_sfx: AudioStreamPlayer

var idle_time := 0.0
var hitstun_timer := 0.0
var invuln_timer := 0.0
var facing := 1

var jump_buffer_timer := 0.0
var jump_buffer_time := 0.05

var jump_boost_timer := 0.0
var rocket_timer := 0.0

var visual: Node2D
var camera: Camera2D

func _ready() -> void:
	_build_visuals()
	add_to_group("player")
	jump_buffer_time = JUMP_BUFFER_FRAMES / float(Engine.physics_ticks_per_second)
	collision_layer = LAYER_PLAYER
	collision_mask = MASK_NORMAL

func _build_visuals() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 48)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([Vector2(-16, -24), Vector2(16, -24), Vector2(16, 24), Vector2(-16, 24)])
	body.color = Color(0.25, 0.75, 0.95)
	visual.add_child(body)

	var eye := Polygon2D.new()
	eye.polygon = PackedVector2Array([Vector2(2, -14), Vector2(14, -14), Vector2(14, -4), Vector2(2, -4)])
	eye.color = Color(1, 1, 1)
	visual.add_child(eye)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.zoom = Vector2(1.3, 1.3)
	add_child(camera)

	jump_sfx = AudioStreamPlayer.new()
	jump_sfx.stream = SFX_JUMP
	add_child(jump_sfx)

	damage_sfx = AudioStreamPlayer.new()
	damage_sfx.stream = SFX_DAMAGE
	add_child(damage_sfx)

	enemy_killed_sfx = AudioStreamPlayer.new()
	enemy_killed_sfx.stream = SFX_ENEMY_KILLED
	add_child(enemy_killed_sfx)

func set_camera_limits(left: float, right: float, top: float, bottom: float) -> void:
	camera.limit_left = int(left)
	camera.limit_right = int(right)
	camera.limit_top = int(top)
	camera.limit_bottom = int(bottom)

func _physics_process(delta: float) -> void:
	if jump_boost_timer > 0.0:
		jump_boost_timer -= delta

	if rocket_timer > 0.0:
		collision_mask = MASK_ROCKET
		rocket_timer -= delta
		velocity.y = -ROCKET_SPEED
		var dir := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		velocity.x = dir * SPEED
		if dir != 0.0:
			facing = 1 if dir > 0.0 else -1
			visual.scale.x = facing
	else:
		collision_mask = MASK_NORMAL
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

		if hitstun_timer > 0.0:
			hitstun_timer -= delta
		else:
			var dir := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
			velocity.x = dir * SPEED
			if dir != 0.0:
				facing = 1 if dir > 0.0 else -1
				visual.scale.x = facing

			# ジャンプ先行入力：着地の少し前に押しても、着地した瞬間にジャンプする
			if Input.is_action_just_pressed("jump"):
				jump_buffer_timer = jump_buffer_time
			else:
				jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

			if jump_buffer_timer > 0.0 and is_on_floor():
				var boost := JUMP_BOOST_MULTIPLIER if jump_boost_timer > 0.0 else 1.0
				velocity.y = JUMP_VELOCITY * boost
				jump_buffer_timer = 0.0
				jump_sfx.play()

	if invuln_timer > 0.0:
		invuln_timer -= delta
		modulate.a = 0.4 if int(invuln_timer * 12.0) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0

	move_and_slide()
	_handle_collisions()
	_update_idle(delta)

func apply_item_effect(kind: int, duration: float) -> void:
	match kind:
		Item.Kind.INVINCIBLE:
			invuln_timer = max(invuln_timer, duration)
		Item.Kind.JUMP_BOOST:
			jump_boost_timer = duration
		Item.Kind.ROCKET:
			rocket_timer = duration
			invuln_timer = max(invuln_timer, duration)

func _handle_collisions() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Enemy:
			if col.get_normal().y < -0.5:
				collider.stomp()
				enemy_killed_sfx.play()
				velocity.y = BOUNCE_VELOCITY
				stomped_enemy.emit()
			elif invuln_timer > 0.0:
				# 無敵状態なら、真上以外から触れても敵を倒す
				collider.stomp()
				enemy_killed_sfx.play()
				stomped_enemy.emit()
			else:
				take_damage(collider.global_position)

func take_damage(source_pos: Vector2 = global_position) -> void:
	if invuln_timer > 0.0 or hitstun_timer > 0.0:
		return
	GameState.lose_subscribers(DAMAGE_PENALTY, "被弾")
	damage_sfx.play()
	hitstun_timer = HITSTUN_TIME
	invuln_timer = INVULN_TIME
	var dir := signf(global_position.x - source_pos.x)
	if dir == 0.0:
		dir = 1.0
	velocity = Vector2(dir * 220.0, -320.0)
	took_damage.emit()

func _update_idle(delta: float) -> void:
	if is_on_floor() and abs(velocity.x) < 5.0 and hitstun_timer <= 0.0:
		idle_time += delta
		if idle_time > IDLE_GRACE:
			GameState.lose_subscribers(IDLE_DRAIN_PER_SEC * delta, "放置")
	else:
		idle_time = 0.0
