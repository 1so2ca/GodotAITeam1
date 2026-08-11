extends Node2D
## ゲーム全体の進行管理：塔の生成、登録者数の増減判定、
## 配信サイト風UI（動画エリア・ライブチャット・チャンネル情報バー）、勝利画面。
## 仕様: docs/spec/02_gameplay.md, 03_viewer_score_system.md, docs/spec/image.png（画面イメージ）

# --- レベルデザイン定数 ---
const FLOOR_HEIGHT := 140.0
const PLATFORM_WIDTH := 240.0
const PLATFORM_HEIGHT := 24.0
const PLAY_WIDTH := 720.0
const CHECKPOINT_INTERVAL := 10
const TREASURE_INTERVAL := 8
const TREASURE_OFFSET := 4
const ITEM_SPAWN_CHANCE := 0.15
# 塔の乱数シードは固定なので、確率任せだと同じ場所でずっと外れ続けることがある。
# 抽選対象の階が一定回数連続で外れたら強制的に出現させ、必ずどこかで手に入るようにする。
const ITEM_PITY_FLOORS := 10

# --- 塔は階数制限なし。プレイヤーの到達に応じて先読み生成する ---
const INITIAL_FLOORS := 40
const GENERATE_AHEAD := 15
const GENERATE_BATCH := 20

# --- 足場の間隔（隣接フロアの当たり判定が重ならないようにする） ---
# 真上にジャンプしても頭がぶつからないよう、中心間オフセットは
# 「両足場の半幅の合計 + 最低ギャップ」を必ず超える値にする
const MIN_PLATFORM_GAP := 30.0
const GAP_VARIANCE := 90.0

# --- 足場の見た目（assets/content.png のレンガをタイル状に敷き詰める） ---
# PLATFORM_WIDTH(240)・チェックポイント幅(336)がどちらも48の倍数になるように選んでいる
const TILE_RENDER_WIDTH := 48.0
# content_resize.png は上下に透明な余白があり、そのままタイルすると余白分の隙間が
# 見えてしまうため、不透明な範囲だけを切り出して使う（Python/Pillowで検出した範囲）
const CONTENT_OPAQUE_REGION := Rect2(0.0, 25.0, 1024.0, 936.0)

# --- 背景（assets/background.png をループ表示する） ---
const BACKGROUND_TEXTURE := preload("res://assets/background.png")

# --- 衝突レイヤー（ロケット中に足場だけ貫通できるようにするため分離する） ---
const LAYER_PLATFORM := 1
const LAYER_WALL := 2
const LAYER_ENEMY := 4
const LAYER_PLAYER := 8

# --- 登録者数バランス（通常進行+チェックポイント+財宝） ---
const FLOOR_BONUS := 1_500_000.0
const CHECKPOINT_BONUS := 10_000_000.0

# --- 減少条件のしきい値・レート ---
# 「落下」は特殊なテレポート判定を持たない。物理挙動のまま一番下まで自然に落ちる。
# 最高到達点から一定以上離れた状態が続くと、まとめて一度だけ減点し、基準点を
# その場にリセットする（＝自動減少を止める）。ここでまた離れれば再度減点される。
const DESCEND_THRESHOLD := FLOOR_HEIGHT * 0.9
const DESCEND_GRACE := 1.5
# 減点は固定値ではなく「現在の登録者数に対する割合」×「落下フロア数」で決める。
# 大きく落ちるほど割合が増え、長く落ち続けるほど判定が繰り返されるため、
# 高所からの大転落は登録者数が1万人前後まで落ち込むほどの大打撃になる
const DESCEND_PENALTY_RATIO_PER_FLOOR := 0.05
const DESCEND_PENALTY_MIN_RATIO := 0.08
const DESCEND_PENALTY_MAX_RATIO := 0.7

const POPUP_MIN_DELTA := 50_000

# --- 配信サイト風レイアウト定数（docs/spec/image.png の画面イメージを再現） ---
const WINDOW_WIDTH := 1280.0
const WINDOW_HEIGHT := 720.0
const CHAT_WIDTH := 300.0
const BOTTOM_BAR_HEIGHT := 130.0
const VIDEO_WIDTH := WINDOW_WIDTH - CHAT_WIDTH
const VIDEO_HEIGHT := WINDOW_HEIGHT - BOTTOM_BAR_HEIGHT

const STREAM_TITLE := "無限の塔登り配信中！～登録者数1億人へのカウントダウン開始！～"
const CHANNEL_NAME := "世紀の大盗賊CH【財宝山分けプロジェクト】"

# --- ライブチャット演出（コメント欄）用データ ---
# unlock_floor: このユーザーが登場し始める到達階数（それより前は他ユーザーのみ発言する）
const CHAT_USERNAMES := [
	{"name": "塔の税務署", "color": Color(0.6, 0.7, 0.95), "unlock_floor": 0},
	{"name": "1億人耐久@金塊待ち", "color": Color(1.0, 0.85, 0.3), "unlock_floor": 0},
	{"name": "古事記のエルフ", "color": Color(0.55, 0.9, 0.6), "unlock_floor": 20},
	{"name": "お宝クレクレスライム", "color": Color(0.9, 0.55, 0.95), "unlock_floor": 20},
	{"name": "山分け希望のゴブリン", "color": Color(0.9, 0.55, 0.3), "unlock_floor": 30},
	{"name": "錬金術失敗したマン", "color": Color(0.7, 0.55, 0.85), "unlock_floor": 30},
]
const CHAT_IDLE_MESSAGES := [
	"うぽつ〜", "もっと登れー!", "1億人いけー!!", "神プレイ",
	"がんばれ〜", "応援してる!", "888888", "すごい", "ここすき",
	"お見事！さすがの跳躍力だな", "キラキラしたやつ、ちょうだい",
	"登るごとに税金が増えます", "人間にしては悪くないパフォーマンスね",
	"きたあああああ今日も財宝よろ！", "待ってました！",
]
const CHAT_ON_STOMP := ["ナイス踏みつけ!", "スライム瞬殺www", "うまい!"]
const CHAT_ON_DAMAGE := ["危ない!", "被弾しちゃった…", "気をつけて!"]
const CHAT_ON_FALL := ["落ちたー!", "うわあああ", "戻っちゃった…"]
const CHAT_WIN_MESSAGES := [
	"きたあああああ1億人達成!!!", "神プレイすぎる!!!", "伝説を見た…",
	"うおおおおおおおおお", "1億人おめでとう!!!!", "こんなの見たことない",
	"歴史的瞬間に立ち会えた", "最高すぎる配信だった", "感動した…泣いてる",
	"これは殿堂入り", "神回確定", "拍手拍手拍手拍手拍手",
	"財宝山分けされるらしい!!", "伝説の大盗賊誕生の瞬間", "語彙力なくなるくらいすごい",
]

# --- 登録者数増加時に「新しい視聴者」が登録コメントを投稿する演出用データ ---
const NEW_COMMENTER_COLOR := Color(1.0, 0.95, 0.4)
const NEW_COMMENTER_PREFIXES := ["名無しの", "通りすがりの", "新参", "初見の", "旅の", "匿名の", ""]
const NEW_COMMENTER_NOUNS := ["視聴者", "冒険者", "旅人", "登山家", "ファン", "リスナー"]
const NEW_SUBSCRIBER_MESSAGES := [
	"登録しました!!", "チャンネル登録ぽちー", "初コメです、登録した!",
	"面白すぎて登録しちゃった", "登録者一人増えたよ〜", "登録完了!応援してる",
]

var world: Node2D
var player: Player
var sub_viewport: SubViewport
var content_texture: Texture2D

# --- 塔生成の進行状態 ---
var rng: RandomNumberGenerator
var prev_x: float = 0.0
var prev_width: float = 0.0
var generated_floor: int = 0
var bands_generated_up_to: int = -5
var floors_since_item: int = 0

# --- 背景・境界壁（塔の伸長に合わせて拡張する） ---
var bg_sprite: Sprite2D
var bg_width: float = 2000.0
var left_wall: StaticBody2D
var left_shape: RectangleShape2D
var right_wall: StaticBody2D
var right_shape: RectangleShape2D

var max_height_y: float = 0.0
var reached_floor: int = 0
var descend_timer: float = 0.0

var ui_layer: CanvasLayer
var ui_root: Control
var popup_container: Control
var sub_label: Label
var progress: ProgressBar
var floor_label: Label
var chat_vbox: VBoxContainer
var chat_scroll: ScrollContainer
var chat_timer: Timer
var win_overlay: Control
var win_flash: ColorRect
var win_title_label: Label
var win_chat_timer: Timer
var clear_sfx: AudioStreamPlayer

var title_layer: CanvasLayer
var bgm_player: AudioStreamPlayer

func _ready() -> void:
	_play_bgm()
	_build_title_screen()

func _play_bgm() -> void:
	var stream: AudioStreamMP3 = preload("res://assets/bgm.mp3")
	stream.loop = true
	bgm_player = AudioStreamPlayer.new()
	bgm_player.stream = stream
	add_child(bgm_player)
	bgm_player.play()

# ---------------------------------------------------------------------------
# タイトル画面：配信画面の領域（動画エリア）に assets/start.png を表示し、
# ボタン押下でゲーム画面へ即座に遷移する
# ---------------------------------------------------------------------------

func _build_title_screen() -> void:
	title_layer = CanvasLayer.new()
	title_layer.layer = 20
	add_child(title_layer)

	# 704x384 の固定サイズで画面中央に配置する
	var box_w := 704.0
	var box_h := 384.0

	var bg := TextureRect.new()
	bg.texture = preload("res://assets/start.png")
	bg.position = Vector2((VIDEO_WIDTH - box_w) / 2.0, (VIDEO_HEIGHT - box_h) / 2.0)
	bg.size = Vector2(box_w, box_h)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	title_layer.add_child(bg)

	var prompt_bg := ColorRect.new()
	prompt_bg.color = Color(0, 0, 0, 0.55)
	prompt_bg.size = Vector2(VIDEO_WIDTH, 40)
	prompt_bg.position = Vector2(0, VIDEO_HEIGHT - 40)
	title_layer.add_child(prompt_bg)

	var prompt := Label.new()
	prompt.text = "ボタンを押してスタート"
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", Color(1, 1, 0.85))
	prompt.size = Vector2(VIDEO_WIDTH, 40)
	prompt.position = Vector2(0, VIDEO_HEIGHT - 40)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_layer.add_child(prompt)

	var blink := create_tween()
	blink.set_loops()
	blink.tween_property(prompt, "modulate:a", 0.3, 0.6)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.6)

func _input(event: InputEvent) -> void:
	if title_layer == null:
		return
	var is_start_input: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
	)
	if is_start_input:
		_on_start_pressed()

func _on_start_pressed() -> void:
	title_layer.queue_free()
	title_layer = null
	_start_game()

func _start_game() -> void:
	GameState.reset()
	rng = RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system() * 1000) % 2147483647
	rng.randomize()
	content_texture = load("res://assets/content_resize.png")

	_build_video_world()
	_init_environment()
	_generate_start_platform()
	_extend_tower(INITIAL_FLOORS)
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
# 塔の生成（階数制限なし。プレイヤーの到達に応じて先読み生成する）
# ---------------------------------------------------------------------------

func _generate_start_platform() -> void:
	var start_x := PLAY_WIDTH / 2.0
	_add_platform(start_x, 0.0, 0, false)
	max_height_y = 0.0
	prev_x = start_x
	prev_width = PLATFORM_WIDTH
	generated_floor = 0

func _extend_tower(target_floor: int) -> void:
	if target_floor <= generated_floor:
		return

	for i in range(generated_floor + 1, target_floor + 1):
		var is_checkpoint := (i % CHECKPOINT_INTERVAL == 0)
		var this_width := PLATFORM_WIDTH * 1.4 if is_checkpoint else PLATFORM_WIDTH
		var y := -float(i) * FLOOR_HEIGHT

		# 前の足場と必ず離れる（重ならない）ように、中心間の最低オフセットを
		# 「両足場の半幅の合計 + 最低ギャップ」として計算する
		var min_offset: float = prev_width / 2.0 + this_width / 2.0 + MIN_PLATFORM_GAP
		var offset := min_offset + rng.randf_range(0.0, GAP_VARIANCE)
		var side := 1.0 if i % 2 == 1 else -1.0

		var min_x := this_width / 2.0 + 40.0
		var max_x := PLAY_WIDTH - this_width / 2.0 - 40.0

		var x: float = clamp(prev_x + side * offset, min_x, max_x)
		if absf(x - prev_x) < min_offset:
			side = -side
			x = clamp(prev_x + side * offset, min_x, max_x)
		if absf(x - prev_x) < min_offset:
			# 画面端付近でどちらの側にも十分な間隔が確保できない場合は、
			# 最も離れる位置（反対側の端）に寄せる
			x = max_x if prev_x <= (min_x + max_x) / 2.0 else min_x

		_add_platform(x, y, i, is_checkpoint)

		if is_checkpoint:
			pass
		elif i % TREASURE_INTERVAL == TREASURE_OFFSET:
			_add_treasure(x, y)
		elif i % 3 == 0 and i > 2:
			_add_enemy(x, y)
		else:
			floors_since_item += 1
			if rng.randf() < ITEM_SPAWN_CHANCE or floors_since_item >= ITEM_PITY_FLOORS:
				_add_item(x, y)
				floors_since_item = 0

		prev_x = x
		prev_width = this_width

	generated_floor = target_floor
	_extend_environment(target_floor)

func _add_platform(x: float, y: float, floor_index: int, is_checkpoint: bool) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x, y)

	var w := PLATFORM_WIDTH * 1.4 if is_checkpoint else PLATFORM_WIDTH
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, PLATFORM_HEIGHT)
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	body.collision_layer = LAYER_PLATFORM
	body.collision_mask = 0

	_add_platform_texture(body, w, is_checkpoint)

	if floor_index > 0:
		var label := Label.new()
		label.text = str(floor_index)
		label.position = Vector2(-w / 2.0 + 4.0, -PLATFORM_HEIGHT / 2.0 - 20.0)
		body.add_child(label)

	world.add_child(body)

func _add_platform_texture(body: StaticBody2D, w: float, is_checkpoint: bool) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = content_texture
	atlas.region = CONTENT_OPAQUE_REGION
	var scale_factor := TILE_RENDER_WIDTH / CONTENT_OPAQUE_REGION.size.x
	var tile_count := int(ceil(w / TILE_RENDER_WIDTH))
	for i in range(tile_count):
		var spr := Sprite2D.new()
		spr.texture = atlas
		spr.centered = false
		spr.scale = Vector2(scale_factor, scale_factor)
		spr.position = Vector2(-w / 2.0 + i * TILE_RENDER_WIDTH, -PLATFORM_HEIGHT / 2.0)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if is_checkpoint:
			spr.modulate = Color(1.25, 1.15, 0.6)
		body.add_child(spr)

func _add_enemy(x: float, y: float) -> void:
	var e := Enemy.new()
	e.position = Vector2(x, y - PLATFORM_HEIGHT / 2.0 - 20.0)
	e.patrol_half_width = PLATFORM_WIDTH / 2.0 - 20.0
	world.add_child(e)

func _add_treasure(x: float, y: float) -> void:
	var t := Treasure.new()
	t.position = Vector2(x, y - PLATFORM_HEIGHT / 2.0 - 20.0)
	world.add_child(t)

func _add_item(x: float, y: float) -> void:
	var it := Item.new()
	var kinds := [Item.Kind.INVINCIBLE, Item.Kind.JUMP_BOOST, Item.Kind.ROCKET]
	it.kind = kinds[rng.randi_range(0, kinds.size() - 1)]
	it.position = Vector2(x, y - PLATFORM_HEIGHT / 2.0 - 20.0)
	it.collected.connect(_on_item_collected)
	world.add_child(it)

func _on_item_collected(kind: int) -> void:
	var text: String
	match kind:
		Item.Kind.INVINCIBLE:
			text = "⚡ 無敵タイム!"
		Item.Kind.JUMP_BOOST:
			text = "⬆ ジャンプ力3倍!"
		Item.Kind.ROCKET:
			text = "🚀 ロケット発進!"
		_:
			text = ""
	_spawn_item_popup(text)

func _spawn_item_popup(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	lbl.position = Vector2(randf_range(-10.0, 10.0), 0.0)
	popup_container.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 40.0, 1.4)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.4)
	tw.chain().tween_callback(lbl.queue_free)

# ---------------------------------------------------------------------------
# 背景・境界壁（塔の伸長に合わせて拡張する）
# ---------------------------------------------------------------------------

func _init_environment() -> void:
	bg_sprite = Sprite2D.new()
	bg_sprite.texture = BACKGROUND_TEXTURE
	bg_sprite.centered = false
	bg_sprite.region_enabled = true
	bg_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 足場のブロック（TILE_RENDER_WIDTH）と同じサイズでループさせる
	bg_sprite.scale = Vector2.ONE * (TILE_RENDER_WIDTH / BACKGROUND_TEXTURE.get_size().x)
	bg_sprite.z_index = -10
	world.add_child(bg_sprite)

	left_wall = StaticBody2D.new()
	left_shape = RectangleShape2D.new()
	var lcol := CollisionShape2D.new()
	lcol.shape = left_shape
	left_wall.add_child(lcol)
	left_wall.collision_layer = LAYER_WALL
	left_wall.collision_mask = 0
	world.add_child(left_wall)

	right_wall = StaticBody2D.new()
	right_shape = RectangleShape2D.new()
	var rcol := CollisionShape2D.new()
	rcol.shape = right_shape
	right_wall.add_child(rcol)
	right_wall.collision_layer = LAYER_WALL
	right_wall.collision_mask = 0
	world.add_child(right_wall)

	var safety := StaticBody2D.new()
	var sshape := RectangleShape2D.new()
	sshape.size = Vector2(PLAY_WIDTH + 80.0, 40.0)
	var scol := CollisionShape2D.new()
	scol.shape = sshape
	safety.add_child(scol)
	safety.position = Vector2(PLAY_WIDTH / 2.0, 120.0)
	safety.collision_layer = LAYER_WALL
	safety.collision_mask = 0
	world.add_child(safety)

	_extend_environment(0)

func _extend_environment(target_floor: int) -> void:
	var bottom_y := 200.0

	var bg_top := -float(target_floor) * FLOOR_HEIGHT - 600.0
	var bg_left := PLAY_WIDTH / 2.0 - bg_width / 2.0
	bg_sprite.position = Vector2(bg_left, bg_top)
	# region_rect はスケール適用前のローカル単位。実際の見た目のサイズをスケールで割って求める
	bg_sprite.region_rect = Rect2(0.0, 0.0, bg_width / bg_sprite.scale.x, (bottom_y - bg_top) / bg_sprite.scale.y)

	var wall_top := -float(target_floor) * FLOOR_HEIGHT - 400.0
	var wall_height := bottom_y - wall_top
	var wall_center_y := (wall_top + bottom_y) / 2.0

	left_shape.size = Vector2(40.0, wall_height)
	left_wall.position = Vector2(-20.0, wall_center_y)

	right_shape.size = Vector2(40.0, wall_height)
	right_wall.position = Vector2(PLAY_WIDTH + 20.0, wall_center_y)

	var i := bands_generated_up_to + 5
	while i <= target_floor:
		var band := ColorRect.new()
		band.color = Color(1, 1, 1, 0.03)
		band.size = Vector2(bg_width, FLOOR_HEIGHT * 2.5)
		band.position = Vector2(PLAY_WIDTH / 2.0 - bg_width / 2.0, -float(i) * FLOOR_HEIGHT - FLOOR_HEIGHT * 2.5)
		band.z_index = -9
		world.add_child(band)
		bands_generated_up_to = i
		i += 5

func _spawn_player() -> void:
	player = Player.new()
	player.position = Vector2(PLAY_WIDTH / 2.0, -80.0)
	sub_viewport.add_child(player)
	# 階数制限なしのため、カメラの上限はごく大きな値にして実質無制限にする
	player.set_camera_limits(-20.0, PLAY_WIDTH + 20.0, -100_000_000.0, 150.0)
	player.stomped_enemy.connect(func() -> void: _add_chat_message(CHAT_ON_STOMP.pick_random()))

# ---------------------------------------------------------------------------
# 進行判定（通常進行・階層到達ボーナス・降下・落下・先読み生成）
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_instance_valid(player) or GameState.won:
		return

	var y := player.global_position.y

	if y < max_height_y:
		max_height_y = y
		var new_floor: int = int(floor((0.0 - max_height_y) / FLOOR_HEIGHT))
		while reached_floor < new_floor:
			reached_floor += 1
			GameState.add_subscribers(FLOOR_BONUS, "登頂中")
			if reached_floor % CHECKPOINT_INTERVAL == 0:
				GameState.add_subscribers(CHECKPOINT_BONUS, "階層到達ボーナス!")
			floor_label.text = "現在 %d 階" % reached_floor

		if reached_floor + GENERATE_AHEAD > generated_floor:
			_extend_tower(generated_floor + GENERATE_BATCH)

	# 「落下」に特殊なテレポート判定は設けない。物理挙動のまま一番下まで自然に落下させる。
	# 最高到達点から離れた状態が続いたら、まとめて一度だけ減点して基準点をその場に
	# リセットする（＝自動減少はそこで止まる。さらに離れれば再度減点される）。
	var depth_below_best := y - max_height_y
	if depth_below_best > DESCEND_THRESHOLD:
		descend_timer += delta
		if descend_timer > DESCEND_GRACE:
			var floors_fallen := depth_below_best / FLOOR_HEIGHT
			var ratio: float = clamp(floors_fallen * DESCEND_PENALTY_RATIO_PER_FLOOR, DESCEND_PENALTY_MIN_RATIO, DESCEND_PENALTY_MAX_RATIO)
			GameState.lose_subscribers(GameState.subscriber_count * ratio, "降下")
			max_height_y = y
			descend_timer = 0.0
	else:
		descend_timer = 0.0

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
	floor_label.text = "現在 0 階"
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
	var available: Array = CHAT_USERNAMES.filter(func(u: Dictionary) -> bool:
		return reached_floor >= int(u["unlock_floor"])
	)
	var user: Dictionary = available.pick_random()
	_add_chat_line(user["name"], user["color"], text)

func _random_new_commenter_name() -> String:
	var prefix: String = NEW_COMMENTER_PREFIXES.pick_random()
	var noun: String = NEW_COMMENTER_NOUNS.pick_random()
	return "%s%s" % [prefix, noun]

func _add_new_subscriber_comment() -> void:
	var commenter_name := _random_new_commenter_name()
	var msg: String = NEW_SUBSCRIBER_MESSAGES.pick_random()
	_add_chat_line(commenter_name, NEW_COMMENTER_COLOR, "🔔" + msg)

func _add_chat_line(user_name: String, color: Color, text: String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(CHAT_WIDTH - 24.0, 0)
	var color_hex := color.to_html(false)
	line.text = "[color=#%s]%s[/color]: %s" % [color_hex, user_name, text]
	line.add_theme_font_size_override("normal_font_size", 13)

	# コメントをクリックすると削除できる（種類を問わず全コメント共通）。
	# 一旦は分かりやすいUI演出は付けず、押すと文言が置き換わるだけの簡易実装。
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	line.gui_input.connect(_on_chat_line_gui_input.bind(line))

	chat_vbox.add_child(line)

	if chat_vbox.get_child_count() > 40:
		var oldest := chat_vbox.get_child(0)
		chat_vbox.remove_child(oldest)
		oldest.queue_free()

	call_deferred("_scroll_chat_to_bottom")

func _on_chat_line_gui_input(event: InputEvent, line: RichTextLabel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if line.get_meta("deleted", false):
			return
		line.set_meta("deleted", true)
		line.text = "[color=#777777](このコメントは削除されました)[/color]"

func _scroll_chat_to_bottom() -> void:
	chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func _on_subscriber_changed(total: int, delta: int, reason: String) -> void:
	sub_label.text = "%s　登録者数 %s人 / 目標 100,000,000人" % [STREAM_TITLE, _format_number(total)]
	progress.value = total
	if abs(delta) >= POPUP_MIN_DELTA:
		_spawn_popup(delta, reason)
	match reason:
		"登頂中", "階層到達ボーナス!", "財宝入手":
			# 登録者数が増えるたびに、新しい視聴者が登録コメントを投稿する演出
			_add_new_subscriber_comment()
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
	# 演出は配信画面（動画エリア）の中だけで完結させる。チャット・下部バーは隠さない
	win_overlay = Control.new()
	win_overlay.position = Vector2.ZERO
	win_overlay.size = Vector2(VIDEO_WIDTH, VIDEO_HEIGHT)
	win_overlay.clip_contents = true
	win_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_overlay.visible = false
	ui_root.add_child(win_overlay)

	win_flash = ColorRect.new()
	win_flash.color = Color(1.0, 0.9, 0.3, 0.0)
	win_flash.size = Vector2(VIDEO_WIDTH, VIDEO_HEIGHT)
	win_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_overlay.add_child(win_flash)

	win_title_label = Label.new()
	win_title_label.text = "登録者数 1億人 達成！！"
	win_title_label.add_theme_font_size_override("font_size", 28)
	win_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	win_title_label.size = Vector2(VIDEO_WIDTH, 40)
	win_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_title_label.position = Vector2(0, VIDEO_HEIGHT / 2.0 - 70.0)
	win_title_label.pivot_offset = Vector2(VIDEO_WIDTH / 2.0, 20.0)
	win_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_overlay.add_child(win_title_label)

	var btn := Button.new()
	btn.text = "もう一度プレイ"
	btn.custom_minimum_size = Vector2(160, 40)
	btn.position = Vector2(VIDEO_WIDTH / 2.0 - 80.0, VIDEO_HEIGHT / 2.0 + 10.0)
	btn.pressed.connect(_on_restart_pressed)
	win_overlay.add_child(btn)

	clear_sfx = AudioStreamPlayer.new()
	clear_sfx.stream = preload("res://assets/clear.mp3")
	add_child(clear_sfx)

	win_chat_timer = Timer.new()
	win_chat_timer.one_shot = false
	win_chat_timer.wait_time = 0.06
	win_chat_timer.timeout.connect(func() -> void: _add_chat_message(CHAT_WIN_MESSAGES.pick_random()))
	add_child(win_chat_timer)

func _on_game_won() -> void:
	win_overlay.visible = true
	clear_sfx.play()

	chat_timer.stop()
	win_chat_timer.start()

	var flash_tw := create_tween()
	flash_tw.set_loops()
	flash_tw.tween_property(win_flash, "color:a", 0.4, 0.12)
	flash_tw.tween_property(win_flash, "color:a", 0.0, 0.35)

	var title_tw := create_tween()
	title_tw.set_loops()
	title_tw.tween_property(win_title_label, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_SINE)
	title_tw.tween_property(win_title_label, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_SINE)

	var confetti_timer := Timer.new()
	confetti_timer.one_shot = false
	confetti_timer.wait_time = 0.1
	confetti_timer.timeout.connect(_spawn_win_confetti)
	add_child(confetti_timer)
	confetti_timer.start()

func _spawn_win_confetti() -> void:
	var glyphs := ["🎉", "✨", "💰", "🎊", "⭐"]
	var lbl := Label.new()
	lbl.text = glyphs.pick_random()
	lbl.add_theme_font_size_override("font_size", randi_range(18, 32))
	lbl.position = Vector2(randf_range(0.0, VIDEO_WIDTH), VIDEO_HEIGHT + 20.0)
	win_overlay.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", -40.0, randf_range(1.2, 2.2))
	tw.tween_property(lbl, "rotation", randf_range(-TAU, TAU), 1.6)
	tw.chain().tween_callback(lbl.queue_free)

func _on_restart_pressed() -> void:
	GameState.reset()
	get_tree().reload_current_scene()
