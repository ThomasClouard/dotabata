class_name Sfx
extends Node
## Sons entièrement synthétisés au démarrage (aucun fichier à charger).
## Chaque effet est rendu une fois en PCM 16 bits dans un AudioStreamWAV, puis rejoué à la demande.

const RATE := 22050
const MASTER := 0.35

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_rng.seed = 42
	_build()


func _grow(buf: PackedFloat32Array, n: int) -> void:
	if buf.size() < n:
		buf.resize(n)


## Oscillateur dont la fréquence et le volume glissent de façon exponentielle.
func _tone(buf: PackedFloat32Array, type: String, f0: float, f1: float, dur: float, vol := 0.5, delay := 0.0) -> void:
	f1 = maxf(20.0, f1)
	var n0 := int(delay * RATE)
	var n := int(dur * RATE)
	_grow(buf, n0 + n)
	var phase := 0.0
	var ratio := f1 / f0
	var decay := 0.001 / vol
	for i in n:
		var k := float(i) / n
		phase = fposmod(phase + f0 * pow(ratio, k) / RATE, 1.0)
		var s := 0.0
		match type:
			"sine":
				s = sin(TAU * phase)
			"square":
				s = 1.0 if phase < 0.5 else -1.0
			"sawtooth":
				s = 2.0 * phase - 1.0
			_:
				s = 1.0 - 4.0 * absf(phase - 0.5)
		buf[n0 + i] += s * vol * pow(decay, k)


## Souffle de bruit blanc filtré passe-bas, dont la coupure descend.
func _burst(buf: PackedFloat32Array, dur: float, vol: float, freq: float, delay := 0.0) -> void:
	var n0 := int(delay * RATE)
	var n := int(dur * RATE)
	_grow(buf, n0 + n)
	var y1 := 0.0
	var y2 := 0.0
	var ratio := 60.0 / freq
	var decay := 0.001 / vol
	for i in n:
		var k := float(i) / n
		var a := 1.0 - exp(-TAU * freq * pow(ratio, k) / RATE)
		y1 += a * (_rng.randf() * 2.0 - 1.0 - y1)
		y2 += a * (y1 - y2)
		buf[n0 + i] += y2 * 1.6 * vol * pow(decay, k)


func _commit(key: String, buf: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * MASTER, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_streams[key] = w


func _build() -> void:
	var b := PackedFloat32Array()
	_tone(b, "square", 260, 620, 0.14, 0.18)
	_commit("jump", b)
	b = PackedFloat32Array()
	_burst(b, 0.09, 0.25, 500)
	_commit("land", b)
	b = PackedFloat32Array()
	_tone(b, "sine", 180, 720, 0.28, 0.4)
	_tone(b, "sine", 360, 900, 0.2, 0.15, 0.05)
	_commit("boing", b)
	b = PackedFloat32Array()
	_burst(b, 0.18, 0.6, 1400)
	_tone(b, "sawtooth", 220, 60, 0.22, 0.3)
	_commit("hit", b)
	b = PackedFloat32Array()
	_tone(b, "square", 420, 140, 0.18, 0.22)
	_commit("hurt", b)
	b = PackedFloat32Array()
	_tone(b, "sine", 520, 90, 0.25, 0.5)
	_burst(b, 0.12, 0.35, 2500)
	_commit("fire", b)
	b = PackedFloat32Array()
	_burst(b, 0.7, 0.9, 900)
	_tone(b, "sine", 110, 30, 0.6, 0.8)
	_commit("boom", b)
	b = PackedFloat32Array()
	_tone(b, "triangle", 500, 320, 0.08, 0.3)
	_commit("place", b)
	b = PackedFloat32Array()
	_tone(b, "triangle", 300, 180, 0.1, 0.25)
	_commit("remove", b)
	b = PackedFloat32Array()
	for i in 3:
		var f: float = [660.0, 880.0, 1320.0][i]
		_tone(b, "square", f, f, 0.09, 0.2, i * 0.07)
	_commit("pickup", b)
	b = PackedFloat32Array()
	for i in 3:
		var f: float = [523.0, 659.0, 784.0][i]
		_tone(b, "triangle", f, f, 0.14, 0.35, i * 0.09)
	_commit("checkpoint", b)
	b = PackedFloat32Array()
	_tone(b, "square", 440, 440, 0.08, 0.25)
	_commit("tick", b)
	b = PackedFloat32Array()
	_tone(b, "square", 880, 880, 0.35, 0.3)
	_commit("go", b)
	b = PackedFloat32Array()
	for i in 6:
		var f: float = [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0][i]
		_tone(b, "square", f, f, 0.16, 0.22, i * 0.13)
	_commit("win", b)
	b = PackedFloat32Array()
	_burst(b, 0.35, 0.4, 700)
	_commit("crumble", b)
	# petit air de xylophone quand un squelette s'écroule
	b = PackedFloat32Array()
	for i in 7:
		var f: float = [1568.0, 1319.0, 1175.0, 988.0, 784.0, 659.0, 523.0][i]
		_tone(b, "sine", f, f * 0.99, 0.22, 0.4, i * 0.065 + _rng.randf() * 0.02)
	_commit("xylo", b)


func play(key: String, vol := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = linear_to_db(maxf(0.01, vol))
	p.play()


func jump() -> void: play("jump")
func land() -> void: play("land")
func boing() -> void: play("boing")
func hit() -> void: play("hit")
func hurt() -> void: play("hurt")
func fire() -> void: play("fire")
func boom(vol := 1.0) -> void: play("boom", vol)
func place() -> void: play("place")
func remove() -> void: play("remove")
func pickup() -> void: play("pickup")
func checkpoint() -> void: play("checkpoint")
func tick() -> void: play("tick")
func go() -> void: play("go")
func win() -> void: play("win")
func crumble() -> void: play("crumble")
func xylo() -> void: play("xylo")
