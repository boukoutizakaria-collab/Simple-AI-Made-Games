extends Node2D
## ============================================================
##  KI CLASH   -   v1.4  "RIVALS UPDATE"
##  1v1 ki-blast arena fighter  |  Godot 4.2.x  |  100% GDScript
##  Graphics = _draw()    Sounds + music = generated in code
##  ZERO external assets
##
##  NEW: local 2-player mode! Press TAB on the menu to switch
##  between VS AI and VS PLAYER 2.
##
##  PLAYER 1          ARROWS move/jump    DOWN block   dbl-tap L/R dash
##                    SPACE blast   S special   SHIFT swap   Q ULTIMATE
##  PLAYER 2 (2P)     A/D move   W jump   X block   dbl-tap A/D dash
##                    F blast   G special   H swap   J ULTIMATE
##  BOTH              P pause   M music on/off   ESC menu
## ============================================================

const W := 1280.0
const H := 720.0
const GROUND := 640.0
const GRAVITY := 2000.0
const SKILL_TIME := 10.0
const RATE := 22050
const MAX_HP := 1000.0
const ROUNDS_TO_WIN := 2

const DASH_SPEED := 1100.0
const DASH_TIME := 0.16
const DASH_CD := 0.55
const IFRAME_DASH := 0.14
const COMBO_WINDOW := 1.1

const SUPER_CHARGES_NEEDED := 3
const QTE_COUNT := 3
const QTE_SHRINK_BASE := 1.05
const QTE_R_START := 120.0
const QTE_TARGET_R := 46.0
const QTE_TOL := 20.0

enum State { MENU, INTRO, FIGHT, ROUND_END, MATCH_END, PAUSE, SUPER }

var DIFFS := [
	{"name": "EASY", "enemy_hp": 950.0, "react": 0.6, "shoot": 1.4, "speed": 0.7, "dodge": 0.10, "special": 0.15, "dmg": 0.8, "block": 0.05, "qte_pace": 1.35, "col": Color(0.4, 1.0, 0.5)},
	{"name": "NORMAL", "enemy_hp": 1300.0, "react": 0.35, "shoot": 0.9, "speed": 0.9, "dodge": 0.35, "special": 0.30, "dmg": 1.0, "block": 0.15, "qte_pace": 1.0, "col": Color(1.0, 0.9, 0.3)},
	{"name": "HARD", "enemy_hp": 1650.0, "react": 0.2, "shoot": 0.6, "speed": 1.05, "dodge": 0.60, "special": 0.50, "dmg": 1.1, "block": 0.30, "qte_pace": 0.8, "col": Color(1.0, 0.55, 0.2)},
	{"name": "INSANE", "enemy_hp": 2000.0, "react": 0.1, "shoot": 0.4, "speed": 1.2, "dodge": 0.85, "special": 0.80, "dmg": 1.25, "block": 0.45, "qte_pace": 0.65, "col": Color(1.0, 0.2, 0.3)},
]
const SKILL_NAMES := ["MEGA BEAM", "HOMING BARRAGE"]


class Fighter:
	var title := ""
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var face := 1
	var hp := 1000.0
	var max_hp := 1000.0
	var disp_hp := 1000.0
	var on_ground := true
	var shoot_cd := 0.0
	var skill_timer := 0.0
	var skill_sel := 0
	var pending := -1
	var cast := 0.0
	var pose_t := 0.0
	var hit_flash := 0.0
	var stun := 0.0
	var ko_t := 0.0
	var anim := 0.0
	var wins := 0
	var color := Color.WHITE
	var hair := Color.WHITE
	var aura := Color.WHITE
	var dmg_mult := 1.0
	var speed_mult := 1.0
	var ai_think := 0.0
	var ai_move := 0
	var ai_shoot_t := 1.0
	# v1.1
	var dash_t := 0.0
	var dash_cd := 0.0
	var iframe := 0.0
	var blocking := false
	var tap_dir := 0
	var tap_time := -10.0
	var combo := 0
	var combo_last := -10.0
	var took_damage := false
	var ai_block_t := 0.0
	# v1.2
	var super_charges := 0
	var ult_name := ""


var player: Fighter
var enemy: Fighter
var winner: Fighter = null
var projectiles: Array = []
var particles: Array = []
var rings: Array = []
var texts: Array = []
var state: int = State.MENU
var state_t := 0.0
var round_num := 1
var diff_idx := 1
var shake := 0.0
var cur_off := Vector2.ZERO
var flash := 0.0
var time := 0.0
var fight_msg_t := 0.0
var hitstop := 0.0
var sfx := {}
var sfx_players: Array = []
var sfx_idx := 0
var music: AudioStreamPlayer
var stars: Array = []
var peaks_far := PackedVector2Array()
var peaks_near := PackedVector2Array()
var font: Font
var _fc := 1.0

# v1.3 - Ultimate cutscene state
var super_performer: Fighter = null
var super_target: Fighter = null
var super_phase := 0  # 0 windup, 1 QTE, 2 combo flurry, 3 result, 4 outro
var super_t := 0.0
var qte_seq: Array = []
var qte_idx := 0
var qte_timer := 0.0
var qte_hits := 0
var qte_results: Array = []
var super_grade := ""
var letterbox := 0.0
var cam_zoom := 1.0
var pending_ko: Fighter = null
# flurry (combo + big blast) sub-state
var flurry_attacker: Fighter = null
var flurry_defender: Fighter = null
var flurry_count := 0
var flurry_idx := 0
var flurry_timer := 0.0
var flurry_each := 0.0
var flurry_big := 0.0
var flurry_total := 0.0
var qte_shrink_time := QTE_SHRINK_BASE
# visible combo cutscene FX
var flurry_lunge := 0.0
var big_blast_t := 0.0
var big_blast_from := Vector2.ZERO
var big_blast_to := Vector2.ZERO
var big_blast_col := Color.WHITE
# v1.4 - local 2-player mode
var vs_mode := 0  # 0 = vs AI, 1 = vs local Player 2
var qte_scheme := 0  # 0 = arrow keys, 1 = WASD (whoever is acting in the QTE)


# ------------------------------------------------------------
#  SETUP
# ------------------------------------------------------------
func _ready() -> void:
	randomize()
	font = ThemeDB.fallback_font
	get_window().title = "KI CLASH"
	_build_audio()
	_build_scenery()
	player = _make_fighter("YOU", Color(0.2, 0.45, 1.0), Color(1.0, 0.85, 0.2), Color(0.3, 0.85, 1.0))
	enemy = _make_fighter("AI", Color(0.8, 0.15, 0.2), Color(0.92, 0.95, 1.0), Color(1.0, 0.25, 0.35))
	player.ult_name = "DRAGON ASCENSION"
	enemy.ult_name = "ABYSSAL ANNIHILATION"
	reset_fighter(player, 300.0, 1, MAX_HP)
	reset_fighter(enemy, W - 300.0, -1, DIFFS[diff_idx]["enemy_hp"])


func _make_fighter(t: String, gi: Color, hair: Color, aura: Color) -> Fighter:
	var f := Fighter.new()
	f.title = t
	f.color = gi
	f.hair = hair
	f.aura = aura
	return f


func reset_fighter(f: Fighter, x: float, face: int, hp_max: float) -> void:
	f.pos = Vector2(x, GROUND)
	f.vel = Vector2.ZERO
	f.face = face
	f.max_hp = hp_max
	f.hp = f.max_hp
	f.disp_hp = f.max_hp
	f.on_ground = true
	f.shoot_cd = 0.5
	f.skill_timer = 4.0
	f.skill_sel = 0
	f.pending = -1
	f.cast = 0.0
	f.pose_t = 0.0
	f.hit_flash = 0.0
	f.stun = 0.0
	f.ko_t = 0.0
	f.ai_think = 0.5
	f.ai_shoot_t = 1.0
	f.dash_t = 0.0
	f.dash_cd = 0.0
	f.iframe = 0.0
	f.blocking = false
	f.tap_dir = 0
	f.tap_time = -10.0
	f.combo = 0
	f.combo_last = -10.0
	f.took_damage = false
	f.ai_block_t = 0.0
	f.super_charges = 0


func _build_scenery() -> void:
	for i in 90:
		stars.append(Vector3(randf() * W, randf() * 320.0, randf() * TAU))
	var x := -40.0
	while x <= W + 80.0:
		peaks_far.append(Vector2(x, randf_range(380.0, 470.0)))
		x += 90.0
	peaks_far.append(Vector2(W + 80.0, GROUND))
	peaks_far.append(Vector2(-40.0, GROUND))
	x = -40.0
	while x <= W + 80.0:
		peaks_near.append(Vector2(x, randf_range(470.0, 550.0)))
		x += 70.0
	peaks_near.append(Vector2(W + 80.0, GROUND))
	peaks_near.append(Vector2(-40.0, GROUND))


# ------------------------------------------------------------
#  AUDIO  (everything synthesized at startup)
# ------------------------------------------------------------
func _build_audio() -> void:
	sfx["shoot"] = to_wav(tone(1100.0, 420.0, 0.14, 0.30, 0.08, 1))
	sfx["hit"] = to_wav(tone(220.0, 70.0, 0.14, 0.60, 0.55, 0))
	sfx["bighit"] = to_wav(tone(160.0, 40.0, 0.38, 0.85, 0.60, 0))
	sfx["charge"] = to_wav(tone(180.0, 1100.0, 0.5, 0.25, 0.05, 2))
	sfx["beam"] = to_wav(tone(520.0, 60.0, 0.7, 0.55, 0.30, 2))
	sfx["barrage"] = to_wav(tone(900.0, 300.0, 0.3, 0.40, 0.10, 1))
	sfx["switch"] = to_wav(tone(500.0, 900.0, 0.07, 0.35, 0.0, 1))
	sfx["tick"] = to_wav(tone(700.0, 700.0, 0.04, 0.30, 0.0, 1))
	sfx["denied"] = to_wav(tone(180.0, 120.0, 0.12, 0.30, 0.0, 1))
	sfx["jump"] = to_wav(tone(250.0, 620.0, 0.12, 0.25, 0.0, 3))
	sfx["clash"] = to_wav(tone(2000.0, 800.0, 0.1, 0.30, 0.70, 0))
	sfx["ko"] = to_wav(tone(700.0, 40.0, 1.0, 0.70, 0.35, 2))
	sfx["fight"] = to_wav(tone(110.0, 330.0, 0.35, 0.60, 0.15, 1))
	sfx["block"] = to_wav(tone(320.0, 150.0, 0.12, 0.45, 0.35, 0))
	sfx["dash"] = to_wav(tone(950.0, 180.0, 0.13, 0.30, 0.55, 1))
	sfx["pause"] = to_wav(tone(500.0, 500.0, 0.08, 0.30, 0.0, 1))
	var qh := tone(1400.0, 1400.0, 0.08, 0.40, 0.0, 3)
	sfx["qte_hit"] = to_wav(qh)
	var sup := tone(80.0, 900.0, 0.6, 0.45, 0.2, 2)
	sfx["super_start"] = to_wav(sup)
	var rdy := tone(700.0, 700.0, 0.09, 0.35, 0.0, 3)
	rdy.append_array(tone(1050.0, 1050.0, 0.18, 0.35, 0.0, 3))
	sfx["ready"] = to_wav(rdy)
	var perf := tone(800.0, 800.0, 0.1, 0.4, 0.0, 3)
	perf.append_array(tone(1100.0, 1100.0, 0.1, 0.4, 0.0, 3))
	perf.append_array(tone(1500.0, 1500.0, 0.3, 0.4, 0.0, 3))
	sfx["perfect"] = to_wav(perf)
	var win := PackedFloat32Array()
	for fq in [523.0, 659.0, 784.0, 1047.0]:
		win.append_array(tone(fq, fq, 0.15, 0.40, 0.0, 3))
	win.append_array(tone(1047.0, 1047.0, 0.5, 0.40, 0.0, 3))
	sfx["win"] = to_wav(win)
	var lose := PackedFloat32Array()
	for fq in [392.0, 349.0, 330.0, 262.0]:
		lose.append_array(tone(fq, fq * 0.98, 0.25, 0.35, 0.0, 2))
	sfx["lose"] = to_wav(lose)

	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)

	music = AudioStreamPlayer.new()
	add_child(music)
	music.stream = to_wav(make_music(), true)
	music.volume_db = -13.0
	music.play()


func wave_at(ph: float, w: int) -> float:
	match w:
		1:
			return 1.0 if sin(ph) > 0.0 else -1.0
		2:
			return fposmod(ph / TAU, 1.0) * 2.0 - 1.0
		3:
			return absf(fposmod(ph / TAU, 1.0) * 4.0 - 2.0) - 1.0
	return sin(ph)


func tone(f0: float, f1: float, dur: float, vol: float, noise := 0.0, wave := 0) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		ph += TAU * lerpf(f0, f1, t) / float(RATE)
		var s := wave_at(ph, wave)
		if noise > 0.0:
			s = lerpf(s, randf_range(-1.0, 1.0), noise)
		var env := pow(1.0 - t, 1.5) * minf(1.0, float(i) / 120.0)
		out[i] = s * vol * env
	return out


func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int) -> PackedFloat32Array:
	for i in src.size():
		if offset + i >= dst.size():
			break
		dst[offset + i] += src[i]
	return dst


func to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func make_music() -> PackedFloat32Array:
	var step := 0.15
	var step_n := int(RATE * step)
	var steps := 16
	var m := PackedFloat32Array()
	m.resize(step_n * steps)
	var roots := [110.0, 87.31, 98.0, 82.41]
	var arp := [
		[220.0, 261.6, 329.6, 261.6],
		[174.6, 220.0, 261.6, 220.0],
		[196.0, 247.0, 293.7, 247.0],
		[164.8, 207.7, 246.9, 207.7],
	]
	for s in steps:
		var chord: int = s >> 2
		var root: float = roots[chord]
		var bf: float = root * 2.0 if (s % 4) == 2 else root
		m = mix_into(m, tone(bf, bf, step * 0.9, 0.20, 0.0, 1), s * step_n)
		var a: float = arp[chord][s % 4]
		m = mix_into(m, tone(a, a, step * 0.8, 0.07, 0.0, 3), s * step_n)
		if s % 4 == 0:
			m = mix_into(m, tone(140.0, 40.0, 0.14, 0.40, 0.0, 0), s * step_n)
		if s % 8 == 4:
			m = mix_into(m, tone(200.0, 150.0, 0.12, 0.22, 0.8, 0), s * step_n)
		if s % 2 == 1:
			m = mix_into(m, tone(6000.0, 6000.0, 0.04, 0.10, 0.9, 0), s * step_n)
	return m


func play_sfx(n: String, db := -4.0) -> void:
	var p: AudioStreamPlayer = sfx_players[sfx_idx]
	sfx_idx = (sfx_idx + 1) % sfx_players.size()
	p.stream = sfx[n]
	p.volume_db = db
	p.play()


# ------------------------------------------------------------
#  INPUT (one-shot keys)
# ------------------------------------------------------------
func _input(event: InputEvent) -> void:
	var ev := event as InputEventKey
	if ev == null or not ev.pressed or ev.echo:
		return
	var k: int = ev.physical_keycode
	if k == KEY_M:
		music.stream_paused = not music.stream_paused
		return
	var confirm := k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE
	match state:
		State.MENU:
			if k == KEY_TAB:
				vs_mode = 1 - vs_mode
				play_sfx("switch")
			elif k == KEY_UP or k == KEY_LEFT:
				diff_idx = (diff_idx + DIFFS.size() - 1) % DIFFS.size()
				play_sfx("tick")
			elif k == KEY_DOWN or k == KEY_RIGHT:
				diff_idx = (diff_idx + 1) % DIFFS.size()
				play_sfx("tick")
			elif confirm:
				start_match()
			elif k == KEY_ESCAPE:
				get_tree().quit()
		State.FIGHT:
			if k == KEY_SHIFT:
				player.skill_sel = 1 - player.skill_sel
				play_sfx("switch")
			elif k == KEY_S:
				use_skill(player)
			elif k == KEY_Q:
				try_trigger_super(player)
			elif k == KEY_LEFT:
				try_dash_input(-1)
			elif k == KEY_RIGHT:
				try_dash_input(1)
			elif k == KEY_P:
				state = State.PAUSE
				play_sfx("pause")
			elif k == KEY_ESCAPE:
				to_menu()
			elif vs_mode == 1 and k == KEY_H:
				enemy.skill_sel = 1 - enemy.skill_sel
				play_sfx("switch")
			elif vs_mode == 1 and k == KEY_G:
				use_skill(enemy)
			elif vs_mode == 1 and k == KEY_J:
				try_trigger_super(enemy)
			elif vs_mode == 1 and k == KEY_A:
				try_dash_input2(-1)
			elif vs_mode == 1 and k == KEY_D:
				try_dash_input2(1)
		State.SUPER:
			if super_phase == 1:
				var dirv := key_to_dir(k)
				if dirv >= 0:
					handle_qte_press(dirv)
		State.PAUSE:
			if k == KEY_P:
				state = State.FIGHT
				play_sfx("pause")
			elif k == KEY_ESCAPE:
				to_menu()
		State.INTRO, State.ROUND_END:
			if k == KEY_ESCAPE:
				to_menu()
		State.MATCH_END:
			if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_ESCAPE:
				to_menu()


func try_dash_input(dir: int) -> void:
	if state != State.FIGHT:
		return
	var f := player
	if dir == f.tap_dir and (time - f.tap_time) < 0.28:
		start_dash(f, dir)
		f.tap_dir = 0
		f.tap_time = -10.0
	else:
		f.tap_dir = dir
		f.tap_time = time


func try_dash_input2(dir: int) -> void:
	if state != State.FIGHT or vs_mode != 1:
		return
	var f := enemy
	if dir == f.tap_dir and (time - f.tap_time) < 0.28:
		start_dash(f, dir)
		f.tap_dir = 0
		f.tap_time = -10.0
	else:
		f.tap_dir = dir
		f.tap_time = time


# Maps a physical key to an abstract QTE direction (0=up,1=down,2=left,3=right)
# under whichever scheme is currently active - arrows or WASD. Keys outside
# the active scheme simply don't match, so the two players never interfere.
func key_to_dir(k: int) -> int:
	if qte_scheme == 0:
		match k:
			KEY_UP:
				return 0
			KEY_DOWN:
				return 1
			KEY_LEFT:
				return 2
			KEY_RIGHT:
				return 3
	else:
		match k:
			KEY_W:
				return 0
			KEY_S:
				return 1
			KEY_A:
				return 2
			KEY_D:
				return 3
	return -1


func start_dash(f: Fighter, dir: int) -> void:
	if f.dash_cd > 0.0 or f.stun > 0.0 or f.cast > 0.0 or f.hp <= 0.0 or f.blocking:
		return
	f.dash_t = DASH_TIME
	f.dash_cd = DASH_CD
	f.vel.x = float(dir) * DASH_SPEED
	f.iframe = IFRAME_DASH
	play_sfx("dash", -6.0)


# ------------------------------------------------------------
#  GAME FLOW
# ------------------------------------------------------------
func to_menu() -> void:
	state = State.MENU
	projectiles.clear()
	particles.clear()
	rings.clear()
	texts.clear()
	letterbox = 0.0
	cam_zoom = 1.0
	pending_ko = null
	super_performer = null
	super_target = null
	reset_fighter(player, 300.0, 1, MAX_HP)
	reset_fighter(enemy, W - 300.0, -1, MAX_HP if vs_mode == 1 else DIFFS[diff_idx]["enemy_hp"])
	play_sfx("tick")


func start_match() -> void:
	var df: Dictionary = DIFFS[diff_idx]
	player.wins = 0
	enemy.wins = 0
	if vs_mode == 1:
		enemy.dmg_mult = 1.0
		enemy.speed_mult = 1.0
		enemy.title = "PLAYER 2"
		player.title = "PLAYER 1"
	else:
		enemy.dmg_mult = df["dmg"]
		enemy.speed_mult = df["speed"]
		enemy.title = "AI - " + str(df["name"])
		player.title = "YOU"
	round_num = 1
	start_round()


func start_round() -> void:
	var df: Dictionary = DIFFS[diff_idx]
	reset_fighter(player, 300.0, 1, MAX_HP)
	reset_fighter(enemy, W - 300.0, -1, MAX_HP if vs_mode == 1 else df["enemy_hp"])
	projectiles.clear()
	particles.clear()
	rings.clear()
	texts.clear()
	letterbox = 0.0
	cam_zoom = 1.0
	pending_ko = null
	state = State.INTRO
	state_t = 2.0
	play_sfx("ready")


func ko(loser: Fighter) -> void:
	winner = enemy if loser == player else player
	winner.wins += 1
	state = State.ROUND_END
	state_t = 1.1
	flash = 0.9
	shake = 22.0
	play_sfx("ko")
	burst(loser.pos + Vector2(0, -60), loser.aura, 50, 520.0, 7.0)
	add_ring(loser.pos + Vector2(0, -60), Color.WHITE)
	if not winner.took_damage:
		add_text(winner.pos + Vector2(0, -215), "PERFECT!", Color(1.0, 0.95, 0.3), 34)
		play_sfx("perfect", -3.0)


func _physics_process(delta: float) -> void:
	if state == State.PAUSE:
		queue_redraw()
		return
	if hitstop > 0.0:
		hitstop -= delta
		queue_redraw()
		return

	time += delta
	var d := delta * (0.35 if state == State.ROUND_END else 1.0)
	shake = maxf(0.0, shake - 50.0 * delta)
	cur_off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	flash = maxf(0.0, flash - 2.5 * delta)
	fight_msg_t = maxf(0.0, fight_msg_t - delta)

	match state:
		State.MENU:
			update_fighter(player, enemy, d)
			update_fighter(enemy, player, d)
		State.INTRO:
			update_fighter(player, enemy, d)
			update_fighter(enemy, player, d)
			state_t -= d
			if state_t <= 0.0:
				state = State.FIGHT
				fight_msg_t = 0.7
				play_sfx("fight")
		State.FIGHT:
			control_player()
			if vs_mode == 1:
				control_player2()
			else:
				control_ai(d)
			update_fighter(player, enemy, d)
			update_fighter(enemy, player, d)
			separate()
			update_projectiles(d)
		State.SUPER:
			update_super(d)
		State.ROUND_END:
			update_fighter(player, enemy, d)
			update_fighter(enemy, player, d)
			update_projectiles(d)
			state_t -= d
			if state_t <= 0.0:
				if winner.wins >= ROUNDS_TO_WIN:
					state = State.MATCH_END
					play_sfx("win" if winner == player else "lose")
				else:
					round_num += 1
					start_round()
		State.MATCH_END:
			update_fighter(player, enemy, d)
			update_fighter(enemy, player, d)
	var fx_d := d * (0.6 if state == State.SUPER else 1.0)
	update_fx(fx_d)
	queue_redraw()


# ------------------------------------------------------------
#  FIGHTER LOGIC
# ------------------------------------------------------------
func update_fighter(f: Fighter, other: Fighter, d: float) -> void:
	if state != State.FIGHT:
		f.blocking = false
	f.anim += d
	if f.hp > 0.0:
		f.face = 1 if other.pos.x >= f.pos.x else -1
	else:
		f.ko_t += d
	f.shoot_cd = maxf(0.0, f.shoot_cd - d)
	f.hit_flash = maxf(0.0, f.hit_flash - d)
	f.stun = maxf(0.0, f.stun - d)
	f.pose_t = maxf(0.0, f.pose_t - d)
	f.dash_cd = maxf(0.0, f.dash_cd - d)
	f.iframe = maxf(0.0, f.iframe - d)
	if f.dash_t > 0.0:
		f.dash_t = maxf(0.0, f.dash_t - d)
		add_particle(f.pos + Vector2(randf_range(-10.0, 10.0), -60.0 + randf_range(-20.0, 20.0)), Vector2(-f.vel.x * 0.25, 0.0), 0.22, f.aura, 8.0)
	if f.cast > 0.0:
		f.cast -= d
		charge_fx(f)
		charge_fx(f)
		if f.cast <= 0.0 and f.pending >= 0:
			fire_skill(f)
	if state == State.FIGHT and f.hp > 0.0:
		var before := f.skill_timer
		f.skill_timer = minf(SKILL_TIME, f.skill_timer + d)
		if before < SKILL_TIME and f.skill_timer >= SKILL_TIME and f == player:
			play_sfx("ready")
	f.disp_hp = move_toward(f.disp_hp, f.hp, 35.0 * d)
	if not f.on_ground:
		f.vel.y += GRAVITY * d
	f.pos += f.vel * d
	f.pos.x = clampf(f.pos.x, 40.0, W - 40.0)
	if f.pos.y >= GROUND and f.vel.y >= 0.0:
		f.pos.y = GROUND
		f.vel.y = 0.0
		f.on_ground = true
	if state != State.FIGHT or f.stun > 0.0 or f.hp <= 0.0 or f.cast > 0.0:
		f.vel.x = move_toward(f.vel.x, 0.0, 1400.0 * d)


func separate() -> void:
	var dx := enemy.pos.x - player.pos.x
	if absf(dx) < 46.0 and absf(enemy.pos.y - player.pos.y) < 90.0:
		var push := (46.0 - absf(dx)) * 0.5
		var s := 1.0 if dx >= 0.0 else -1.0
		player.pos.x -= s * push
		enemy.pos.x += s * push


func jump(f: Fighter) -> void:
	if not f.on_ground or f.stun > 0.0 or f.cast > 0.0 or f.blocking:
		return
	f.vel.y = -860.0
	f.on_ground = false
	play_sfx("jump", -10.0)


func control_player() -> void:
	var p := player
	if p.stun > 0.0 or p.cast > 0.0:
		p.blocking = false
		return
	if p.dash_t > 0.0:
		return
	var blocking_now := Input.is_physical_key_pressed(KEY_DOWN) and p.on_ground
	p.blocking = blocking_now
	if blocking_now:
		p.vel.x = 0.0
		return
	var dir := 0
	if Input.is_physical_key_pressed(KEY_LEFT):
		dir -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT):
		dir += 1
	p.vel.x = dir * 340.0
	if Input.is_physical_key_pressed(KEY_UP):
		jump(p)
	if Input.is_physical_key_pressed(KEY_SPACE):
		try_shoot(p)


func control_player2() -> void:
	var p := enemy
	if p.stun > 0.0 or p.cast > 0.0:
		p.blocking = false
		return
	if p.dash_t > 0.0:
		return
	var blocking_now := Input.is_physical_key_pressed(KEY_X) and p.on_ground
	p.blocking = blocking_now
	if blocking_now:
		p.vel.x = 0.0
		return
	var dir := 0
	if Input.is_physical_key_pressed(KEY_A):
		dir -= 1
	if Input.is_physical_key_pressed(KEY_D):
		dir += 1
	p.vel.x = dir * 340.0
	if Input.is_physical_key_pressed(KEY_W):
		jump(p)
	if Input.is_physical_key_pressed(KEY_F):
		try_shoot(p)


func try_shoot(f: Fighter) -> bool:
	if f.shoot_cd > 0.0 or f.stun > 0.0 or f.cast > 0.0 or f.hp <= 0.0 or f.blocking:
		return false
	f.shoot_cd = 0.32
	f.pose_t = 0.18
	spawn_proj(f, f.pos + Vector2(f.face * 38.0, -66.0), Vector2(f.face * 780.0, 0.0), 13.0, 5.0 * f.dmg_mult, false, false, 2.0)
	play_sfx("shoot")
	return true


func use_skill(f: Fighter) -> void:
	if state != State.FIGHT or f.hp <= 0.0 or f.stun > 0.0 or f.cast > 0.0 or f.blocking:
		return
	if f.skill_timer < SKILL_TIME:
		if f == player:
			play_sfx("denied")
		return
	f.skill_timer = 0.0
	f.pending = f.skill_sel
	f.cast = 0.55 if f.skill_sel == 0 else 0.4
	f.vel.x = 0.0
	f.super_charges = mini(f.super_charges + 1, SUPER_CHARGES_NEEDED)
	play_sfx("charge")
	add_text(f.pos + Vector2(0, -160), SKILL_NAMES[f.skill_sel], f.aura, 24)
	if f.super_charges >= SUPER_CHARGES_NEEDED and f == player:
		add_text(f.pos + Vector2(0, -190), "ULTIMATE READY!", Color(1.0, 0.9, 0.3), 18)


func fire_skill(f: Fighter) -> void:
	if f.pending == 0:
		spawn_proj(f, f.pos + Vector2(f.face * 40.0, -66.0), Vector2(f.face * 950.0, 0.0), 34.0, 30.0 * f.dmg_mult, true, false, 2.5)
		play_sfx("beam", -2.0)
		shake = maxf(shake, 12.0)
		f.vel.x = -f.face * 220.0
	else:
		for i in 8:
			var a := lerpf(-1.4, -0.15, float(i) / 7.0)
			var dir := Vector2(float(f.face) * cos(a), sin(a))
			spawn_proj(f, f.pos + Vector2(f.face * 20.0, -90.0), dir * 560.0, 11.0, 4.0 * f.dmg_mult, false, true, 3.5)
		play_sfx("barrage")
		shake = maxf(shake, 6.0)
	f.pending = -1
	f.pose_t = 0.4
	add_ring(f.pos + Vector2(f.face * 30.0, -66.0), f.aura)


func spawn_proj(src: Fighter, p: Vector2, v: Vector2, r: float, dmg: float, big: bool, homing: bool, life: float) -> void:
	projectiles.append({"src": src, "pos": p, "vel": v, "r": r, "dmg": dmg, "big": big, "homing": homing, "life": life, "dead": false, "col": src.aura})


func hit_rect(f: Fighter) -> Rect2:
	return Rect2(f.pos.x - 24.0, f.pos.y - 104.0, 48.0, 104.0)


func circle_hits_rect(c: Vector2, r: float, rc: Rect2) -> bool:
	var cx := clampf(c.x, rc.position.x, rc.end.x)
	var cy := clampf(c.y, rc.position.y, rc.end.y)
	return c.distance_squared_to(Vector2(cx, cy)) <= r * r


func update_projectiles(d: float) -> void:
	for pr in projectiles:
		if pr["dead"]:
			continue
		var src: Fighter = pr["src"]
		var tgt: Fighter = enemy if src == player else player
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		var r: float = pr["r"]
		var big: bool = pr["big"]
		var col: Color = pr["col"]

		if pr["homing"] and tgt.hp > 0.0:
			var want: Vector2 = tgt.pos + Vector2(0.0, -55.0) - pos
			var diff: float = vel.angle_to(want)
			vel = vel.rotated(clampf(diff, -3.4 * d, 3.4 * d))
		pos += vel * d
		pr["pos"] = pos
		pr["vel"] = vel
		pr["life"] = float(pr["life"]) - d
		add_particle(pos, Vector2.ZERO, 0.22, col, r * 0.7)

		if pr["life"] <= 0.0 or pos.x < -150.0 or pos.x > W + 150.0 or pos.y < -200.0 or pos.y > GROUND:
			if pos.y > GROUND:
				explode(Vector2(pos.x, GROUND), col, false)
			pr["dead"] = true
			continue

		if state == State.FIGHT and tgt.hp > 0.0 and circle_hits_rect(pos, r, hit_rect(tgt)):
			if tgt.iframe > 0.0:
				add_particle(pos, vel.normalized() * 140.0, 0.2, Color.WHITE, r * 0.6)
				pr["dead"] = true
				continue
			var dir := signf(vel.x)
			if dir == 0.0:
				dir = float(src.face)
			explode(pos, col, big)
			damage(tgt, float(pr["dmg"]), dir, big, src)
			pr["dead"] = true
			continue

		for o in projectiles:
			if o["dead"] or o["src"] == src:
				continue
			var op: Vector2 = o["pos"]
			if pos.distance_to(op) < r + float(o["r"]):
				burst((pos + op) * 0.5, Color.WHITE, 8, 240.0, 4.0)
				play_sfx("clash", -8.0)
				if not big:
					pr["dead"] = true
				if not o["big"]:
					o["dead"] = true
				break
	projectiles = projectiles.filter(func(p): return not p["dead"])


func damage(f: Fighter, amount: float, dir: float, big: bool, src: Fighter = null) -> void:
	if state != State.FIGHT or f.hp <= 0.0:
		return
	var dealt := amount
	if f.blocking:
		dealt = amount * (0.22 if not big else 0.42)
	f.hp = maxf(0.0, f.hp - dealt)
	f.took_damage = true
	f.hit_flash = 0.15
	if f.blocking:
		f.vel.x = dir * 50.0
		play_sfx("block", -5.0)
		add_text(f.pos + Vector2(0, -130), "BLOCK", Color(0.55, 0.8, 1.0), 22)
	else:
		if f.cast <= 0.0:
			f.stun = 0.45 if big else 0.14
			f.vel.x = dir * (480.0 if big else 110.0)
			if big:
				f.vel.y = -380.0
				f.on_ground = false
		play_sfx("bighit" if big else "hit")
		add_text(f.pos + Vector2(0, -130), str(int(dealt)), Color(1.0, 0.95, 0.5), 40 if big else 26)
	shake = maxf(shake, 16.0 if big else 5.0)
	if big:
		flash = maxf(flash, 0.35)
		hitstop = 0.05
	if src != null:
		if not f.blocking:
			if time - src.combo_last < COMBO_WINDOW:
				src.combo += 1
			else:
				src.combo = 1
			src.combo_last = time
			if src.combo >= 2:
				add_text(f.pos + Vector2(0, -175), "%dx COMBO" % src.combo, Color(1.0, 0.5, 0.9), 20 + mini(src.combo, 6) * 2)
		else:
			src.combo = 0
	if f.hp <= 0.0:
		f.vel.x = dir * 300.0
		ko(f)


# ------------------------------------------------------------
#  ULTIMATE / SUPER TECHNIQUE  (QTE cutscene)
# ------------------------------------------------------------
func try_trigger_super(f: Fighter) -> void:
	if state != State.FIGHT:
		return
	var target := enemy if f == player else player
	if f.super_charges < SUPER_CHARGES_NEEDED or f.stun > 0.0 or f.cast > 0.0 or f.blocking or f.hp <= 0.0 or target.hp <= 0.0:
		if f == player or vs_mode == 1:
			play_sfx("denied")
		return
	start_super(f)


func start_super(performer: Fighter) -> void:
	var target := enemy if performer == player else player
	super_performer = performer
	super_target = target
	performer.super_charges = 0
	performer.vel = Vector2.ZERO
	target.vel = Vector2.ZERO
	super_phase = 0
	super_t = 0.0
	qte_idx = 0
	qte_hits = 0
	qte_timer = 0.0
	qte_results.clear()
	qte_seq.clear()
	for i in QTE_COUNT:
		qte_seq.append(randi() % 4)  # 0=up, 1=down, 2=left, 3=right
	qte_scheme = 1 if (vs_mode == 1 and performer == enemy) else 0
	var pace: float = float(DIFFS[1]["qte_pace"]) if vs_mode == 1 else float(DIFFS[diff_idx]["qte_pace"])
	qte_shrink_time = QTE_SHRINK_BASE * pace
	letterbox = 0.0
	cam_zoom = 1.0
	pending_ko = null
	state = State.SUPER
	shake = maxf(shake, 10.0)
	flash = maxf(flash, 0.3)
	play_sfx("super_start", -1.0)


func update_super(d: float) -> void:
	super_t += d
	flurry_lunge = maxf(0.0, flurry_lunge - d * 7.0)
	big_blast_t = maxf(0.0, big_blast_t - d)
	match super_phase:
		0:  # windup - camera zooms in, energy gathers
			letterbox = minf(1.0, letterbox + d / 0.45)
			cam_zoom = lerp(1.0, 1.55, clampf(super_t / 0.6, 0.0, 1.0))
			if randf() < 0.9:
				var ang := randf() * TAU
				var rr := randf_range(140.0, 260.0)
				var p0: Vector2 = super_performer.pos + Vector2(cos(ang), sin(ang)) * rr + Vector2(0.0, -70.0)
				var dirv: Vector2 = (super_performer.pos + Vector2(0.0, -70.0) - p0).normalized() * 420.0
				add_particle(p0, dirv, 0.5, super_performer.aura, 6.0)
			if super_t >= 0.6:
				super_phase = 1
				super_t = 0.0
				qte_timer = 0.0
				play_sfx("ready", -2.0)
		1:  # simple QTE - press the arrow when the ring hits the gold band
			qte_timer += d
			if randf() < 0.6:
				var a2 := randf() * TAU
				add_particle(Vector2(W / 2.0, H * 0.5) + Vector2(cos(a2), sin(a2)) * QTE_TARGET_R, Vector2.ZERO, 0.3, Color.WHITE, 3.0)
			if qte_idx < qte_seq.size() and qte_timer >= qte_shrink_time:
				register_qte_result(false)
		2:  # combo flurry + big blast cutscene - bars gone, full view of the action
			letterbox = maxf(0.0, letterbox - d / 0.2)
			cam_zoom = lerp(cam_zoom, 1.0, d * 8.0)
			flurry_timer -= d
			if flurry_idx < flurry_count:
				if flurry_timer <= 0.0:
					flurry_step()
			elif flurry_timer <= 0.0:
				super_phase = 3
				super_t = 0.0
		3:  # result banner - still a clear, un-letterboxed view
			if super_t >= 1.1:
				super_phase = 4
				super_t = 0.0
		4:  # outro - brief hold before returning control
			if super_t >= 0.3:
				finish_super()


func handle_qte_press(dirv: int) -> void:
	if qte_idx >= qte_seq.size():
		return
	var want: int = qte_seq[qte_idx]
	var radius: float = lerp(QTE_R_START, 0.0, clampf(qte_timer / qte_shrink_time, 0.0, 1.0))
	var in_band := absf(radius - QTE_TARGET_R) <= QTE_TOL
	if dirv == want and in_band:
		register_qte_result(true)
	else:
		register_qte_result(false)


func register_qte_result(hit: bool) -> void:
	qte_results.append(hit)
	if hit:
		qte_hits += 1
		play_sfx("qte_hit", -2.0)
		add_ring(Vector2(W / 2.0, H * 0.5), Color.WHITE)
	else:
		play_sfx("denied", -4.0)
	qte_idx += 1
	qte_timer = 0.0
	if qte_idx >= qte_seq.size():
		begin_flurry()


# Turns the QTE score into a short combo flurry + a big finishing blast.
# performer's own ultimate -> more hits = bigger combo onto the opponent.
# opponent's ultimate -> defend well (2-3 hits) and YOU counter-combo them instead.
func begin_flurry() -> void:
	var hits := qte_hits
	if vs_mode == 1 or super_performer == player:
		# self-executed ultimate: in 2P mode BOTH players always perform their
		# own technique with their own QTE scheme - no AI-style "defend" logic.
		flurry_attacker = super_performer
		flurry_defender = super_target
		var lv := _player_ult_level(hits)
		flurry_count = lv["count"]
		flurry_each = lv["each"] * super_performer.dmg_mult
		flurry_big = lv["big"] * super_performer.dmg_mult
		super_grade = lv["grade"]
	else:
		if hits >= 2:
			# you defended it well - the AI's ultimate simply fails. No damage to anyone.
			flurry_attacker = null
			flurry_defender = null
			flurry_count = 0
			flurry_each = 0.0
			flurry_big = 0.0
			super_grade = "DEFENDED! ULTIMATE FAILED"
			play_sfx("ready", -1.0)
		else:
			flurry_attacker = enemy
			flurry_defender = player
			var lv3 := _ai_ult_level(hits)
			flurry_count = lv3["count"]
			flurry_each = lv3["each"] * enemy.dmg_mult
			flurry_big = lv3["big"] * enemy.dmg_mult
			super_grade = lv3["grade"]
	flurry_idx = 0
	flurry_total = 0.0
	flurry_timer = 0.35
	flurry_lunge = 0.0
	big_blast_t = 0.0
	super_phase = 2
	super_t = 0.0
	if flurry_attacker != null:
		play_sfx("charge", -1.0)


func _player_ult_level(hits: int) -> Dictionary:
	var levels := [
		{"count": 3, "each": 11.0, "big": 45.0, "grade": "WEAK ULTIMATE"},
		{"count": 5, "each": 13.0, "big": 65.0, "grade": "GOOD ULTIMATE"},
		{"count": 7, "each": 15.0, "big": 90.0, "grade": "GREAT ULTIMATE"},
		{"count": 9, "each": 17.0, "big": 130.0, "grade": "PERFECT ULTIMATE!"},
	]
	return levels[clampi(hits, 0, 3)]


func _ai_ult_level(hits: int) -> Dictionary:
	var levels := [
		{"count": 9, "each": 15.0, "big": 115.0, "grade": "ULTIMATE LANDED!"},
		{"count": 5, "each": 10.0, "big": 55.0, "grade": "PARTIALLY BLOCKED"},
	]
	return levels[clampi(hits, 0, 1)]


func flurry_step() -> void:
	var is_big := flurry_idx == flurry_count - 1
	var dmg := flurry_big if is_big else flurry_each
	var atk := flurry_attacker
	var defn := flurry_defender
	var impact_pos: Vector2 = defn.pos + Vector2(0.0, -62.0)
	if defn.hp > 0.0:
		defn.hp = maxf(0.0, defn.hp - dmg)
		defn.took_damage = true
		defn.hit_flash = 0.14
		flurry_total += dmg
		add_text(defn.pos + Vector2(randf_range(-24.0, 24.0), -150.0 - randf_range(0.0, 20.0)), str(int(dmg)), Color(1.0, 0.95, 0.5) if not is_big else Color(1.0, 0.75, 0.2), 30 if is_big else 20)
		if is_big:
			# the huge finishing blast - a real glowing beam fired across the arena
			big_blast_t = 0.45
			big_blast_from = atk.pos + Vector2(atk.face * 24.0, -70.0)
			big_blast_to = defn.pos + Vector2(0.0, -62.0)
			big_blast_col = atk.aura
			burst(impact_pos, atk.aura, 60, 560.0, 10.0)
			burst(impact_pos, Color.WHITE, 24, 420.0, 6.0)
			add_ring(impact_pos, Color.WHITE)
			add_ring(impact_pos, atk.aura)
			play_sfx("beam", -1.0)
			play_sfx("bighit", -1.0)
			shake = maxf(shake, 26.0)
			flash = maxf(flash, 0.65)
			hitstop = 0.07
		else:
			# a visible quick strike: the attacker lunges to the target and snaps back
			flurry_lunge = 1.0
			var start_p: Vector2 = atk.pos + Vector2(0.0, -62.0)
			for t in 6:
				var tt := float(t) / 5.0
				add_particle(start_p.lerp(impact_pos, tt), Vector2.ZERO, 0.14, atk.aura, 6.0 - tt * 2.0)
			burst(impact_pos, atk.aura, 14, 260.0, 5.0)
			burst(impact_pos, Color.WHITE, 6, 180.0, 3.0)
			add_particle(atk.pos + Vector2(atk.face * 10.0, -70.0), Vector2(atk.face * 300.0, -40.0), 0.18, atk.aura, 6.0)
			play_sfx("hit", -6.0)
			shake = maxf(shake, 7.0)
		if defn.hp <= 0.0:
			pending_ko = defn
	flurry_idx += 1
	flurry_timer = 0.55 if is_big else randf_range(0.08, 0.13)


func finish_super() -> void:
	cam_zoom = 1.0
	letterbox = 0.0
	if pending_ko != null:
		var t := pending_ko
		pending_ko = null
		ko(t)
	else:
		state = State.FIGHT
	super_performer = null
	super_target = null
	flurry_attacker = null
	flurry_defender = null


# ------------------------------------------------------------
#  AI
# ------------------------------------------------------------
func control_ai(d: float) -> void:
	var a := enemy
	var df: Dictionary = DIFFS[diff_idx]
	a.ai_block_t = maxf(0.0, a.ai_block_t - d)
	a.blocking = a.ai_block_t > 0.0 and a.on_ground and a.stun <= 0.0 and a.cast <= 0.0
	if a.blocking:
		a.vel.x = 0.0
	a.ai_think -= d
	a.ai_shoot_t -= d
	var desperate := a.hp > 0.0 and a.hp / a.max_hp < 0.3
	var dx := player.pos.x - a.pos.x
	var dist := absf(dx)
	var sgn := 1.0 if dx >= 0.0 else -1.0

	if a.ai_think <= 0.0:
		a.ai_think = float(df["react"]) * (0.6 if desperate else 1.0) * randf_range(0.6, 1.3)
		var pref := 420.0 + randf_range(-100.0, 100.0)
		if dist > pref + 90.0:
			a.ai_move = int(sgn)
		elif dist < pref - 110.0:
			a.ai_move = -int(sgn)
		else:
			a.ai_move = [-1, 0, 0, 1][randi() % 4]

		var threat := false
		for pr in projectiles:
			var src: Fighter = pr["src"]
			if src != player:
				continue
			var pp: Vector2 = pr["pos"]
			var pv: Vector2 = pr["vel"]
			var rel := a.pos.x - pp.x
			if rel * pv.x > 0.0 and absf(rel) < 360.0 and absf(pp.y - (a.pos.y - 55.0)) < 70.0:
				threat = true

		if threat and a.on_ground and not a.blocking:
			var r := randf()
			var blockc: float = float(df.get("block", 0.15))
			if r < blockc:
				a.ai_block_t = 0.4
			elif r < blockc + float(df["dodge"]) and a.dash_cd <= 0.0 and randf() < 0.6:
				start_dash(a, -int(sgn))
			elif randf() < float(df["dodge"]):
				jump(a)
		elif not player.on_ground and a.on_ground and not a.blocking and randf() < 0.25:
			jump(a)
		elif not a.blocking and randf() < 0.05:
			jump(a)

		var special_chance: float = float(df["special"]) * (1.6 if desperate else 1.0)
		if a.skill_timer >= SKILL_TIME and dist > 160.0 and randf() < clampf(special_chance, 0.0, 0.95):
			a.skill_sel = randi() % 2
			use_skill(a)

		if a.super_charges >= SUPER_CHARGES_NEEDED and dist < 700.0 and player.hp > 0.0:
			start_super(a)
			return

	if a.stun <= 0.0 and a.cast <= 0.0 and a.dash_t <= 0.0 and not a.blocking:
		a.vel.x = float(a.ai_move) * 300.0 * a.speed_mult
		var shoot_t: float = float(df["shoot"]) * (0.6 if desperate else 1.0)
		if a.ai_shoot_t <= 0.0 and dist < 950.0 and absf(a.pos.y - player.pos.y) < 70.0:
			if try_shoot(a):
				a.ai_shoot_t = shoot_t * randf_range(0.7, 1.4)


# ------------------------------------------------------------
#  EFFECTS
# ------------------------------------------------------------
func add_particle(p: Vector2, v: Vector2, life: float, col: Color, size: float, g := 0.0) -> void:
	if particles.size() > 700:
		particles.remove_at(0)
	particles.append({"p": p, "v": v, "life": life, "max": life, "col": col, "size": size, "g": g})


func burst(p: Vector2, col: Color, n: int, spd: float, size := 5.0) -> void:
	for i in n:
		var a := randf() * TAU
		add_particle(p, Vector2(cos(a), sin(a)) * spd * randf_range(0.2, 1.0), randf_range(0.25, 0.7), col, size * randf_range(0.5, 1.2), 400.0)


func add_ring(p: Vector2, col: Color) -> void:
	rings.append({"p": p, "r": 10.0, "life": 0.4, "col": col})


func explode(p: Vector2, col: Color, big: bool) -> void:
	burst(p, col, 34 if big else 14, 460.0 if big else 260.0, 7.0 if big else 5.0)
	burst(p, Color.WHITE, 8, 300.0, 3.0)
	add_ring(p, col)


func charge_fx(f: Fighter) -> void:
	var c := f.pos + Vector2(0.0, -60.0)
	var a := randf() * TAU
	var r := randf_range(90.0, 160.0)
	var dir := Vector2(cos(a), sin(a))
	add_particle(c + dir * r, -dir * r * 3.0, 0.33, f.aura, 5.0)


func add_text(p: Vector2, s: String, col: Color, size: int) -> void:
	texts.append({"p": p, "s": s, "col": col, "size": size, "life": 1.0})


func update_fx(d: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p["life"] = float(p["life"]) - d
		if p["life"] <= 0.0:
			particles.remove_at(i)
			continue
		var v: Vector2 = p["v"]
		v.y += float(p["g"]) * d
		p["v"] = v
		p["p"] = Vector2(p["p"]) + v * d
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		r["life"] = float(r["life"]) - d
		r["r"] = float(r["r"]) + 700.0 * d
		if r["life"] <= 0.0:
			rings.remove_at(i)
	for i in range(texts.size() - 1, -1, -1):
		var t: Dictionary = texts[i]
		t["life"] = float(t["life"]) - d
		var tp: Vector2 = t["p"]
		tp.y -= 60.0 * d
		t["p"] = tp
		if t["life"] <= 0.0:
			texts.remove_at(i)


# ------------------------------------------------------------
#  DRAWING
# ------------------------------------------------------------
func world_transform(local_pos: Vector2, rot: float, scale: Vector2) -> void:
	if state == State.SUPER:
		var origin := Vector2(W / 2.0, H * 0.55)
		var off := origin - origin * cam_zoom
		draw_set_transform(off + local_pos * cam_zoom, rot, scale * cam_zoom)
	else:
		draw_set_transform(cur_off + local_pos, rot, scale)


func _draw() -> void:
	world_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_background()
	draw_fighter(enemy)
	draw_fighter(player)
	world_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_projectiles()
	draw_big_blast()
	for pt in particles:
		var k: float = float(pt["life"]) / float(pt["max"])
		var c: Color = pt["col"]
		draw_circle(pt["p"], float(pt["size"]) * k, Color(c, k))
	for rg in rings:
		var k2: float = float(rg["life"]) / 0.4
		var c2: Color = rg["col"]
		draw_arc(rg["p"], float(rg["r"]), 0.0, TAU, 48, Color(c2, k2), 5.0 * k2 + 1.0)
	for tx in texts:
		var tc: Color = tx["col"]
		var tp: Vector2 = tx["p"]
		ctext(str(tx["s"]), tp.x, tp.y, int(tx["size"]), Color(tc, clampf(float(tx["life"]) * 2.0, 0.0, 1.0)))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state != State.MENU and state != State.SUPER:
		draw_hud()
	draw_overlays()
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, flash * 0.6))


func ctext(s: String, cx: float, y: float, size: int, col: Color, shadow := true) -> void:
	if shadow:
		draw_string(font, Vector2(cx - 600.0 + 3.0, y + 3.0), s, HORIZONTAL_ALIGNMENT_CENTER, 1200.0, size, Color(0, 0, 0, col.a * 0.7))
	draw_string(font, Vector2(cx - 600.0, y), s, HORIZONTAL_ALIGNMENT_CENTER, 1200.0, size, col)


func draw_background() -> void:
	var top := Color(0.05, 0.03, 0.15)
	var bot := Color(0.95, 0.45, 0.25)
	var bands := 36
	var bh := (GROUND + 30.0) / float(bands)
	for i in bands:
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(-40.0, -30.0 + i * bh, W + 80.0, bh + 1.0), top.lerp(bot, pow(t, 1.8)))
	for s in stars:
		var sv: Vector3 = s
		var al := (0.4 + 0.6 * sin(time * 2.0 + sv.z)) * (1.0 - sv.y / 340.0)
		draw_circle(Vector2(sv.x, sv.y), 1.6, Color(1, 1, 1, clampf(al, 0.0, 1.0)))
	draw_circle(Vector2(930, 150), 110.0, Color(1.0, 0.9, 0.8, 0.07))
	draw_circle(Vector2(930, 150), 85.0, Color(1.0, 0.9, 0.8, 0.12))
	draw_circle(Vector2(930, 150), 62.0, Color(1.0, 0.96, 0.88))
	draw_circle(Vector2(912, 135), 12.0, Color(0.9, 0.85, 0.78))
	draw_circle(Vector2(950, 168), 16.0, Color(0.9, 0.85, 0.78))
	draw_circle(Vector2(940, 128), 7.0, Color(0.9, 0.85, 0.78))
	for k in 4:
		var cx := fposmod(k * 380.0 + time * (12.0 + k * 5.0), W + 500.0) - 250.0
		var cy := 90.0 + k * 45.0
		var cc := Color(0.75, 0.35, 0.55, 0.22)
		draw_circle(Vector2(cx, cy), 40.0, cc)
		draw_circle(Vector2(cx + 45.0, cy + 8.0), 32.0, cc)
		draw_circle(Vector2(cx - 45.0, cy + 10.0), 28.0, cc)
	draw_colored_polygon(peaks_far, Color(0.27, 0.12, 0.30))
	draw_colored_polygon(peaks_near, Color(0.15, 0.07, 0.20))
	draw_rect(Rect2(-40.0, GROUND, W + 80.0, H - GROUND + 40.0), Color(0.11, 0.06, 0.14))
	for i in range(-12, 30):
		var x0 := i * 80.0
		draw_line(Vector2(x0, GROUND), Vector2(W * 0.5 + (x0 - W * 0.5) * 2.4, H + 40.0), Color(0.9, 0.35, 0.5, 0.18), 2.0)
	for i in 5:
		var yy := GROUND + 6.0 + i * i * 6.0
		draw_line(Vector2(-40.0, yy), Vector2(W + 40.0, yy), Color(0.9, 0.35, 0.5, 0.18), 2.0)
	draw_line(Vector2(-40.0, GROUND), Vector2(W + 40.0, GROUND), Color(1.0, 0.45, 0.55, 0.35), 8.0)
	draw_line(Vector2(-40.0, GROUND), Vector2(W + 40.0, GROUND), Color(1.0, 0.7, 0.75), 2.0)


func fv(x: float, y: float) -> Vector2:
	return Vector2(x * _fc, y)


func draw_aura(f: Fighter, k: float) -> void:
	var c := f.aura
	var pr := sin(time * 18.0) * 6.0
	draw_circle(fv(0.0, -62.0), 78.0 + pr, Color(c, 0.10 * k))
	draw_circle(fv(0.0, -62.0), 58.0 + pr * 0.5, Color(c, 0.16 * k))
	for i in 7:
		var x := -30.0 + i * 10.0
		var h := 70.0 + sin(time * 14.0 + i * 1.7) * 26.0
		draw_line(fv(x, 0.0), fv(x * 0.6, -h - 50.0), Color(c, 0.35 * k), 9.0)


func draw_arm(sh: Vector2, hand: Vector2, sleeve: Color, skin: Color) -> void:
	var mid := sh.lerp(hand, 0.5)
	draw_line(sh, mid, sleeve, 11.0)
	draw_line(mid, hand, skin, 9.0)
	draw_circle(hand, 6.5, skin)


func draw_fighter(f: Fighter) -> void:
	_fc = float(f.face)
	var draw_p := f.pos
	if state == State.SUPER and super_phase == 2 and f == flurry_attacker and flurry_defender != null and flurry_lunge > 0.0:
		var lunge_target: Vector2 = flurry_defender.pos + Vector2(-flurry_defender.face * 60.0, 0.0)
		var k := sin(flurry_lunge * PI)
		draw_p = f.pos.lerp(lunge_target, k)
	var shd := clampf(1.0 - (GROUND - draw_p.y) / 350.0, 0.25, 1.0)
	world_transform(Vector2(draw_p.x, GROUND + 4.0), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 40.0 * shd, Color(0, 0, 0, 0.45))
	var rot := 0.0
	if f.hp <= 0.0:
		rot = -PI / 2.0 * _fc * minf(f.ko_t * 4.0, 1.0)
	elif f.dash_t > 0.0:
		rot = -0.22 * _fc
	world_transform(draw_p, rot, Vector2.ONE)

	var flashing := f.hit_flash > 0.0 and int(f.hit_flash * 60.0) % 2 == 0
	var gi := Color.WHITE if flashing else f.color
	var dark := Color.WHITE if flashing else f.color.darkened(0.4)
	var skin := Color.WHITE if flashing else Color(1.0, 0.82, 0.66)
	var hair := Color.WHITE if flashing else f.hair
	var sash := Color.WHITE if flashing else Color(1.0, 0.85, 0.2)
	if f.blocking:
		gi = gi.lerp(Color(0.6, 0.85, 1.0), 0.35)
	var moving := f.on_ground and absf(f.vel.x) > 30.0 and f.stun <= 0.0 and f.hp > 0.0 and not f.blocking
	var sw := sin(f.anim * 16.0) * 12.0 if moving else 0.0
	var bob := absf(sin(f.anim * 16.0)) * 3.0 if moving else sin(f.anim * 4.0) * 1.5
	var yb := -bob

	if f.hp > 0.0:
		if f.cast > 0.0 or f.pose_t > 0.25:
			draw_aura(f, 1.0)
		elif state == State.SUPER and f == super_performer:
			draw_aura(f, 1.0)
		elif f.skill_timer >= SKILL_TIME:
			draw_aura(f, 0.35 + 0.15 * sin(time * 6.0))

	var hand_f := fv(28.0 + sw * 0.4, -60.0 + yb)
	var hand_b := fv(8.0 - sw * 0.4, -56.0 + yb)
	if f.hp <= 0.0:
		hand_f = fv(18.0, -40.0)
		hand_b = fv(-14.0, -36.0)
	elif f.cast > 0.12:
		hand_f = fv(-4.0, -52.0)
		hand_b = fv(-24.0, -60.0)
	elif f.pose_t > 0.0:
		hand_f = fv(54.0, -68.0)
		hand_b = fv(46.0, -72.0)
	elif f.blocking:
		hand_f = fv(22.0, -68.0 + yb)
		hand_b = fv(16.0, -72.0 + yb)
	elif state == State.SUPER and f == super_performer:
		hand_f = fv(-6.0, -58.0)
		hand_b = fv(-26.0, -64.0)

	draw_arm(fv(-15.0, -78.0 + yb), hand_b, dark, skin)
	if f.on_ground and not f.blocking:
		draw_line(fv(-8.0, -42.0), fv(-8.0 + sw, -3.0), dark, 13.0)
		draw_line(fv(8.0, -42.0), fv(8.0 - sw, -3.0), dark, 13.0)
		draw_line(fv(-10.0 + sw, -3.0), fv(2.0 + sw, -3.0), Color(0.08, 0.08, 0.12), 8.0)
		draw_line(fv(6.0 - sw, -3.0), fv(18.0 - sw, -3.0), Color(0.08, 0.08, 0.12), 8.0)
	elif f.blocking:
		draw_line(fv(-10.0, -46.0), fv(-6.0, -3.0), dark, 14.0)
		draw_line(fv(10.0, -46.0), fv(6.0, -3.0), dark, 14.0)
		draw_line(fv(-8.0, -3.0), fv(4.0, -3.0), Color(0.08, 0.08, 0.12), 8.0)
		draw_line(fv(4.0, -3.0), fv(16.0, -3.0), Color(0.08, 0.08, 0.12), 8.0)
	else:
		draw_line(fv(-8.0, -42.0), fv(-14.0, -12.0), dark, 13.0)
		draw_line(fv(8.0, -42.0), fv(16.0, -16.0), dark, 13.0)

	var torso_y := -84.0 + yb if not f.blocking else -76.0 + yb
	draw_colored_polygon(PackedVector2Array([fv(-20.0, torso_y), fv(20.0, torso_y), fv(15.0, -40.0), fv(-15.0, -40.0)]), gi)
	draw_line(fv(-17.0, -44.0), fv(17.0, -44.0), sash, 6.0)
	draw_circle(fv(5.0, -70.0 + yb), 5.5, Color(1, 1, 1, 0.85))

	var head_y := -99.0 + yb if not f.blocking else -92.0 + yb
	draw_circle(fv(2.0, head_y), 15.0, skin)
	var hp_pts := PackedVector2Array([
		fv(-14.0, head_y + 1.0), fv(-18.0, head_y - 11.0), fv(-26.0, head_y - 22.0), fv(-8.0, head_y - 15.0),
		fv(-8.0, head_y - 34.0), fv(4.0, head_y - 17.0), fv(12.0, head_y - 36.0), fv(16.0, head_y - 15.0),
		fv(28.0, head_y - 22.0), fv(19.0, head_y - 5.0), fv(16.0, head_y + 2.0)])
	draw_colored_polygon(hp_pts, hair)
	if f.hp > 0.0:
		draw_line(fv(4.0, head_y - 6.0), fv(16.0, head_y - 1.0), Color(0.1, 0.05, 0.05), 3.0)
		draw_circle(fv(11.0, head_y + 2.0), 3.2, Color.WHITE)
		draw_circle(fv(12.2, head_y + 2.0), 1.6, Color(0.05, 0.05, 0.1))
	else:
		draw_line(fv(7.0, -101.0), fv(14.0, -94.0), Color(0.1, 0.05, 0.05), 2.5)
		draw_line(fv(14.0, -101.0), fv(7.0, -94.0), Color(0.1, 0.05, 0.05), 2.5)

	draw_arm(fv(15.0, -78.0 + yb), hand_f, gi, skin)

	if f.blocking:
		var bk := 0.55 + 0.25 * sin(time * 12.0)
		draw_arc(fv(28.0, -62.0 + yb), 32.0, -1.2, 1.2, 18, Color(0.5, 0.85, 1.0, bk), 5.0)
		draw_arc(fv(28.0, -62.0 + yb), 32.0, -1.2, 1.2, 18, Color.WHITE, 1.5)

	if f.iframe > 0.0:
		draw_arc(fv(0.0, -62.0), 46.0, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 2.0)

	if f.cast > 0.0:
		var orb := 10.0 + (1.0 - f.cast) * 18.0
		draw_circle(fv(-4.0, -56.0), orb * 1.6, Color(f.aura, 0.25))
		draw_circle(fv(-4.0, -56.0), orb, f.aura.lightened(0.4))
		draw_circle(fv(-4.0, -56.0), orb * 0.5, Color.WHITE)
	if f.hp > 0.0 and f.skill_timer >= SKILL_TIME and f.cast <= 0.0 and state == State.FIGHT:
		var sy := -158.0 + sin(time * 6.0) * 4.0
		draw_colored_polygon(PackedVector2Array([fv(0.0, sy - 9.0), fv(7.0, sy), fv(0.0, sy + 9.0), fv(-7.0, sy)]), Color(1.0, 0.9, 0.3))
	if f.hp > 0.0 and f.super_charges >= SUPER_CHARGES_NEEDED and state == State.FIGHT:
		var sy2 := -186.0 + sin(time * 9.0) * 5.0
		var pulse := 0.6 + 0.4 * sin(time * 10.0)
		draw_circle(fv(0.0, sy2), 9.0, Color(1.0, 0.9, 0.3, pulse))
		draw_arc(fv(0.0, sy2), 13.0, 0.0, TAU, 16, Color.WHITE, 2.0)


func draw_projectiles() -> void:
	for pr in projectiles:
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		var r: float = pr["r"]
		var col: Color = pr["col"]
		var big: bool = pr["big"]
		var tail := -vel.normalized() * (r * 5.0 if big else r * 2.5)
		draw_line(pos, pos + tail, Color(col, 0.35), r * (1.6 if big else 1.2))
		draw_line(pos, pos + tail * 0.7, Color(col.lightened(0.5), 0.6), r * 0.8)
		draw_circle(pos, r * 1.7, Color(col, 0.20))
		draw_circle(pos, r * 1.2, Color(col, 0.45))
		draw_circle(pos, r * 0.75, col.lightened(0.3))
		draw_circle(pos, r * 0.4, Color.WHITE)


func draw_big_blast() -> void:
	if big_blast_t <= 0.0:
		return
	var k := clampf(big_blast_t / 0.45, 0.0, 1.0)
	var a := k * k
	var dir := big_blast_to - big_blast_from
	var len_ := dir.length()
	if len_ < 1.0:
		return
	var n := dir.normalized()
	var perp := Vector2(-n.y, n.x)
	var width := 26.0 * a + 4.0
	# outer glow
	draw_line(big_blast_from, big_blast_to, Color(big_blast_col, 0.25 * a), width * 3.2)
	draw_line(big_blast_from, big_blast_to, Color(big_blast_col, 0.5 * a), width * 1.8)
	draw_line(big_blast_from, big_blast_to, Color(big_blast_col.lightened(0.4), 0.85 * a), width)
	draw_line(big_blast_from, big_blast_to, Color(1, 1, 1, 0.9 * a), width * 0.4)
	# crackling energy zig-zag along the beam
	var segs := 10
	var prev := big_blast_from
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var pp: Vector2 = big_blast_from.lerp(big_blast_to, t) + perp * sin(t * 30.0 + time * 40.0) * (6.0 * a)
		draw_line(prev, pp, Color(1, 1, 1, 0.6 * a), 2.0)
		prev = pp
	# muzzle flare + impact flare
	draw_circle(big_blast_from, 26.0 * a + 8.0, Color(big_blast_col, 0.5 * a))
	draw_circle(big_blast_from, 14.0 * a + 4.0, Color.WHITE)
	draw_circle(big_blast_to, 46.0 * a + 10.0, Color(big_blast_col, 0.4 * a))
	draw_circle(big_blast_to, 24.0 * a + 6.0, Color.WHITE)


func bar_rect(x0: float, bw: float, ratio: float, right: bool, y: float, h: float) -> Rect2:
	if right:
		return Rect2(x0 + bw * (1.0 - ratio), y, bw * ratio, h)
	return Rect2(x0, y, bw * ratio, h)


func draw_panel(f: Fighter, right: bool) -> void:
	var bw := 520.0
	var x0 := W - 40.0 - bw if right else 40.0
	var ratio := clampf(f.hp / f.max_hp, 0.0, 1.0)
	var dratio := clampf(f.disp_hp / f.max_hp, 0.0, 1.0)
	draw_rect(Rect2(x0 - 4.0, 26.0, bw + 8.0, 34.0), Color(0.02, 0.02, 0.05, 0.9))
	draw_rect(Rect2(x0, 30.0, bw, 26.0), Color(0.18, 0.05, 0.08))
	draw_rect(bar_rect(x0, bw, dratio, right, 30.0, 26.0), Color(1.0, 0.95, 0.6))
	var hc := Color(1.0, 0.2, 0.2).lerp(Color(1.0, 0.9, 0.2), clampf(ratio * 2.0, 0.0, 1.0)).lerp(Color(0.3, 1.0, 0.4), clampf((ratio - 0.5) * 2.0, 0.0, 1.0))
	draw_rect(bar_rect(x0, bw, ratio, right, 30.0, 26.0), hc)
	draw_rect(bar_rect(x0, bw, ratio, right, 30.0, 11.0), Color(1, 1, 1, 0.22))
	draw_rect(Rect2(x0 - 4.0, 26.0, bw + 8.0, 34.0), f.aura, false, 2.0)
	draw_string(font, Vector2(x0, 21.0), f.title, HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT, bw, 20, Color.WHITE)
	draw_string(font, Vector2(x0, 50.0), str(ceili(f.hp)), HORIZONTAL_ALIGNMENT_CENTER, bw, 16, Color(0, 0, 0, 0.8))
	for i in ROUNDS_TO_WIN:
		var cx := x0 + 10.0 + i * 22.0 if right else x0 + bw - 10.0 - i * 22.0
		draw_circle(Vector2(cx, 12.0), 7.0, Color(1.0, 0.85, 0.2) if i < f.wins else Color(0, 0, 0, 0.5))
		draw_arc(Vector2(cx, 12.0), 7.0, 0.0, TAU, 20, Color.WHITE, 1.5)
	var sx := x0 + bw - 300.0 if right else x0
	var sr := clampf(f.skill_timer / SKILL_TIME, 0.0, 1.0)
	var ready := sr >= 1.0
	draw_rect(Rect2(sx - 2.0, 64.0, 304.0, 16.0), Color(0.02, 0.02, 0.05, 0.9))
	draw_rect(Rect2(sx, 66.0, 300.0, 12.0), Color(0.15, 0.15, 0.25))
	var sc := f.aura
	if ready:
		sc = Color(1.0, 0.9, 0.3).lerp(Color.WHITE, 0.5 + 0.5 * sin(time * 10.0))
	draw_rect(bar_rect(sx, 300.0, sr, right, 66.0, 12.0), sc)
	var lbl := "SPECIAL READY!" if ready else "SPECIAL %ds" % ceili(SKILL_TIME - f.skill_timer)
	draw_string(font, Vector2(sx, 76.5), lbl, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 11, Color(0, 0, 0, 0.9) if ready else Color.WHITE)
	if not right:
		for i in 2:
			var rc := Rect2(sx + i * 154.0, 86.0, 148.0, 24.0)
			var sel := i == f.skill_sel
			draw_rect(rc, Color(f.aura, 0.55) if sel else Color(0, 0, 0, 0.5))
			draw_rect(rc, Color.WHITE if sel else Color(1, 1, 1, 0.3), false, 2.0 if sel else 1.0)
			draw_string(font, Vector2(rc.position.x, rc.position.y + 17.0), "%d  %s" % [i + 1, SKILL_NAMES[i]], HORIZONTAL_ALIGNMENT_CENTER, rc.size.x, 13, Color.WHITE)

	# v1.2 - super charge pips
	var ux := x0 if not right else x0 + bw - 90.0
	var uy := 122.0 if not right else 90.0
	for i in SUPER_CHARGES_NEEDED:
		var ccx := ux + i * 26.0
		var filled := i < f.super_charges
		var col: Color = f.aura if filled else Color(1, 1, 1, 0.25)
		draw_colored_polygon(PackedVector2Array([Vector2(ccx, uy - 9.0), Vector2(ccx + 8.0, uy), Vector2(ccx, uy + 9.0), Vector2(ccx - 8.0, uy)]), col)
	if f.super_charges >= SUPER_CHARGES_NEEDED:
		var pulse := 0.6 + 0.4 * sin(time * 8.0)
		var lbl2 := "ULTIMATE READY - Q" if not right else "AI ULTIMATE READY"
		draw_string(font, Vector2(ux, uy + 20.0), lbl2, HORIZONTAL_ALIGNMENT_LEFT if not right else HORIZONTAL_ALIGNMENT_RIGHT, 220.0, 13, Color(1.0, 0.9, 0.3, pulse))

	var cy := 154.0 if not right else 114.0
	if f.combo >= 2 and time - f.combo_last < 1.4:
		draw_string(font, Vector2(x0, cy), "COMBO x%d" % f.combo, HORIZONTAL_ALIGNMENT_LEFT if not right else HORIZONTAL_ALIGNMENT_RIGHT, bw, 16, Color(1.0, 0.6, 0.9))


func draw_hud() -> void:
	draw_panel(player, false)
	draw_panel(enemy, true)
	var df: Dictionary = DIFFS[diff_idx]
	ctext("ROUND %d" % round_num, W / 2.0, 42.0, 24, Color.WHITE)
	if vs_mode == 1:
		ctext("LOCAL 2-PLAYER", W / 2.0, 64.0, 15, Color(1.0, 0.5, 0.8))
		ctext("P1: ARROWS / SPACE / S / Q         P2: A D W / F / G / J", W / 2.0, H - 14.0, 13, Color(1, 1, 1, 0.55), false)
	else:
		ctext(str(df["name"]), W / 2.0, 64.0, 15, df["col"])
		ctext("ARROWS move/jump   DOWN block   dbl-tap dash   SPACE blast   S special   Q ULTIMATE   SHIFT swap   P pause", W / 2.0, H - 14.0, 13, Color(1, 1, 1, 0.55), false)


# ------------------------------------------------------------
#  ULTIMATE CUTSCENE OVERLAY
# ------------------------------------------------------------
func grade_color(g: String) -> Color:
	if g.contains("PERFECT"):
		return Color(1.0, 0.95, 0.3)
	if g.contains("DEFENDED") or g.contains("GREAT"):
		return Color(0.5, 1.0, 0.6)
	if g.contains("GOOD") or g.contains("PARTIALLY"):
		return Color(0.6, 0.85, 1.0)
	if g.contains("WEAK"):
		return Color(1.0, 0.7, 0.3)
	return Color(1.0, 0.3, 0.3)


func draw_arrow_glyph(center: Vector2, dirv: int, col: Color) -> void:
	var pts: PackedVector2Array
	match dirv:
		0:  # up
			pts = PackedVector2Array([center + Vector2(-20, 14), center + Vector2(0, -16), center + Vector2(20, 14)])
		1:  # down
			pts = PackedVector2Array([center + Vector2(-20, -14), center + Vector2(0, 16), center + Vector2(20, -14)])
		2:  # left
			pts = PackedVector2Array([center + Vector2(14, -20), center + Vector2(-16, 0), center + Vector2(14, 20)])
		_:  # right
			pts = PackedVector2Array([center + Vector2(-14, -20), center + Vector2(16, 0), center + Vector2(-14, 20)])
	draw_colored_polygon(pts, col)


func draw_qte() -> void:
	var center := Vector2(W / 2.0, H * 0.56)
	# one steady gold target ring + one shrinking ring - simple, easy to read
	draw_arc(center, QTE_TARGET_R, 0.0, TAU, 40, Color(1.0, 0.9, 0.3, 0.9), 5.0)
	var radius: float = lerp(QTE_R_START, 0.0, clampf(qte_timer / qte_shrink_time, 0.0, 1.0))
	var in_band := absf(radius - QTE_TARGET_R) <= QTE_TOL
	var ring_col := Color(0.3, 1.0, 0.5) if in_band else Color(1, 1, 1, 0.85)
	draw_arc(center, maxf(radius, 1.0), 0.0, TAU, 40, ring_col, 5.0)
	if qte_idx < qte_seq.size():
		draw_arrow_glyph(center, qte_seq[qte_idx], Color.WHITE)
	var n := qte_seq.size()
	for i in n:
		var col: Color
		if i < qte_results.size():
			col = Color(0.3, 1.0, 0.4) if qte_results[i] else Color(1.0, 0.3, 0.3)
		elif i == qte_idx:
			col = Color.WHITE
		else:
			col = Color(1, 1, 1, 0.3)
		draw_circle(Vector2(W / 2.0 - float(n - 1) * 20.0 + i * 40.0, H * 0.56 + 130.0), 9.0, col)
	var hint := "PRESS THE ARROW WHEN THE RING TOUCHES GOLD"
	if vs_mode == 1:
		hint = "PLAYER 1 - USE ARROW KEYS" if qte_scheme == 0 else "PLAYER 2 - USE W A S D"
	ctext(hint, W / 2.0, H * 0.56 - 180.0, 18, Color(1, 1, 1, 0.75))


func draw_super_result() -> void:
	ctext(super_grade, W / 2.0, H * 0.42, 50, grade_color(super_grade))
	if flurry_attacker != null:
		ctext("%d DAMAGE" % int(flurry_total), W / 2.0, H * 0.42 + 56.0, 26, Color(1, 1, 1, 0.85))
		var who := "YOU" if flurry_attacker == player else "AI"
		ctext("%s LANDED %d HITS!" % [who, flurry_count], W / 2.0, H * 0.42 + 92.0, 17, Color(1, 1, 1, 0.6))
	else:
		ctext("NO DAMAGE TAKEN", W / 2.0, H * 0.42 + 56.0, 24, Color(0.5, 1.0, 0.6))


func draw_flurry_banner() -> void:
	if flurry_attacker == null:
		ctext("ULTIMATE FIZZLES OUT...", W / 2.0, H * 0.78, 24, Color(0.6, 0.85, 1.0, 0.85))
		return
	var who := "YOU" if flurry_attacker == player else "AI"
	ctext("%s STRIKES!" % who, W / 2.0, H * 0.78, 26, Color(1.0, 0.8, 0.3, 0.85 + 0.15 * sin(time * 20.0)))


func draw_super_cutscene() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.30))
	if super_performer != null:
		ctext(super_performer.ult_name, W / 2.0, 140.0, 44, super_performer.aura)
		var sub := "YOUR ULTIMATE TECHNIQUE!" if super_performer == player else "AI UNLEASHES ITS ULTIMATE - DEFEND!"
		ctext(sub, W / 2.0, 178.0, 19, Color(1, 1, 1, 0.85))
	match super_phase:
		0:
			ctext("...", W / 2.0, H * 0.5, 36, Color(1, 1, 1, 0.5))
		1:
			draw_qte()
		2:
			draw_flurry_banner()
		3, 4:
			draw_super_result()
	if letterbox > 0.0:
		var bh := letterbox * 130.0
		draw_rect(Rect2(0, 0, W, bh), Color.BLACK)
		draw_rect(Rect2(0, H - bh, W, bh), Color.BLACK)


func draw_overlays() -> void:
	match state:
		State.MENU:
			draw_menu()
		State.INTRO:
			if state_t > 0.8:
				ctext("ROUND %d" % round_num, W / 2.0, 330.0, 100, Color.WHITE)
			else:
				ctext("FIGHT!", W / 2.0, 330.0, 130, Color(1.0, 0.45, 0.2))
		State.FIGHT:
			if fight_msg_t > 0.0:
				var k := fight_msg_t / 0.7
				ctext("FIGHT!", W / 2.0, 330.0, int(130.0 + (1.0 - k) * 60.0), Color(1.0, 0.45, 0.2, k))
			var p_low := player.hp > 0.0 and player.hp / player.max_hp < 0.25
			var e_low := vs_mode == 1 and enemy.hp > 0.0 and enemy.hp / enemy.max_hp < 0.25
			if p_low or e_low:
				var wk := 0.10 + 0.10 * sin(time * 9.0)
				draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.08, 0.08, wk))
		State.SUPER:
			draw_super_cutscene()
		State.ROUND_END:
			ctext("K.O.!", W / 2.0, 350.0, 180, Color(1.0, 0.25, 0.2))
		State.PAUSE:
			draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
			ctext("PAUSED", W / 2.0, 300.0, 90, Color.WHITE)
			ctext("P  resume        ESC  quit to menu", W / 2.0, 380.0, 24, Color(1, 1, 1, 0.7))
		State.MATCH_END:
			draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
			if vs_mode == 1:
				var wtxt := "PLAYER 1 WINS!" if winner == player else "PLAYER 2 WINS!"
				var wcol := winner.aura.lightened(0.3)
				ctext(wtxt, W / 2.0, 340.0, 110, wcol)
			elif winner == player:
				ctext("VICTORY!", W / 2.0, 340.0, 150, Color(1.0, 0.85, 0.2))
			else:
				ctext("DEFEAT", W / 2.0, 340.0, 150, Color(1.0, 0.25, 0.25))
			ctext("Press ENTER to return to menu", W / 2.0, 430.0, 28, Color(1, 1, 1, 0.6 + 0.4 * sin(time * 5.0)))


func draw_menu() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35))
	var hue := fposmod(time * 0.15, 1.0)
	ctext("KI CLASH", W / 2.0, 150.0, 110, Color.from_hsv(hue, 0.6, 1.0))
	ctext("UPDATE 1.4  -  RIVALS", W / 2.0, 185.0, 19, Color(1.0, 0.85, 0.3, 0.95))

	# mode toggle banner
	var mode_col := Color(0.3, 0.85, 1.0) if vs_mode == 0 else Color(1.0, 0.5, 0.8)
	var mode_txt := "MODE:  VS AI" if vs_mode == 0 else "MODE:  VS PLAYER 2  (LOCAL)"
	ctext(mode_txt, W / 2.0, 222.0, 25, mode_col)
	ctext("press TAB to switch mode", W / 2.0, 246.0, 14, Color(1, 1, 1, 0.5 + 0.3 * sin(time * 4.0)))

	if vs_mode == 0:
		ctext("SELECT DIFFICULTY  (YOU: %d HP)" % int(MAX_HP), W / 2.0, 292.0, 19, Color(1, 1, 1, 0.8))
		for i in DIFFS.size():
			var df: Dictionary = DIFFS[i]
			var sel := i == diff_idx
			var c: Color = df["col"]
			var s := "%s  -  AI %d HP" % [str(df["name"]), int(df["enemy_hp"])]
			if sel:
				s = ">   " + s + "   <"
			ctext(s, W / 2.0, 336.0 + i * 40.0, 28 if sel else 20, c if sel else Color(c, 0.45))
		ctext("UP / DOWN choose difficulty        ENTER fight", W / 2.0, 548.0, 19, Color(1, 1, 1, 0.6 + 0.4 * sin(time * 4.0)))
		ctext("ARROWS move/jump   DOWN block   dbl-tap L/R dash   SPACE blast   S special   SHIFT swap", W / 2.0, 588.0, 15, Color(1, 1, 1, 0.55), false)
		ctext("P pause   M music   Special bar refills every 10s   3 specials charge your ULTIMATE (Q)!", W / 2.0, 612.0, 15, Color(1, 1, 1, 0.5), false)
		ctext("Ultimate QTE: press the arrow shown when the ring touches the gold circle.", W / 2.0, 636.0, 14, Color(0.6, 0.85, 1.0, 0.6), false)
		ctext("Succeed and you unload a combo + a huge blast. Defend AI's ultimate well and it just fails!", W / 2.0, 658.0, 14, Color(0.6, 0.85, 1.0, 0.6), false)
	else:
		ctext("LOCAL 2-PLAYER BATTLE  -  %d HP EACH  -  press ENTER to fight!" % int(MAX_HP), W / 2.0, 300.0, 19, Color(1, 1, 1, 0.85))
		ctext("PLAYER 1", W / 2.0 - 300.0, 350.0, 24, player.aura)
		ctext("ARROWS move / jump", W / 2.0 - 300.0, 384.0, 15, Color(1, 1, 1, 0.75), false)
		ctext("DOWN block    dbl-tap L/R dash", W / 2.0 - 300.0, 406.0, 15, Color(1, 1, 1, 0.75), false)
		ctext("SPACE blast    S special    SHIFT swap", W / 2.0 - 300.0, 428.0, 15, Color(1, 1, 1, 0.75), false)
		ctext("Q ultimate (after 3 specials)", W / 2.0 - 300.0, 450.0, 15, Color(1.0, 0.9, 0.3, 0.9), false)
		ctext("PLAYER 2", W / 2.0 + 300.0, 350.0, 24, enemy.aura)
		ctext("A / D move     W jump", W / 2.0 + 300.0, 384.0, 15, Color(1, 1, 1, 0.75), false)
		ctext("X block    dbl-tap A/D dash", W / 2.0 + 300.0, 406.0, 15, Color(1, 1, 1, 0.75), false)
		ctext("F blast    G special    H swap", W / 2.0 + 300.0, 428.0, 15, Color(1, 1, 1, 0.75), false)
		ctext("J ultimate (after 3 specials)", W / 2.0 + 300.0, 450.0, 15, Color(1.0, 0.9, 0.3, 0.9), false)
		ctext("Each player's ULTIMATE is their own QTE - PLAYER 1 uses arrows, PLAYER 2 uses WASD!", W / 2.0, 500.0, 15, Color(0.6, 0.85, 1.0, 0.75), false)
		ctext("P pause   M music   ENTER to begin the rivalry!", W / 2.0, 548.0, 19, Color(1, 1, 1, 0.6 + 0.4 * sin(time * 4.0)))
