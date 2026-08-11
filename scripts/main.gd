extends Node2D
## ゲーム全体の進行管理：塔の生成、登録者数の増減判定、
## 配信サイト風UI（動画エリア・ライブチャット・チャンネル情報バー）、勝利画面。
## 仕様: docs/spec/02_gameplay.md, 03_viewer_score_system.md, docs/spec/image.png（画面イメージ）

# --- レベルデザイン定数 ---
const FLOOR_HEIGHT := 140.0
const NUM_FLOORS := 40
const PLATFORM_WIDTH := 240.0
const PLATFORM_HEIGHT := 24.0
const PLAY_WIDTH := 640.0
const CHECKPOINT_INTERVAL := 10
const TREASURE_FLOORS := [5, 13, 17, 25, 33, 37]

# --- 登録者数バランス（合計 118,000,000。ゴール100,000,000に対し18%の余裕） ---
const FLOOR_BONUS := 1_500_000.0
const CHECKPOINT_BONUS := 10_000_000.0

# --- 減少条件のしきい値・レート ---
const DESCEND_THRESHOLD := FLOOR_HEIGHT * 0.9
const DESCEND_GRACE := 1.5
const DESCEND_DRAIN_PER_SEC := 200_000.0
const FALL_THRESHOLD := FLOOR_HEIGHT * 2.5
const FALL_PENALTY := 2_000_000.0
const FALL_COOLDOWN := 1.5

const POPUP_MIN_DELTA := 50_000

# --- 配信サイト風レイアウト定数（docs/spec/image.png の画面イメージを再現） ---
const WINDOW_WIDTH := 1280.0
const WINDOW_HEIGHT := 720.0
const CHAT_WIDTH := 300.0
const BOTTOM_BAR_HEIGHT := 130.0
const VIDEO_WIDTH := WINDOW_WIDTH - CHAT_WIDTH
const VIDEO_HEIGHT := WINDOW_HEIGHT - BOTTOM_BAR_HEIGHT

const STREAM_TITLE := "無限の塔登り配信中！スライム踏みつけ実況"
const CHANNEL_NAME := "とうのぼりチャンネル"

# --- ライブチャット演出（コメント欄）用データ ---
const CHAT_USERNAMES := [
	{"name": "とうろく太郎", "color": Color(0.45, 0.8, 1.0)},
	{"name": "のぼりer", "color": Color(0.6, 0.9, 0.45)},
	{"name": "財宝ハンター", "color": Color(1.0, 0.8, 0.35)},
	{"name": "スライム倒す人", "color": Color(1.0, 0.55, 0.75)},
	{"name": "匿名視聴者", "color": Color(0.8, 0.8, 0.85)},
	{"name": "登録者Bot", "color": Color(0.75, 0.65, 1.0)},
]
const CHAT_IDLE_MESSAGES := [
	"うぽつ〜", "もっと登れー!", "1億人いけー!!", "神プレイ",
	"がんばれ〜", "応援してる!", "888888", "すごい", "ここすき",
]
const CHAT_ON_FLOOR := ["登れ登れ!", "その調子!", "ナイスペース!"]
const CHAT_ON_CHECKPOINT := ["登録者数跳ね上がったww", "チェックポイント到達おめ!", "でかい!!"]
const CHAT_ON_TREASURE := ["お宝キタ!", "ナイス発見!", "ラッキー!"]
const CHAT_ON_STOMP := ["ナイス踏みつけ!", "スライム瞬殺www", "うまい!"]
const CHAT_ON_DAMAGE := ["危ない!", "被弾しちゃった…", "気をつけて!"]
const CHAT_ON_FALL := ["落ちたー!", "うわあああ", "戻っちゃった…"]

var world: Node2D
var player: Player
var sub_viewport: SubViewport

var checkpoint_positions: Array[Vector2] = []
var max_height_y: float = 0.0
var reached_floor: int = 0
var last_checkpoint_pos: Vector2 = Vector2.ZERO
var descend_timer: float = 0.0
var fall_cooldown_timer: float = 0.0

var ui_layer: CanvasLayer
var ui_root: Control
var popup_container: Control
var sub_label: Label
var progress: ProgressBar
var floor_label: Label
var chat_vbox: VBoxContainer
var chat_scroll: ScrollContainer
var chat_timer: Timer
var win_layer: CanvasLayer
var win_stats_label: Label

func _ready() -> void:
	GameState.reset()
	_build_video_world()
	_build_background()
	_build_boundaries()
	_generate_tower()
	_spawn_player()
	_build_video_overlay()
	_build_bottom_bar()
	_build_chat_panel()
	_build_win_screen()

	GameState.subscriber_changed.connect(_on_subscriber_changed)
	GameState.game_won.connect(_on_game_won)

# ---------------------------------------------------------------------------
# 配信サイト風レイアウト：ゲーム本編はSubViewportに収め、画面左側の「動画エリア」に表示する
# ---------------------------------------------------------------------------

func _build_video_world() -> void:
	var video_layer := CanvasLayer.new()
	video_layer.layer = 0
	add_child(video_layer)

	var svc := SubViewportContainer.new()
	svc.position = Vector2.ZERO
	svc.size = Vector2(VIDEO_WIDTH, VIDEO_HEIGHT)
	svc.stretch = true
	video_layer.add_child(svc)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(int(VIDEO_WIDTH), int(VIDEO_HEIGHT))
	svc.add_child(sub_viewport)

	world = Node2D.new()
	world.name = "World"
	sub_viewport.add_child(world)

# ---------------------------------------------------------------------------
# 塔の生成
# ---------------------------------------------------------------------------

func _generate_tower() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260811

	var start_x := PLAY_WIDTH / 2.0
	_add_platform(start_x, 0.0, 0, false)
	last_checkpoint_pos = Vector2(start_x, -PLATFORM_HEIGHT / 2.0 - 30.0)
	max_height_y = 0.0

	var prev_x := start_x
	for i in range(1, NUM_FLOORS + 1):
		var side := 1.0 if i % 2 == 1 else -1.0
		var offset := rng.randf_range(90.0, 200.0)
		var min_x := PLATFORM_WIDTH / 2.0 + 40.0
		var max_x := PLAY_WIDTH - PLATFORM_WIDTH / 2.0 - 40.0
		var x: float = clamp(prev_x + side * offset, min_x, max_x)
		var y := -float(i) * FLOOR_HEIGHT
		var is_checkpoint := (i % CHECKPOINT_INTERVAL == 0)

		_add_platform(x, y, i, is_checkpoint)

		if is_checkpoint:
			checkpoint_positions.append(Vector2(x, y - PLATFORM_HEIGHT / 2.0 - 30.0))
		elif TREASURE_FLOORS.has(i):
			_add_treasure(x, y)
		elif i % 3 == 0 and i > 2:
			_add_enemy(x, y)

		prev_x = x

func _add_platform(x: float, y: float, floor_index: int, is_checkpoint: bool) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x, y)

	var w := PLATFORM_WIDTH * 1.4 if is_checkpoint else PLATFORM_WIDTH
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, PLATFORM_HEIGHT)
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-w / 2.0, -PLATFORM_HEIGHT / 2.0), Vector2(w / 2.0, -PLATFORM_HEIGHT / 2.0),
		Vector2(w / 2.0, PLATFORM_HEIGHT / 2.0), Vector2(-w / 2.0, PLATFORM_HEIGHT / 2.0)
	])
	poly.color = Color(0.95, 0.8, 0.25) if is_checkpoint else Color(0.55, 0.5, 0.62)
	body.add_child(poly)

	if floor_index > 0:
		var label := Label.new()
		label.text = str(floor_index)
		label.position = Vector2(-w / 2.0 + 4.0, -PLATFORM_HEIGHT / 2.0 - 20.0)
		body.add_child(label)

	world.add_child(body)

func _add_enemy(x: float, y: float) -> void:
	var e := Enemy.new()
	e.position = Vector2(x, y - PLATFORM_HEIGHT / 2.0 - 20.0)
	e.patrol_half_width = PLATFORM_WIDTH / 2.0 - 20.0
	world.add_child(e)

func _add_treasure(x: float, y: float) -> void:
	var t := Treasure.new()
	t.position = Vector2(x, y - PLATFORM_HEIGHT / 2.0 - 20.0)
	world.add_child(t)

func _build_background() -> void:
	var total_height := NUM_FLOORS * FLOOR_HEIGHT + 600.0
	var bg := Polygon2D.new()
	var w := 2000.0
	bg.polygon = PackedVector2Array([
		Vector2(-w / 2.0, 200.0), Vector2(w / 2.0, 200.0),
		Vector2(w / 2.0, -total_height), Vector2(-w / 2.0, -total_height)
	])
	bg.color = Color(0.13, 0.11, 0.22)
	bg.z_index = -10
	bg.position.x = PLAY_WIDTH / 2.0
	world.add_child(bg)

	for i in range(0, NUM_FLOORS + 1, 5):
		var band := ColorRect.new()
		band.color = Color(1, 1, 1, 0.03)
		band.size = Vector2(w, FLOOR_HEIGHT * 2.5)
		band.position = Vector2(PLAY_WIDTH / 2.0 - w / 2.0, -float(i) * FLOOR_HEIGHT - FLOOR_HEIGHT * 2.5)
		band.z_index = -9
		world.add_child(band)

func _build_boundaries() -> void:
	var total_height := NUM_FLOORS * FLOOR_HEIGHT + 400.0

	var left := StaticBody2D.new()
	var lshape := RectangleShape2D.new()
	lshape.size = Vector2(40.0, total_height)
	var lcol := CollisionShape2D.new()
	lcol.shape = lshape
	left.add_child(lcol)
	left.position = Vector2(-20.0, -total_height / 2.0 + 200.0)
	world.add_child(left)

	var right := StaticBody2D.new()
	var rshape := RectangleShape2D.new()
	rshape.size = Vector2(40.0, total_height)
	var rcol := CollisionShape2D.new()
	rcol.shape = rshape
	right.add_child(rcol)
	right.position = Vector2(PLAY_WIDTH + 20.0, -total_height / 2.0 + 200.0)
	world.add_child(right)

	var safety := StaticBody2D.new()
	var sshape := RectangleShape2D.new()
	sshape.size = Vector2(PLAY_WIDTH + 80.0, 40.0)
	var scol := CollisionShape2D.new()
	scol.shape = sshape
	safety.add_child(scol)
	safety.position = Vector2(PLAY_WIDTH / 2.0, 120.0)
	world.add_child(safety)

func _spawn_player() -> void:
	player = Player.new()
	player.position = Vector2(PLAY_WIDTH / 2.0, -80.0)
	sub_viewport.add_child(player)
	player.set_camera_limits(-20.0, PLAY_WIDTH + 20.0, -NUM_FLOORS * FLOOR_HEIGHT - 200.0, 150.0)
	player.stomped_enemy.connect(func() -> void: _add_chat_message(CHAT_ON_STOMP.pick_random()))

# ---------------------------------------------------------------------------
# 進行判定（通常進行・階層到達ボーナス・降下・落下）
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_instance_valid(player) or GameState.won:
		return

	var y := player.global_position.y

	if y < max_height_y:
		max_height_y = y
		var new_floor: int = int(clamp(floor((0.0 - max_height_y) / FLOOR_HEIGHT), 0, NUM_FLOORS))
		while reached_floor < new_floor:
			reached_floor += 1
			GameState.add_subscribers(FLOOR_BONUS, "登頂中")
			if reached_floor % CHECKPOINT_INTERVAL == 0:
				GameState.add_subscribers(CHECKPOINT_BONUS, "階層到達ボーナス!")
				var idx := reached_floor / CHECKPOINT_INTERVAL - 1
				if idx >= 0 and idx < checkpoint_positions.size():
					last_checkpoint_pos = checkpoint_positions[idx]
			floor_label.text = "現在 %d / %d 階" % [reached_floor, NUM_FLOORS]

	var depth_below_best := y - max_height_y
	if depth_below_best > DESCEND_THRESHOLD:
		descend_timer += delta
		if descend_timer > DESCEND_GRACE:
			GameState.lose_subscribers(DESCEND_DRAIN_PER_SEC * delta, "降下")
	else:
		descend_timer = 0.0

	if fall_cooldown_timer > 0.0:
		fall_cooldown_timer -= delta
	elif depth_below_best > FALL_THRESHOLD:
		GameState.lose_subscribers(FALL_PENALTY, "落下")
		player.teleport_to(last_checkpoint_pos)
		max_height_y = min(max_height_y, last_checkpoint_pos.y)
		descend_timer = 0.0
		fall_cooldown_timer = FALL_COOLDOWN

# ---------------------------------------------------------------------------
# 動画エリアのオーバーレイ（LIVEバッジ・タイトル・決め台詞・増減ポップアップ）
# ---------------------------------------------------------------------------

func _build_video_overlay() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	var overlay := Control.new()
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(VIDEO_WIDTH, VIDEO_HEIGHT)
	overlay.clip_contents = true
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(overlay)

	# 上部バー：LIVEバッジ + 配信タイトル
	var title_bg := ColorRect.new()
	title_bg.color = Color(0, 0, 0, 0.55)
	title_bg.size = Vector2(VIDEO_WIDTH, 36)
	overlay.add_child(title_bg)

	var live_badge := Label.new()
	live_badge.text = "● LIVE"
	live_badge.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	live_badge.add_theme_font_size_override("font_size", 18)
	live_badge.position = Vector2(10, 6)
	overlay.add_child(live_badge)
	var blink := create_tween()
	blink.set_loops()
	blink.tween_property(live_badge, "modulate:a", 0.3, 0.6)
	blink.tween_property(live_badge, "modulate:a", 1.0, 0.6)

	var title_label := Label.new()
	title_label.text = STREAM_TITLE
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.position = Vector2(90, 8)
	overlay.add_child(title_label)

	# 決め台詞（開始時に表示してフェードアウト）
	var catchphrase := Label.new()
	catchphrase.text = "「みんなが見てない世界を見せてやるぜ」"
	catchphrase.add_theme_font_size_override("font_size", 20)
	catchphrase.add_theme_color_override("font_color", Color(1, 1, 0.8))
	catchphrase.position = Vector2(20, VIDEO_HEIGHT - 50)
	overlay.add_child(catchphrase)
	var fade := create_tween()
	fade.tween_interval(3.0)
	fade.tween_property(catchphrase, "modulate:a", 0.0, 1.0)

	# 登録者数の増減ポップアップ（画面中央上寄り）
	popup_container = Control.new()
	popup_container.position = Vector2(VIDEO_WIDTH / 2.0 - 80.0, 60.0)
	popup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(popup_container)

# ---------------------------------------------------------------------------
# 下部バー：動画タイトル/登録者数/進捗バー/階数 + チャンネル情報行
# ---------------------------------------------------------------------------

func _build_bottom_bar() -> void:
	var bar := Control.new()
	bar.position = Vector2(0, VIDEO_HEIGHT)
	bar.size = Vector2(VIDEO_WIDTH, BOTTOM_BAR_HEIGHT)
	ui_root.add_child(bar)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.size = bar.size
	bar.add_child(bg)

	sub_label = Label.new()
	sub_label.text = "%s　登録者数 0人 / 目標 100,000,000人" % STREAM_TITLE
	sub_label.add_theme_font_size_override("font_size", 18)
	sub_label.position = Vector2(16, 8)
	bar.add_child(sub_label)

	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = GameState.GOAL
	progress.value = 0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(VIDEO_WIDTH - 32, 10)
	progress.position = Vector2(16, 36)
	bar.add_child(progress)

	floor_label = Label.new()
	floor_label.text = "現在 0 / %d 階" % NUM_FLOORS
	floor_label.add_theme_font_size_override("font_size", 14)
	floor_label.position = Vector2(16, 50)
	bar.add_child(floor_label)

	# チャンネル情報行：アバター・チャンネル名・視聴者数・登録ボタン・高評価/共有
	var avatar := Panel.new()
	avatar.size = Vector2(40, 40)
	avatar.position = Vector2(16, 78)
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = Color(0.25, 0.75, 0.95)
	avatar_style.corner_radius_top_left = 20
	avatar_style.corner_radius_top_right = 20
	avatar_style.corner_radius_bottom_left = 20
	avatar_style.corner_radius_bottom_right = 20
	avatar.add_theme_stylebox_override("panel", avatar_style)
	bar.add_child(avatar)

	var channel_name := Label.new()
	channel_name.text = CHANNEL_NAME
	channel_name.add_theme_font_size_override("font_size", 16)
	channel_name.position = Vector2(64, 78)
	bar.add_child(channel_name)

	var watching_label := Label.new()
	watching_label.text = "1.2K 視聴中"
	watching_label.add_theme_font_size_override("font_size", 12)
	watching_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	watching_label.position = Vector2(64, 98)
	bar.add_child(watching_label)

	var subscribe_btn := Button.new()
	subscribe_btn.text = "登録する"
	subscribe_btn.custom_minimum_size = Vector2(88, 32)
	subscribe_btn.position = Vector2(220, 82)
	subscribe_btn.disabled = true
	bar.add_child(subscribe_btn)

	var like_label := Label.new()
	like_label.text = "👍 1.2K　👎　🔗 共有　⋯"
	like_label.add_theme_font_size_override("font_size", 14)
	like_label.position = Vector2(VIDEO_WIDTH - 260, 88)
	bar.add_child(like_label)

# ---------------------------------------------------------------------------
# ライブチャット欄（画面右側）
# ---------------------------------------------------------------------------

func _build_chat_panel() -> void:
	var panel := Control.new()
	panel.position = Vector2(VIDEO_WIDTH, 0)
	panel.size = Vector2(CHAT_WIDTH, WINDOW_HEIGHT)
	ui_root.add_child(panel)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.13)
	bg.size = panel.size
	panel.add_child(bg)

	var header := Label.new()
	header.text = "LIVE CHAT"
	header.add_theme_font_size_override("font_size", 16)
	header.position = Vector2(12, 10)
	panel.add_child(header)

	chat_scroll = ScrollContainer.new()
	chat_scroll.position = Vector2(0, 40)
	chat_scroll.size = Vector2(CHAT_WIDTH, WINDOW_HEIGHT - 40.0 - 44.0)
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(chat_scroll)

	chat_vbox = VBoxContainer.new()
	chat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_vbox.custom_minimum_size = Vector2(CHAT_WIDTH - 16.0, 0)
	chat_vbox.position = Vector2(8, 4)
	chat_scroll.add_child(chat_vbox)

	var input_bg := ColorRect.new()
	input_bg.color = Color(0.16, 0.16, 0.2)
	input_bg.position = Vector2(0, WINDOW_HEIGHT - 44.0)
	input_bg.size = Vector2(CHAT_WIDTH, 44)
	panel.add_child(input_bg)

	var input_hint := Label.new()
	input_hint.text = "メッセージを入力…"
	input_hint.add_theme_font_size_override("font_size", 12)
	input_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	input_hint.position = Vector2(12, WINDOW_HEIGHT - 30.0)
	panel.add_child(input_hint)

	chat_timer = Timer.new()
	chat_timer.one_shot = false
	chat_timer.wait_time = 1.6
	chat_timer.timeout.connect(_on_chat_timer_timeout)
	add_child(chat_timer)
	chat_timer.start()

	for i in range(4):
		_add_chat_message(CHAT_IDLE_MESSAGES.pick_random())

func _on_chat_timer_timeout() -> void:
	_add_chat_message(CHAT_IDLE_MESSAGES.pick_random())
	chat_timer.wait_time = randf_range(1.2, 3.0)

func _add_chat_message(text: String) -> void:
	var user: Dictionary = CHAT_USERNAMES.pick_random()
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(CHAT_WIDTH - 24.0, 0)
	var color_hex: String = (user["color"] as Color).to_html(false)
	line.text = "[color=#%s]%s[/color]: %s" % [color_hex, user["name"], text]
	line.add_theme_font_size_override("normal_font_size", 13)
	chat_vbox.add_child(line)

	if chat_vbox.get_child_count() > 40:
		var oldest := chat_vbox.get_child(0)
		chat_vbox.remove_child(oldest)
		oldest.queue_free()

	call_deferred("_scroll_chat_to_bottom")

func _scroll_chat_to_bottom() -> void:
	chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func _on_subscriber_changed(total: int, delta: int, reason: String) -> void:
	sub_label.text = "%s　登録者数 %s人 / 目標 100,000,000人" % [STREAM_TITLE, _format_number(total)]
	progress.value = total
	if abs(delta) >= POPUP_MIN_DELTA:
		_spawn_popup(delta, reason)
	match reason:
		"登頂中":
			_add_chat_message(CHAT_ON_FLOOR.pick_random())
		"階層到達ボーナス!":
			_add_chat_message(CHAT_ON_CHECKPOINT.pick_random())
		"財宝入手":
			_add_chat_message(CHAT_ON_TREASURE.pick_random())
		"被弾":
			_add_chat_message(CHAT_ON_DAMAGE.pick_random())
		"落下":
			_add_chat_message(CHAT_ON_FALL.pick_random())

func _spawn_popup(delta: int, reason: String) -> void:
	var lbl := Label.new()
	var sign_str := "+" if delta > 0 else ""
	lbl.text = "%s%s  %s" % [sign_str, _format_number(delta), reason]
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4) if delta > 0 else Color(1.0, 0.4, 0.4))
	lbl.position = Vector2(randf_range(-10.0, 10.0), 0.0)
	popup_container.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 40.0, 1.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2)
	tw.chain().tween_callback(lbl.queue_free)

func _format_number(n: int) -> String:
	var negative := n < 0
	var s := str(abs(n))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result
	return ("-" if negative else "") + result

# ---------------------------------------------------------------------------
# 勝利画面
# ---------------------------------------------------------------------------

func _build_win_screen() -> void:
	win_layer = CanvasLayer.new()
	win_layer.layer = 20
	win_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(win_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_layer.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	win_layer.add_child(vbox)

	var title := Label.new()
	title.text = "登録者数 1億人 達成！"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var msg := Label.new()
	msg.text = "「塔の中で手に入れたものは、ちゃんとみんなに配るぜ！」"
	msg.add_theme_font_size_override("font_size", 18)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	win_stats_label = Label.new()
	win_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(win_stats_label)

	var btn := Button.new()
	btn.text = "もう一度プレイ"
	btn.custom_minimum_size = Vector2(160, 40)
	btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(btn)

	win_layer.visible = false

func _on_game_won() -> void:
	win_stats_label.text = "到達フロア: %d / %d 階" % [reached_floor, NUM_FLOORS]
	win_layer.visible = true
	get_tree().paused = true

func _on_restart_pressed() -> void:
	get_tree().paused = false
	GameState.reset()
	get_tree().reload_current_scene()
