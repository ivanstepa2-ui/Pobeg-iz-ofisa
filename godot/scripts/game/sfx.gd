class_name Sfx
extends Node
## Процедурные звуки (синтезируются при старте в AudioStreamWAV, 22 кГц моно — лоу-фай как на PS1).

const RATE := 22050
var streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _hum: AudioStreamPlayer
var muted := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build()
	_hum = AudioStreamPlayer.new()
	_hum.stream = streams["hum"]
	_hum.volume_db = -20.0
	add_child(_hum)


func start_ambience() -> void:
	if not _hum.playing and not muted:
		_hum.play()


func set_muted(m: bool) -> void:
	muted = m
	if m: _hum.stop()
	else: _hum.play()


## Воспроизвести звук; vol 0..1, pitch_var — случайный разброс высоты.
func play(snd: String, vol: float = 1.0, pitch_var: float = 0.08) -> void:
	if muted or vol <= 0.02 or not streams.has(snd):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[snd]
	p.volume_db = linear_to_db(clampf(vol, 0.0, 1.5))
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


## Звук в мире: громкость по расстоянию до слушателя.
func play_at(snd: String, pos: Vector3, listener: Vector3, vol: float = 1.0, max_d: float = 18.0) -> void:
	var d := Vector2(pos.x - listener.x, pos.z - listener.z).length()
	play(snd, vol * clampf(1.0 - d / max_d, 0.0, 1.0))


# ---------------------------------------------------------------- синтез
func _make(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s


## Шум с огибающей и однополюсным ФНЧ/ФВЧ.
func _noise(dur: float, lp: float, hp: float, attack: float, decay_pow: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	var a_lp := 1.0 - exp(-TAU * lp / RATE)
	var a_hp := exp(-TAU * hp / RATE)
	var y := 0.0
	var prev_x := 0.0
	var prev_h := 0.0
	for i in n:
		var t := float(i) / n
		var x := _rng.randf_range(-1.0, 1.0)
		y += a_lp * (x - y)
		var h := a_hp * (prev_h + y - prev_x)
		prev_x = y
		prev_h = h
		var env := minf(1.0, t / maxf(attack, 0.0001)) * pow(1.0 - t, decay_pow)
		out[i] = (h if hp > 0.0 else y) * env * gain
	return out


func _tone(dur: float, f0: float, f1: float, wave: String, decay_pow: float, gain: float, vib: float = 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t) * (1.0 + vib * sin(i / float(RATE) * TAU * 6.0))
		ph += f / RATE
		var v := 0.0
		match wave:
			"sin": v = sin(ph * TAU)
			"sq": v = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"saw": v = fmod(ph, 1.0) * 2.0 - 1.0
			"tri": v = absf(fmod(ph, 1.0) * 4.0 - 2.0) - 1.0
		out[i] = v * pow(1.0 - t, decay_pow) * gain * minf(1.0, i / 60.0)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset: float = 0.0) -> PackedFloat32Array:
	var off := int(offset * RATE)
	var n := maxi(a.size(), b.size() + off)
	var out := PackedFloat32Array(); out.resize(n)
	for i in a.size(): out[i] += a[i]
	for i in b.size(): out[i + off] += b[i]
	return out


func _build() -> void:
	streams["step"] = _make(_noise(0.07, 900, 80, 0.05, 3.0, 0.5))
	streams["punch"] = _make(_mix(_noise(0.12, 1500, 60, 0.02, 2.5, 0.8), _tone(0.12, 140, 50, "sin", 2.0, 0.8)))
	streams["hit"] = _make(_mix(_noise(0.18, 900, 40, 0.02, 2.0, 0.8), _tone(0.2, 110, 40, "sin", 1.5, 0.9)))
	streams["hurt"] = _make(_mix(_tone(0.25, 220, 140, "saw", 1.5, 0.35, 0.03), _noise(0.15, 1200, 80, 0.02, 2.0, 0.4)))
	streams["gun"] = _make(_mix(_noise(0.3, 4000, 100, 0.005, 3.0, 1.0), _tone(0.2, 160, 40, "sin", 2.0, 1.0)))
	streams["shotgun"] = _make(_mix(_noise(0.55, 2500, 60, 0.005, 2.0, 1.1), _tone(0.35, 110, 30, "sin", 1.5, 1.1)))
	streams["uzi"] = _make(_mix(_noise(0.14, 5000, 300, 0.003, 3.0, 0.8), _tone(0.08, 220, 80, "sq", 2.0, 0.35)))
	streams["rifle"] = _make(_mix(_mix(_noise(0.6, 3500, 60, 0.003, 2.2, 1.2), _tone(0.4, 130, 35, "sin", 1.5, 1.1)), _noise(0.12, 2500, 900, 0.05, 1.0, 0.35), 0.45))
	# щелкун: серия сухих щелчков, визгливый крик, укус
	var clk := _noise(0.02, 6000, 1500, 0.002, 4.0, 0.9)
	streams["click_c"] = _make(_mix(_mix(_mix(clk, clk, 0.07), _mix(clk, clk, 0.05), 0.15), clk, 0.32))
	streams["clicker_scream"] = _make(_mix(_tone(0.9, 900, 520, "saw", 0.7, 0.4, 0.09), _mix(_noise(0.9, 5000, 900, 0.03, 0.8, 0.5), _tone(0.7, 1350, 700, "sq", 1.0, 0.15, 0.1), 0.05)))
	streams["bite"] = _make(_mix(_noise(0.25, 1800, 120, 0.01, 1.5, 0.9), _tone(0.2, 160, 70, "sin", 1.5, 0.6)))
	streams["click"] =_make(_mix(_noise(0.03, 7000, 2500, 0.002, 3.0, 0.8), _tone(0.05, 1800, 1500, "sq", 3.0, 0.25), 0.04))
	streams["reload"] =_make(_mix(_noise(0.05, 4000, 1500, 0.01, 2.0, 0.6), _noise(0.06, 3000, 1200, 0.01, 2.0, 0.6), 0.25))
	streams["stab"] = _make(_mix(_noise(0.1, 2500, 300, 0.02, 2.0, 0.6), _tone(0.08, 300, 120, "sin", 2.0, 0.5)))
	streams["shout"] = _make(_mix(_tone(0.55, 300, 220, "saw", 0.8, 0.45, 0.07), _mix(_tone(0.5, 450, 330, "sq", 1.0, 0.18, 0.05), _noise(0.55, 2200, 300, 0.05, 1.0, 0.25))))
	streams["silenced"] =_make(_noise(0.12, 3000, 800, 0.005, 3.0, 0.6))
	streams["m4"] = _make(_noise(0.1, 3400, 900, 0.004, 3.0, 0.65))   # 0.19: M4A1-S с глушителем
	streams["heli"] = _make(_mix(_noise(0.32, 300, 40, 0.01, 1.4, 1.0), _tone(0.3, 70, 55, "sin", 1.2, 0.6)))   # 0.19: удар лопастей
	streams["shatter"] = _make(_mix(_noise(0.35, 9000, 2500, 0.005, 2.0, 0.9), _mix(_tone(0.15, 3200, 3000, "sin", 2.0, 0.3), _tone(0.18, 4300, 4100, "sin", 2.0, 0.25), 0.05)))
	streams["thud"] = _make(_mix(_noise(0.2, 500, 30, 0.01, 2.0, 0.9), _tone(0.2, 90, 40, "sin", 2.0, 0.9)))
	streams["clink"] = _make(_mix(_tone(0.3, 2100, 2050, "sin", 3.0, 0.5), _noise(0.06, 6000, 1500, 0.005, 2.0, 0.5)))
	streams["whoosh"] = _make(_noise(0.25, 2500, 400, 0.4, 1.5, 0.5))
	streams["boom"] = _make(_mix(_noise(1.3, 900, 20, 0.005, 1.6, 1.2), _tone(0.8, 70, 25, "sin", 1.2, 1.2)))
	streams["hiss"] = _make(_noise(1.0, 9000, 2500, 0.03, 0.8, 0.7))
	streams["ring"] = _make(_ring())
	streams["beep"] = _make(_tone(0.09, 1400, 1400, "sq", 0.5, 0.25))
	streams["type"] = _make(_noise(0.025, 8000, 2000, 0.01, 2.0, 0.5))
	streams["hack_ok"] = _make(_mix(_mix(_tone(0.1, 523, 523, "sq", 0.5, 0.25), _tone(0.1, 659, 659, "sq", 0.5, 0.25), 0.1), _mix(_tone(0.1, 784, 784, "sq", 0.5, 0.25), _tone(0.25, 1046, 1046, "sq", 1.0, 0.25), 0.1), 0.2))
	streams["pickup"] = _make(_mix(_tone(0.08, 880, 880, "tri", 0.5, 0.4), _tone(0.15, 1320, 1320, "tri", 1.0, 0.4), 0.07))
	streams["alert"] = _make(_mix(_tone(0.12, 880, 880, "sq", 0.3, 0.3), _tone(0.3, 1320, 1320, "sq", 1.0, 0.3), 0.1))
	streams["groan"] = _make(_mix(_tone(1.0, 95, 70, "saw", 0.8, 0.45, 0.06), _noise(1.0, 600, 100, 0.2, 1.0, 0.25)))
	streams["scream"] = _make(_mix(_tone(0.7, 650, 900, "saw", 1.0, 0.35, 0.05), _noise(0.7, 3000, 500, 0.05, 1.0, 0.3)))
	streams["roar"] = _make(_mix(_tone(0.9, 60, 45, "saw", 0.8, 0.6, 0.08), _noise(0.9, 400, 30, 0.05, 1.0, 0.5)))
	streams["pant"] = _make(_noise(0.4, 1500, 300, 0.3, 1.0, 0.35))
	streams["ding"] = _make(_mix(_tone(0.8, 1046, 1046, "sin", 1.5, 0.45), _tone(1.0, 1318, 1318, "sin", 1.5, 0.4), 0.35))
	streams["deny"] = _make(_tone(0.25, 180, 160, "sq", 0.5, 0.25))
	streams["heal"] = _make(_mix(_tone(0.12, 600, 900, "tri", 0.5, 0.4), _tone(0.2, 900, 1300, "tri", 1.0, 0.4), 0.1))
	streams["hum"] = _make(_hum_loop(), true)


func _ring() -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array(); out.resize(n)
	var ph := 0.0
	for i in n:
		ph += 1600.0 / RATE
		var gate := 1.0 if int(i / float(RATE) * 30.0) % 2 == 0 else 0.0
		out[i] = (1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * gate * 0.22
	return out


func _hum_loop() -> PackedFloat32Array:
	# Гул ламп дневного света 100 Гц + «кондиционер»; длина кратна периоду — бесшовная петля.
	var n := RATE
	var out := PackedFloat32Array(); out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += 0.02 * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = sin(t * TAU * 100.0) * 0.18 + sin(t * TAU * 50.0) * 0.12 + y * 0.9
	return out
