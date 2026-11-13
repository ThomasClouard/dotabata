extends SceneTree
## Tests de parité avec le jeu d'origine : rejoue en GDScript les scénarios enregistrés par
## tools/gen-golden.mjs (physique, obstacles des niveaux, balistique) et compare les résultats.
##   godot --headless --path godot -s res://tests/run_tests.gd

const EPS := 1e-6
const H := 1.0 / 60.0

var _fails := 0
var _checks := 0


func _init() -> void:
	_test_physics()
	_test_levels()
	_test_wave("vague1")
	_test_wave("vague4")
	_test_vague2()
	_test_vague3()
	_test_mortar()
	_test_server()
	print("%d vérifications, %d échec(s)" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _load(file: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://tests/golden/" + file)
	assert(txt != "", "fichier de référence manquant : " + file)
	return JSON.parse_string(txt)


func _near(a: float, b: float, what: String) -> bool:
	_checks += 1
	if absf(a - b) <= EPS * maxf(1.0, absf(b)) or (is_inf(a) and is_inf(b)):
		return true
	_fails += 1
	if _fails <= 25:
		print("ÉCHEC ", what, " : obtenu ", a, ", attendu ", b)
	return false


func _same(a: Variant, b: Variant, what: String) -> bool:
	_checks += 1
	if a == b:
		return true
	_fails += 1
	if _fails <= 25:
		print("ÉCHEC ", what, " : obtenu ", a, ", attendu ", b)
	return false


func _col_from(d: Dictionary) -> Phys.Col:
	var c := Phys.Col.box(int(d["id"]), d["c"][0], d["c"][1], d["c"][2], d["h"][0], d["h"][1], d["h"][2], d["yaw"], d["tag"])
	c.vx = d["vel"][0]
	c.vy = d["vel"][1]
	c.vz = d["vel"][2]
	c.ang_vel = d["angVel"]
	c.ice = d["ice"]
	c.bounce = d["bounce"]
	if d["conveyor"] != null:
		c.has_conv = true
		c.conv_x = d["conveyor"][0]
		c.conv_z = d["conveyor"][1]
	if d.has("slow"):
		c.slow = d["slow"]
		c.jump = d["jump"]
		c.jelly = d["jelly"]
		c.slope = d["slope"]
		c.slide = d["slide"]
		if d["boost"] != null:
			c.has_boost = true
			c.boost_x = d["boost"][0]
			c.boost_z = d["boost"][1]
		if d["launch"] != null:
			c.has_launch = true
			c.launch_x = d["launch"][0]
			c.launch_y = d["launch"][1]
			c.launch_z = d["launch"][2]
	return c


func _check_col(c: Phys.Col, d: Dictionary, what: String) -> void:
	_same(c.id, int(d["id"]), what + " id")
	_same(c.tag, d["tag"], what + " tag")
	_near(c.cx, d["c"][0], what + " cx")
	_near(c.cy, d["c"][1], what + " cy")
	_near(c.cz, d["c"][2], what + " cz")
	_near(c.hx, d["h"][0], what + " hx")
	_near(c.hy, d["h"][1], what + " hy")
	_near(c.hz, d["h"][2], what + " hz")
	_near(c.yaw, d["yaw"], what + " yaw")
	_near(c.vx, d["vel"][0], what + " vx")
	_near(c.vy, d["vel"][1], what + " vy")
	_near(c.vz, d["vel"][2], what + " vz")
	_near(c.ang_vel, d["angVel"], what + " angVel")
	_same(c.ice, d["ice"], what + " ice")
	_near(c.bounce, d["bounce"], what + " bounce")
	_same(c.has_conv, d["conveyor"] != null, what + " conveyor")
	if c.has_conv and d["conveyor"] != null:
		_near(c.conv_x, d["conveyor"][0], what + " conv x")
		_near(c.conv_z, d["conveyor"][1], what + " conv z")
	if d.has("slow"):
		_near(c.slow, d["slow"], what + " slow")
		_near(c.jump, d["jump"], what + " jump")
		_near(c.jelly, d["jelly"], what + " jelly")
		_near(c.slope, d["slope"], what + " slope")
		_same(c.slide, d["slide"], what + " slide")
		_same(c.has_boost, d["boost"] != null, what + " boost")
		if c.has_boost and d["boost"] != null:
			_near(c.boost_x, d["boost"][0], what + " boost x")
			_near(c.boost_z, d["boost"][1], what + " boost z")
		_same(c.has_launch, d["launch"] != null, what + " launch")
		if c.has_launch and d["launch"] != null:
			_near(c.launch_x, d["launch"][0], what + " launch x")
			_near(c.launch_y, d["launch"][1], what + " launch y")
			_near(c.launch_z, d["launch"][2], what + " launch z")


func _check_body(b: Phys.Body, d: Dictionary, what: String) -> bool:
	var ok := true
	ok = _near(b.px, d["p"][0], what + " px") and ok
	ok = _near(b.py, d["p"][1], what + " py") and ok
	ok = _near(b.pz, d["p"][2], what + " pz") and ok
	ok = _near(b.vx, d["v"][0], what + " vx") and ok
	ok = _near(b.vy, d["v"][1], what + " vy") and ok
	ok = _near(b.vz, d["v"][2], what + " vz") and ok
	ok = _same(b.grounded, d["grounded"], what + " grounded") and ok
	ok = _same(b.ground_id, int(d["groundId"]), what + " groundId") and ok
	ok = _near(b.gvx, d["groundVel"][0], what + " gvx") and ok
	ok = _near(b.gvz, d["groundVel"][2], what + " gvz") and ok
	ok = _same(b.on_ice, d["onIce"], what + " onIce") and ok
	ok = _near(b.coyote, d["coyote"], what + " coyote") and ok
	ok = _near(b.tumble, d["tumble"], what + " tumble") and ok
	if d.has("slow"):
		ok = _near(b.slow, d["slow"], what + " slow") and ok
		ok = _near(b.jump_k, d["jumpK"], what + " jumpK") and ok
		ok = _near(b.boost, d["boost"], what + " boost") and ok
		ok = _near(b.flight, d["flight"], what + " flight") and ok
		ok = _same(b.zip, int(d["zip"]), what + " zip") and ok
		ok = _near(b.zip_s, d["zipS"], what + " zipS") and ok
		ok = _near(b.cool, d["cool"], what + " cool") and ok
	if d.has("superJump"):
		ok = _near(b.super_jump, d["superJump"], what + " superJump") and ok
		ok = _near(b.shield, d["shield"], what + " shield") and ok
	return ok


func _test_physics() -> void:
	var g := _load("physics.json")
	var cols: Array = []
	for d: Dictionary in g["cols"]:
		cols.append(_col_from(d))
	var inp: Array = g["inputs"]
	var states: Array = g["states"]
	var other: Array = g["other"]
	var b := Phys.Body.new()
	b.set_pos(1, 2, 1)
	var before := _fails
	for i in inp.size():
		cols[5].yaw = i * H * 1.4
		Phys.step_body(b, inp[i][0], inp[i][1], inp[i][2], cols, H)
		Phys.push_apart(b, other[0], other[1], other[2])
		if b.py < -9.0:
			b.set_pos(0, 3, 0)
			b.vx = 0.0
			b.vy = 0.0
			b.vz = 0.0
		if i % 10 == 9:
			var s: Dictionary = states[i / 10]
			if not _check_body(b, s, "physique pas %d" % i):
				break
			var gb: Variant = s["ground"]
			_near(Phys.ground_below(b.px, b.py + 0.3, b.pz, cols), -INF if gb == null else gb, "sol sous le joueur, pas %d" % i)
	print("physique : %s" % ("OK" if _fails == before else "ÉCHEC"))


func _test_levels() -> void:
	var g := _load("levels.json")
	for l: Dictionary in g["levels"]:
		var level: Dictionary = l["level"]
		var name: String = level["name"]
		var before := _fails
		var crumbled := {}
		if int(l["crumbleIdx"]) >= 0:
			crumbled[int(l["crumbleIdx"])] = 1.0
		for snap: Dictionary in l["snapshots"]:
			var cols := Level.build_colliders(level, snap["t"], crumbled)
			var want: Array = snap["cols"]
			if not _same(cols.size(), want.size(), "%s t=%s nombre de boîtes" % [name, snap["t"]]):
				continue
			for i in cols.size():
				_check_col(cols[i], want[i], "%s t=%s boîte %d" % [name, snap["t"], i])
		for f: Dictionary in l["fans"]:
			var a := Level.fan_accel(level, f["p"][0], f["p"][1], f["p"][2])
			for k in 3:
				_near(a[k], f["a"][k], "%s ventilateur" % name)
		_near(Level.kill_y(level), l["killY"], "%s killY" % name)

		# course simulée avec les entrées enregistrées
		var spawn: Array = l["spawn"]
		var kill_y: float = l["killY"]
		var inp: Array = l["inputs"]
		var states: Array = l["states"]
		var els: Array = level["elements"]
		var b := Phys.Body.new()
		b.set_pos(spawn[0], spawn[1], spawn[2])
		var run := {}
		var knocks := 0
		var bounces := 0
		var diverged := false
		for i in inp.size():
			var t := 3.0 + i * H
			var cols := Level.build_colliders(level, t, run)
			ParkourShared.pre_step(level, b, H)
			var contacts := Phys.step_body(b, inp[i][0], inp[i][1], inp[i][2], cols, H)
			var ev := ParkourShared.post_step(b, contacts)
			if ev["knocked"]:
				knocks += 1
			if ev["bounced"]:
				bounces += 1
			for k: int in ev["crumble"]:
				var e: Dictionary = els[k]
				if not run.has(k) or t >= run[k] + e["delay"] + e["respawn"]:
					run[k] = t
			if ev["killed"] or b.py < kill_y:
				b.set_pos(spawn[0], spawn[1], spawn[2])
				b.vx = 0.0
				b.vy = 0.0
				b.vz = 0.0
				b.tumble = 0.0
			if i % 10 == 9 and not _check_body(b, states[i / 10], "%s course pas %d" % [name, i]):
				diverged = true
				break
		if not diverged:
			_same(knocks, int(l["knocks"]), "%s éjections" % name)
			_same(bounces, int(l["bounces"]), "%s rebonds" % name)
		# lâcher du personnage sur chaque élément
		var total_knocks := 0
		var total_bounces := 0
		for d: Dictionary in l["drops"]:
			var k := int(d["k"])
			var t0: float = d["t0"]
			var db := Phys.Body.new()
			db.set_pos(d["at"][0], d["at"][1], d["at"][2])
			var seen := {}
			var kn := 0
			var bo := 0
			var st: Array = d["states"]
			var ok := true
			for i in 150:
				var t := t0 + i * H
				ParkourShared.pre_step(level, db, H)
				var contacts := Phys.step_body(db, 0.6, 0.3 if k % 2 else -0.3, i % 40 == 20, Level.build_colliders(level, t, seen), H)
				var ev := ParkourShared.post_step(db, contacts)
				if ev["knocked"]:
					kn += 1
				if ev["bounced"]:
					bo += 1
				for c: int in ev["crumble"]:
					if not seen.has(c):
						seen[c] = t
				if i % 10 == 9 and not _check_body(db, st[i / 10], "%s lâcher sur l'élément %d (%s) pas %d" % [name, k, els[k]["type"], i]):
					ok = false
					break
			if ok:
				_same(kn, int(d["knocks"]), "%s élément %d éjections" % [name, k])
				_same(bo, int(d["bounces"]), "%s élément %d rebonds" % [name, k])
			total_knocks += kn
			total_bounces += bo
		print("niveau %s : %s (%d éjections et %d rebonds rejoués)" % [name, "OK" if _fails == before else "ÉCHEC", total_knocks, total_bounces])
	for t: Dictionary in g["times"]:
		_same(ParkourShared.format_time(t["s"]), t["text"], "format du temps %s" % t["s"])


func _check_snapshots(level: Dictionary, snaps: Array, what: String) -> void:
	for snap: Dictionary in snaps:
		var cols := Level.build_colliders(level, snap["t"])
		var want: Array = snap["cols"]
		if not _same(cols.size(), want.size(), "%s t=%s nombre de boîtes" % [what, snap["t"]]):
			continue
		for i in cols.size():
			_check_col(cols[i], want[i], "%s t=%s boîte %d" % [what, snap["t"], i])


## Vague 1 : tous les nouveaux types (rouleaux, poinçonneurs, guillotines, plateaux, balayeurs, grande roue, pistons,
## boule de démolition, étau, dalles clignotantes, lave, boules, faux mur, décor, panneau, brouillard).
func _test_wave(name: String) -> void:
	var g := _load(name + ".json")
	var level: Dictionary = g["level"]
	var els: Array = level["elements"]
	var before := _fails
	_check_snapshots(level, g["snapshots"], name)
	# niveau brut (sans les défauts zod) : les valeurs par défaut de Godot doivent donner les mêmes boîtes
	var raw_snaps: Array = g["snapshots"].slice(0, 12)
	_check_snapshots(g["raw"], raw_snaps, "%s brut" % name)
	_near(Level.kill_y(g["raw"]), g["killY"], "%s brut killY" % name)
	_near(Level.kill_y(level), g["killY"], "%s killY" % name)
	var bottoms: Array = g["bottoms"]
	for i in els.size():
		_near(Level.element_bottom(els[i]), bottoms[i], "%s bas de l'élément %d" % [name, i])
	for f: Dictionary in g["fog"]:
		var p: Array = f["p"]
		var got: Variant = Level.fog_at(level, p[0], p[1], p[2])
		if f["f"] == null:
			_same(got, null, "brouillard en %s" % [p])
		elif _same(got != null, true, "brouillard en %s" % [p]):
			_near(got["density"], f["f"]["density"], "densité du brouillard")
			_same(got["color"], f["f"].get("color"), "couleur du brouillard")
	for r: Dictionary in g["pure"]:
		var t: float = r["t"]
		for o: Dictionary in r["els"]:
			var e: Dictionary = els[int(o["i"])]
			var what := "%s t=%s élément %d (%s)" % [name, t, int(o["i"]), e["type"]]
			if o.has("roll"):
				_near(Level.roller_angle(e, t), o["roll"], what + " rotation")
			if o.has("untilFall"):
				_near(Level.gate_until_fall(e, t), o["untilFall"], what + " avant la chute")
				var pr := Level.gate_profile(Level.frac(t / e["period"] + e["phase"]))
				_near(pr[0], o["profile"][0], what + " profil")
				_near(pr[1], o["profile"][1], what + " dérivée du profil")
			if o.has("spin"):
				_near(Level.spin_angle(e, t), o["spin"], what + " angle")
			if o.has("gap"):
				var gp := Level.crusher_gap(e, t)
				_near(gp[0], o["gap"][0], what + " écart")
				_near(gp[1], o["gap"][1], what + " vitesse d'écart")
			if o.has("blink"):
				var bs := Level.blink_state(e, t)
				_same(bs["solid"], o["blink"]["solid"], what + " solide")
				_near(bs["u"], o["blink"]["u"], what + " u")
				_near(bs["left"], o["blink"]["left"], what + " reste")
			if o.has("pulse"):
				var pu := Level.cannon_pulse(Level.frac(t / e["period"] + e["phase"]))
				_near(pu[0], o["pulse"][0], what + " sortie")
			if o.has("balls"):
				var balls := Level.boulder_balls(e, t)
				var want: Array = o["balls"]
				if _same(balls.size(), want.size(), what + " nombre de boules"):
					for j in balls.size():
						var c: Phys.Col = balls[j][0]
						_near(c.cx, want[j]["c"][0], what + " boule x")
						_near(c.cy, want[j]["c"][1], what + " boule y")
						_near(c.cz, want[j]["c"][2], what + " boule z")
						_near(balls[j][1], want[j]["k"], what + " avancée")
						_near(balls[j][2], want[j]["roll"], what + " roulement")
			if o.has("pop"):
				var want: Array = o["pop"]
				for k in want.size():
					var ps := Level.popper_state(e, k, t, int(o["i"]))
					_near(ps["ext"], want[k]["ext"], what + " castor %d sortie" % k)
					_near(ps["dext"], want[k]["dext"], what + " castor %d vitesse" % k)
					_same(ps["warn"], want[k]["warn"], what + " castor %d préavis" % k)
			if o.has("geyser"):
				var gs := Level.geyser_state(e, t)
				_same(gs["active"], o["geyser"]["active"], what + " éruption")
				_same(gs["warn"], o["geyser"]["warn"], what + " bouillonnement")
				_near(gs["left"], o["geyser"]["left"], what + " reste")
			if o.has("stones"):
				var got := Level.rockfall_stones(e, t, int(o["i"]))
				var want: Array = o["stones"]
				if _same(got.size(), want.size(), what + " nombre de pierres"):
					for j in got.size():
						var c: Phys.Col = got[j][0]
						_near(c.cy, want[j]["c"][1], what + " pierre y")
						_same(got[j][1], int(want[j]["k"]), what + " pierre k")
						_near(got[j][2], want[j]["f"], what + " pierre chute")
						_near(got[j][3], want[j]["x"], what + " pierre x")
						_near(got[j][4], want[j]["z"], what + " pierre z")
	for h: Array in g.get("hashes", []):
		_near(Level.hash01(int(h[0]), int(h[1])), h[2], "%s hash01(%d, %d)" % [name, int(h[0]), int(h[1])])

	# course pilotée vers l'avant, avec checkpoints, lave et chutes
	var cp_idx: Array = g["cpIdx"]
	var kill_y: float = g["killY"]
	var inp: Array = g["inputs"]
	var states: Array = g["states"]
	var start: Dictionary = els[Level.find_type(level, "start")]
	var cp := -1
	var spawn := Vector3(start["pos"][0], Level.top_of(start) + 0.2, start["pos"][2])
	var b := Phys.Body.new()
	b.set_pos(spawn.x, spawn.y, spawn.z)
	var knocks := 0
	var bounces := 0
	var kills := 0
	var falls := 0
	var diverged := false
	for i in inp.size():
		var t := 3.0 + i * H
		var cols := Level.build_colliders(level, t)
		ParkourShared.pre_step(level, b, H)
		var contacts := Phys.step_body(b, inp[i][0], inp[i][1], inp[i][2], cols, H)
		var ev := ParkourShared.post_step(b, contacts)
		if ev["knocked"]:
			knocks += 1
		if ev["bounced"]:
			bounces += 1
		if cp + 1 < cp_idx.size() and Level.on_pad(els[int(cp_idx[cp + 1])], b.px, b.py, b.pz):
			cp += 1
			var ce: Dictionary = els[int(cp_idx[cp])]
			spawn = Vector3(ce["pos"][0], Level.top_of(ce) + 0.2, ce["pos"][2])
		if ev["killed"] or b.py < kill_y:
			if ev["killed"]:
				kills += 1
			else:
				falls += 1
			b.set_pos(spawn.x, spawn.y, spawn.z)
			b.vx = 0.0
			b.vy = 0.0
			b.vz = 0.0
			b.tumble = 0.0
		if i % 10 == 9:
			var s: Dictionary = states[i / 10]
			var ok := _check_body(b, s, "%s course pas %d" % [name, i])
			ok = _same(cp, int(s["cp"]), "%s course checkpoint pas %d" % [name, i]) and ok
			ok = _same(ev["killed"], s["killed"], "%s course mort pas %d" % [name, i]) and ok
			ok = _same(ev["hazard"], int(s["hazard"]), "%s course élément mortel pas %d" % [name, i]) and ok
			if not ok:
				diverged = true
				break
	if not diverged:
		_same(knocks, int(g["knocks"]), "%s éjections" % name)
		_same(bounces, int(g["bounces"]), "%s rebonds" % name)
		_same(kills, int(g["kills"]), "%s morts" % name)
		_same(falls, int(g["falls"]), "%s chutes" % name)
	# lâchers et approches latérales sur chaque élément
	var tk := 0
	var tki := 0
	for d: Dictionary in g["drops"]:
		var k := int(d["k"])
		var t0: float = d["t0"]
		var db := Phys.Body.new()
		db.set_pos(d["at"][0], d["at"][1], d["at"][2])
		var kn := 0
		var bo := 0
		var ki := 0
		var st: Array = d["states"]
		var ok := true
		for i in 150:
			var t := t0 + i * H
			ParkourShared.pre_step(level, db, H)
			var contacts := Phys.step_body(db, d["mx"], d["mz"], d["jumps"] and i % 40 == 20, Level.build_colliders(level, t), H)
			var ev := ParkourShared.post_step(db, contacts)
			if ev["knocked"]:
				kn += 1
			if ev["bounced"]:
				bo += 1
			if ev["killed"]:
				ki += 1
			if i % 10 == 9 and not _check_body(db, st[i / 10], "%s lâcher %d sur l'élément %d (%s) pas %d" % [name, int(d["n"]), k, els[k]["type"], i]):
				ok = false
				break
		if ok:
			_same(kn, int(d["knocks"]), "%s élément %d éjections" % [name, k])
			_same(bo, int(d["bounces"]), "%s élément %d rebonds" % [name, k])
			_same(ki, int(d["kills"]), "%s élément %d morts" % [name, k])
		tk += kn
		tki += ki
	print("%s : %s (course : %d éjections, %d morts, %d chutes ; lâchers : %d éjections, %d morts)" % [name, "OK" if _fails == before else "ÉCHEC", knocks, kills, falls, tk, tki])


func _near3(v: Variant, w: Array, what: String) -> void:
	for k in 3:
		_near(v[k], w[k], what)


## Vague 2 : boue, gélatine, rampes et toboggan, speed pad, canon, trampoline directionnel, tyrolienne,
## téléporteur, bulles, zone lunaire, rafales — physique nouvelle comprise.
func _test_vague2() -> void:
	var g := _load("vague2.json")
	var before := _fails
	# physique seule sur un terrain de sols spéciaux
	var ph: Dictionary = g["physics"]
	var cols: Array = []
	for d: Dictionary in ph["cols"]:
		cols.append(_col_from(d))
	var inp: Array = ph["inputs"]
	var b := Phys.Body.new()
	b.set_pos(1, 2, 1)
	for i in inp.size():
		Phys.step_body(b, inp[i][0], inp[i][1], inp[i][2], cols, H)
		if b.py < -9.0 or absf(b.px) > 17.0 or absf(b.pz) > 17.0:
			b.set_pos(((i * 7) % 11) - 5, 3, ((i * 5) % 9) - 4)
			b.vx = 0.0
			b.vy = 0.0
			b.vz = 0.0
			Phys.clear_motion_state(b)
		if i % 10 == 9:
			var s: Dictionary = ph["states"][i / 10]
			if not _check_body(b, s, "vague2 physique pas %d" % i):
				break
			var gb: Variant = s["ground"]
			_near(Phys.ground_below(b.px, b.py + 0.3, b.pz, cols), -INF if gb == null else gb, "vague2 sol sous le joueur, pas %d" % i)
	for p: Dictionary in ph["probes"]:
		var gb: Variant = p["g"]
		_near(Phys.ground_below(p["p"][0], p["p"][1], p["p"][2], cols), -INF if gb == null else gb, "vague2 sol en %s" % [p["p"]])
	print("vague 2, physique : %s" % ("OK" if _fails == before else "ÉCHEC"))

	var level: Dictionary = g["level"]
	var els: Array = level["elements"]
	_check_snapshots(level, g["snapshots"], "vague2")
	_check_snapshots(g["raw"], g["snapshots"].slice(0, 10), "vague2 brut")
	_near(Level.kill_y(level), g["killY"], "vague2 killY")
	_near(Level.kill_y(g["raw"]), g["killY"], "vague2 brut killY")
	for o: Dictionary in g["els"]:
		var e: Dictionary = els[int(o["i"])]
		var what := "vague2 élément %d (%s)" % [int(o["i"]), e["type"]]
		_near(Level.element_bottom(e), o["bottom"], what + " bas")
		if o.has("slope"):
			_near(Level.ramp_slope(e), o["slope"], what + " pente")
			var cs := Level.ramp_corners(e)
			for k in 8:
				_near3(cs[k], o["corners"][k], what + " sommet %d" % k)
			var probes := [[0, 35], [1.5, 38], [-2, 41.7], [0, 100], [0.3, 183]]
			for k in probes.size():
				_near(Level.ramp_top_at(e, probes[k][0], probes[k][1]), o["tops"][k], what + " dessus")
		if o.has("boost"):
			var bv := Level.boost_vel(e)
			_near(bv[0], o["boost"][0], what + " boost x")
			_near(bv[1], o["boost"][1], what + " boost z")
		if o.has("launch"):
			_near3(Level.jumppad_vel(e), o["launch"], what + " lancer")
		if o.has("arc"):
			var arc := Level.launcher_arc(e)
			var arc7 := Level.launcher_arc(e, 7)
			if _same(arc.size(), o["arc"].size(), what + " points de l'arc"):
				for k in arc.size():
					_near3(arc[k], o["arc"][k], what + " arc")
			if _same(arc7.size(), o["arc7"].size(), what + " points de l'arc (7)"):
				for k in arc7.size():
					_near3(arc7[k], o["arc7"][k], what + " arc 7")
		if o.has("cable"):
			var cb := Level.zip_cable(e)
			_near3(cb["a"], o["cable"]["a"], what + " câble a")
			_near3(cb["b"], o["cable"]["b"], what + " câble b")
			_near3(cb["dir"], o["cable"]["dir"], what + " câble dir")
			_near(cb["len"], o["cable"]["len"], what + " câble longueur")
			var qs := [-1.0, 0.0, 3.3, 9.9, 50.0]
			for k in qs.size():
				_near3(Level.zip_feet(e, qs[k]), o["feet"][k], what + " pieds")
		if o.has("bubbles"):
			for bt: Dictionary in o["bubbles"]:
				var parts := Level.bubble_parts(e, bt["t"])
				if _same(parts.size(), bt["parts"].size(), what + " nombre de bulles"):
					for k in parts.size():
						var c: Phys.Col = parts[k][0]
						_near3([c.cx, c.cy, c.cz], bt["parts"][k]["c"], what + " bulle")
						_near(parts[k][1], bt["parts"][k]["u"], what + " bulle u")
						_near(parts[k][2], bt["parts"][k]["left"], what + " bulle reste")
		if o.has("gust"):
			var ts := [0.0, 0.4, 1.1, 2.9, 333.3]
			for k in ts.size():
				_near(Level.wind_gust(e, ts[k]), o["gust"][k], what + " rafale")
	for z: Dictionary in g["zones"]:
		var p: Array = z["p"]
		_near3(Level.wind_accel(level, p[0], p[1], p[2], z["t"]), z["wind"], "vague2 vent en %s" % [p])
		_near(Level.lowgrav_at(level, p[0], p[1], p[2]), z["g"], "vague2 gravité en %s" % [p])
		for k in els.size():
			_same(Level.in_zone(els[k], p[0], p[1], p[2]), z["inz"][k], "vague2 zone %d en %s" % [k, p])
	for l: Dictionary in g["launches"]:
		var lv := Level.launch_velocity(l["from"], l["to"], l["apex"], l["dt"])
		_near3(lv, l["v"], "vague2 vitesse du tir")
		_near(lv[3], l["T"], "vague2 durée du tir")
		var qs := [0.0, 0.3, lv[3] / 2.0, lv[3]]
		for k in 4:
			_near3(Level.ballistic_point(l["from"], lv, qs[k], l["dt"]), l["pts"][k], "vague2 point du tir")
	_near(Phys.jump_height(9.0, 24.0 * 0.35), g["misc"]["jh"], "vague2 hauteur de saut lunaire")
	_near(Phys.jump_height(10.8), g["misc"]["jh2"], "vague2 hauteur de saut")

	# courses pilotées (entrées enregistrées), réapparition au checkpoint avec clear_motion_state
	var cp_idx: Array = g["cpIdx"]
	var kill_y: float = g["killY"]
	var start: Dictionary = els[Level.find_type(level, "start")]
	var tot := {"launched": 0, "teleported": 0, "grabbed": 0, "released": 0, "boosted": 0, "bounces": 0}
	for r: Dictionary in g["races"]:
		var cp := int(r["cp0"])
		var se: Dictionary = start if cp < 0 else els[int(cp_idx[cp])]
		var spawn := Vector3(se["pos"][0], Level.top_of(se) + 0.2, se["pos"][2])
		var rb := Phys.Body.new()
		rb.set_pos(spawn.x, spawn.y, spawn.z)
		var n := {"launched": 0, "teleported": 0, "grabbed": 0, "released": 0, "boosted": 0, "bounces": 0, "knocks": 0, "falls": 0}
		var rin: Array = r["inputs"]
		var states: Array = r["states"]
		var diverged := false
		for i in rin.size():
			var t := 3.0 + i * H
			var pre := ParkourShared.pre_step(level, rb, H, t)
			for k: String in ["launched", "teleported", "grabbed", "released"]:
				if pre[k] >= 0:
					n[k] += 1
			var contacts := Phys.step_body(rb, rin[i][0], rin[i][1], rin[i][2], Level.build_colliders(level, t), H)
			var ev := ParkourShared.post_step(rb, contacts)
			if ev["knocked"]:
				n["knocks"] += 1
			if ev["bounced"]:
				n["bounces"] += 1
			if ev["boosted"]:
				n["boosted"] += 1
			if cp + 1 < cp_idx.size() and Level.on_pad(els[int(cp_idx[cp + 1])], rb.px, rb.py, rb.pz):
				cp += 1
				var ce: Dictionary = els[int(cp_idx[cp])]
				spawn = Vector3(ce["pos"][0], Level.top_of(ce) + 0.2, ce["pos"][2])
			if ev["killed"] or rb.py < kill_y:
				n["falls"] += 1
				rb.set_pos(spawn.x, spawn.y, spawn.z)
				rb.vx = 0.0
				rb.vy = 0.0
				rb.vz = 0.0
				rb.tumble = 0.0
				Phys.clear_motion_state(rb)
			if i % 10 == 9:
				var s: Dictionary = states[i / 10]
				var what := "vague2 course depuis %d, pas %d" % [int(r["cp0"]), i]
				var ok := _check_body(rb, s, what)
				ok = _same(cp, int(s["cp"]), what + " checkpoint") and ok
				for k: String in ["launched", "teleported", "grabbed", "released"]:
					ok = _same(pre[k], int(s["pre"][k]), what + " " + k) and ok
				ok = _same(ev["boosted"], s["boosted"], what + " boosted") and ok
				ok = _same(ev["bounced"], s["bounced"], what + " bounced") and ok
				if not ok:
					diverged = true
					break
		if not diverged:
			for k: String in n.keys():
				_same(n[k], int(r[k]), "vague2 course depuis %d : %s" % [int(r["cp0"]), k])
		for k: String in tot.keys():
			tot[k] += n[k]
	# lâchers sur / dans chaque élément
	var evs := 0
	for d: Dictionary in g["drops"]:
		var k := int(d["k"])
		var db := Phys.Body.new()
		db.set_pos(d["at"][0], d["at"][1], d["at"][2])
		var kn := 0
		var bo := 0
		var bs := 0
		var pr := 0
		var st: Array = d["states"]
		var ok := true
		for i in 240:
			var t: float = d["t0"] + i * H
			var pre := ParkourShared.pre_step(level, db, H, t)
			if pre["launched"] >= 0 or pre["teleported"] >= 0 or pre["grabbed"] >= 0 or pre["released"] >= 0:
				pr += 1
			var contacts := Phys.step_body(db, d["mx"], d["mz"], i % 50 == 25, Level.build_colliders(level, t), H)
			var ev := ParkourShared.post_step(db, contacts)
			if ev["knocked"]:
				kn += 1
			if ev["bounced"]:
				bo += 1
			if ev["boosted"]:
				bs += 1
			if i % 10 == 9 and not _check_body(db, st[i / 10], "vague2 lâcher %d sur l'élément %d (%s) pas %d" % [int(d["n"]), k, els[k]["type"], i]):
				ok = false
				break
		if ok:
			_same(kn, int(d["knocks"]), "vague2 élément %d éjections" % k)
			_same(bo, int(d["bounces"]), "vague2 élément %d rebonds" % k)
			_same(bs, int(d["boosts"]), "vague2 élément %d speed pad" % k)
			_same(pr, int(d["pres"]), "vague2 élément %d événements" % k)
		evs += pr
	print("vague 2 : %s (courses : %d tirs, %d téléports, %d tyroliennes, %d pas de speed pad, %d rebonds ; lâchers : %d événements)" % ["OK" if _fails == before else "ÉCHEC", tot["launched"], tot["teleported"], tot["grabbed"], tot["boosted"], tot["bounces"], evs])


func _body_from(d: Dictionary) -> Phys.Body:
	var b := Phys.Body.new()
	b.set_pos(d["p"][0], d["p"][1], d["p"][2])
	b.vx = d["v"][0]
	b.vy = d["v"][1]
	b.vz = d["v"][2]
	b.grounded = d["grounded"]
	b.ground_id = int(d["groundId"])
	b.gvx = d["groundVel"][0]
	b.gvy = d["groundVel"][1]
	b.gvz = d["groundVel"][2]
	b.on_ice = d["onIce"]
	b.coyote = d["coyote"]
	b.tumble = d["tumble"]
	b.slow = d["slow"]
	b.jump_k = d["jumpK"]
	b.boost = d["boost"]
	b.flight = d["flight"]
	b.zip = int(d["zip"])
	b.zip_s = d["zipS"]
	b.cool = d["cool"]
	b.super_jump = d["superJump"]
	b.shield = d["shield"]
	return b


## État de niveau Godot → même forme que le stOut du générateur, pour comparaison.
func _check_state(st: Dictionary, w: Dictionary, what: String) -> void:
	_same(st["crumbled"].size(), w["crumbled"].size(), what + " friables")
	for c: Array in w["crumbled"]:
		_near(st["crumbled"].get(int(c[0]), -1.0), c[1], what + " friable")
	_same(st["links"].size(), w["links"].size(), what + " liens")
	for l: Array in w["links"]:
		var got: Variant = st["links"].get(l[0])
		if _same(got != null, true, what + " lien " + str(l[0])):
			_near(got[0], l[1], what + " lien at")
			_near(got[1], l[2], what + " lien until")
	for key: String in ["levers", "tiles", "boxes"]:
		_same(st[key].size(), w[key].size(), what + " " + key)
		for c: Array in w[key]:
			_near(st[key].get(int(c[0]), -1.0), c[1], what + " " + key)
	for key: String in ["safe", "coins"]:
		var ks: Array = st[key].keys()
		ks.sort()
		_same(ks, w[key].map(func(x: Variant) -> int: return int(x)), what + " " + key)
	_same(st["bananas"].size(), w["bananas"].size(), what + " bananes")
	for bn: Array in w["bananas"]:
		var p: Variant = st["bananas"].get(int(bn[0]))
		if _same(p != null, true, what + " banane"):
			_near3(p, [bn[1], bn[2], bn[3]], what + " banane")


## Vague 3 : boutons, portes, leviers, trappes, dalles mémoire, boîtes, pièces, bananes ; bousculades, super saut, bouclier.
func _test_vague3() -> void:
	var g := _load("vague3.json")
	var before := _fails
	var level: Dictionary = g["level"]
	var els: Array = level["elements"]
	var me := "moi"
	_near(Level.kill_y(level), g["killY"], "vague3 killY")
	_near(Level.kill_y(g["raw"]), g["killY"], "vague3 brut killY")
	# séquence de messages → état, boîtes et fonctions pures
	var st := Level.new_state()
	var times: Array = g["times"]
	for step: Dictionary in g["seq"]:
		var what := "vague3 après %s" % [step["m"]]
		_same(ParkourShared.apply_level_msg(st, step["m"], me), step["used"], what + " (message reconnu)")
		_check_state(st, step["st"], what)
		for sn: Dictionary in step["snaps"]:
			var cols := Level.build_colliders(level, sn["t"], st)
			var raw_cols := Level.build_colliders(g["raw"], sn["t"], st)
			var want: Array = sn["cols"]
			if _same(cols.size(), want.size(), what + " t=%s nombre de boîtes" % sn["t"]) and _same(raw_cols.size(), want.size(), what + " brut, nombre de boîtes"):
				for k in cols.size():
					_check_col(cols[k], want[k], what + " t=%s boîte %d" % [sn["t"], k])
					_check_col(raw_cols[k], want[k], what + " brut boîte %d" % k)
		for k in times.size():
			var t: float = times[k]
			var p: Dictionary = step["pure"][k]
			var links := ["porte1", "trappe", "rien"]
			for l in 3:
				_same(Level.link_open(st, links[l], t), p["open"][l], what + " lien %s ouvert t=%s" % [links[l], t])
			_near(Level.door_openness(els[4], st, t), p["door"][0], what + " porte t=%s" % t)
			_near(Level.door_openness(els[10], st, t), p["door"][1], what + " trappe t=%s" % t)
			_same(Level.lever_down(els[12], 12, st, t), p["lever"], what + " levier t=%s" % t)
			_same(Level.box_ready(6, st, t), p["box"][0], what + " boîte 6 t=%s" % t)
			_same(Level.box_ready(17, st, t), p["box"][1], what + " boîte 17 t=%s" % t)
	for ef: Dictionary in g["effects"]:
		var b := Phys.Body.new()
		_same(ParkourShared.apply_effect_msg(b, ef["m"], me, ef["now"]), ef["ok"], "vague3 effet %s" % [ef["m"]])
		_near(b.super_jump, ef["superJump"], "vague3 effet super saut")
		_near(b.shield, ef["shield"], "vague3 effet bouclier")
	# grille mémoire et détections
	var tiles := Level.memory_tiles(els[8])
	if _same(tiles.size(), g["tiles"].size(), "vague3 nombre de dalles mémoire"):
		for k in tiles.size():
			var c: Phys.Col = tiles[k]
			var w: Dictionary = g["tiles"][k]
			_near3([c.cx, c.cy, c.cz], w["c"], "vague3 dalle %d centre" % k)
			_near3([c.hx, c.hy, c.hz], w["h"], "vague3 dalle %d taille" % k)
			_near(c.yaw, w["yaw"], "vague3 dalle %d lacet" % k)
	for h: Dictionary in g["hits"]:
		var p: Array = h["p"]
		_same(Level.memory_tile_at(els[8], p[0], p[2]), int(h["tile"]), "vague3 dalle sous %s" % [p])
		for k in els.size():
			_same(Level.stands_on(els[k], p[0], p[1], p[2]), h["on"][k], "vague3 posé sur %d en %s" % [k, p])
			_same(Level.touches(els[k], p[0], p[1], p[2]), h["touch"][k], "vague3 touche %d en %s" % [k, p])
	_same([Level.memory_key(0, 0), Level.memory_key(8, 11), Level.memory_key(12, 1023)], g["keys"].map(func(x: Variant) -> int: return int(x)), "vague3 clés mémoire")
	for lay: Dictionary in g["layouts"]:
		var seq: Array = lay["rnd"]
		var pos := [0]
		var rnd := func() -> float:
			pos[0] += 1
			return seq[pos[0] - 1]
		var trap := ParkourShared.memory_layout(int(lay["cols"]), int(lay["rows"]), lay["traps"], rnd)
		_same(trap, lay["trap"], "vague3 grille %dx%d" % [int(lay["cols"]), int(lay["rows"])])
		_same(pos[0], seq.size(), "vague3 tirages de la grille")
	# bousculades
	var trips := 0
	for j: Dictionary in g["jostles"]:
		var op: Array = j["op"]
		var ov: Array = j["ov"]
		var b := _body_from(j["before"])
		var r1 := Phys.jostle(b, op[0], op[1], op[2], ov[0], ov[2])
		_same(r1, j["r1"], "vague3 bousculade")
		_check_body(b, j["after"], "vague3 bousculade")
		var b2 := _body_from(j["before"])
		var init := {} if j["jostle"] == null else {"jostle": j["jostle"]}
		_same(ParkourShared.parkour_jostle(init, b2, op[0], op[1], op[2], ov[0], ov[2]), j["r2"], "vague3 bousculade (réglage %s)" % [j["jostle"]])
		_check_body(b2, j["after2"], "vague3 bousculade (réglage)")
		if r1:
			trips += 1
	# super saut, bouclier, bits de pose
	var cols: Array = []
	for d: Dictionary in g["cols"]:
		cols.append(_col_from(d))
	for x: Dictionary in g["fx"]:
		var inp: Array = x["inputs"]
		var b := Phys.Body.new()
		b.set_pos(0, 0.01, 0)
		b.super_jump = x["superJump"]
		b.shield = x["shield"]
		var kn := 0
		var ok := true
		for i in inp.size():
			var t := i * H
			cols[1].yaw = t * 2.5
			var contacts := Phys.step_body(b, inp[i][0], inp[i][1], inp[i][2], cols, H)
			if ParkourShared.post_step(b, contacts)["knocked"]:
				kn += 1
			if absf(b.px) > 19.0 or absf(b.pz) > 19.0 or b.py < -5.0:
				b.set_pos(0, 0.01, 0)
				b.vx = 0.0
				b.vy = 0.0
				b.vz = 0.0
				Phys.clear_motion_state(b)
			if i % 10 == 9:
				var s: Dictionary = x["states"][i / 10]
				var what := "vague3 effets (super %s, bouclier %s) pas %d" % [x["superJump"], x["shield"], i]
				ok = _check_body(b, s, what) and _same(Protocol.pose_flags(b), int(s["flags"]), what + " drapeaux")
				if not ok:
					break
		if ok:
			_same(kn, int(x["knocks"]), "vague3 frappes (bouclier %s)" % x["shield"])
	# courses avec état évolutif et bousculades d'un autre joueur, réglage activé puis désactivé
	var start: Dictionary = els[0]
	var kill_y: float = g["killY"]
	var timeline: Array = g["timeline"]
	for r: Dictionary in g["races"]:
		var rs := Level.new_state()
		var b := Phys.Body.new()
		b.set_pos(start["pos"][0], Level.top_of(start) + 0.2, start["pos"][2])
		var inp: Array = r["inputs"]
		var others: Array = r["others"]
		var ti := 0
		var n := {"trips": 0, "falls": 0, "knocks": 0}
		var ok := true
		for i in inp.size():
			var t := 3.0 + i * H
			while ti < timeline.size() and timeline[ti][0] <= t:
				ParkourShared.apply_level_msg(rs, timeline[ti][1], me)
				ParkourShared.apply_effect_msg(b, timeline[ti][1], me, t)
				ti += 1
			ParkourShared.pre_step(level, b, H, t)
			var contacts := Phys.step_body(b, inp[i][0], inp[i][1], inp[i][2], Level.build_colliders(level, t, rs), H)
			var o: Array = others[i]
			if ParkourShared.parkour_jostle({"jostle": r["jostle"]}, b, o[0], o[1], o[2], o[3], o[5]):
				n["trips"] += 1
			var ev := ParkourShared.post_step(b, contacts)
			if ev["knocked"]:
				n["knocks"] += 1
			if ev["killed"] or b.py < kill_y:
				n["falls"] += 1
				b.set_pos(start["pos"][0], Level.top_of(start) + 0.2, start["pos"][2])
				b.vx = 0.0
				b.vy = 0.0
				b.vz = 0.0
				b.tumble = 0.0
				Phys.clear_motion_state(b)
			if i % 10 == 9:
				var s: Dictionary = r["states"][i / 10]
				var what := "vague3 course (bousculades %s) pas %d" % [r["jostle"], i]
				if not (_check_body(b, s, what) and _same(Protocol.pose_flags(b), int(s["flags"]), what + " drapeaux")):
					ok = false
					break
		if ok:
			for k: String in n.keys():
				_same(n[k], int(r[k]), "vague3 course (bousculades %s) : %s" % [r["jostle"], k])
	print("vague 3 : %s (%d trébuchements sur %d bousculades)" % ["OK" if _fails == before else "ÉCHEC", trips, g["jostles"].size()])


func _test_mortar() -> void:
	var g := _load("mortar.json")
	var before := _fails
	for r: Dictionary in g["rings"]:
		var n := int(r["n"])
		_near(MortarShared.ring_radius(n), r["radius"], "rayon n=%d" % n)
		var plots: Array = r["plots"]
		for i in plots.size():
			var p: Dictionary = plots[i]
			var what := "n=%d île %d" % [n, i]
			_near(MortarShared.plot_cx(i, n), p["center"][0], what + " centre x")
			_near(MortarShared.plot_cz(i, n), p["center"][2], what + " centre z")
			_near(MortarShared.plot_yaw(i, n), p["yaw"], what + " lacet")
			var loc := MortarShared.to_local(i, n, p["w"][0], p["w"][1])
			_near(loc[0], p["local"][0], what + " local x")
			_near(loc[1], p["local"][1], what + " local z")
			var w := MortarShared.to_world(i, n, 1.25, -2.5)
			_near(w[0], p["world"][0], what + " monde x")
			_near(w[1], p["world"][1], what + " monde z")
			var bc := MortarShared.block_center(i, 2, 1, 5, n)
			for k in 3:
				_near(bc[k], p["block"][k], what + " bloc")
			var cell: Variant = MortarShared.cell_at(i, n, p["w"][0], p["w"][1])
			if p["cell"] == null:
				_same(cell, null, what + " case")
			elif _same(cell != null, true, what + " case"):
				_same(cell.x, int(p["cell"]["x"]), what + " case x")
				_same(cell.y, int(p["cell"]["z"]), what + " case z")
	for s: Dictionary in g["shots"]:
		var l := MortarShared.launch(1.5, 0.2, -2.5, s["yaw"], s["power"])
		for k in 3:
			_near(l[k], s["p"][k], "tir position")
			_near(l[3 + k], s["v"][k], "tir vitesse")
		_near(MortarShared.shell_range(l), s["range"], "portée")
		_near(MortarShared.shell_range(l, 2.0), s["range2"], "portée à y=2")
		var times := [0.0, 0.4, 1.7]
		for k in 3:
			var p := MortarShared.shell_at(s["p"], s["v"], times[k])
			_near(p.x, s["at"][k][0], "obus x")
			_near(p.y, s["at"][k][1], "obus y")
			_near(p.z, s["at"][k][2], "obus z")
	for z: Dictionary in g["zone"]:
		_near(MortarShared.zone_radius(z["t"], z["s"], z["e"]), z["r"], "rayon de zone")
	var blocks := {}
	for b: Dictionary in g["blocks"]:
		var blk := {"plot": int(b["plot"]), "x": int(b["x"]), "y": int(b["y"]), "z": int(b["z"]), "mat": b["mat"], "hp": b["hp"]}
		blocks[MortarShared.block_key(blk["plot"], blk["x"], blk["y"], blk["z"])] = blk
	var cols := MortarShared.colliders(5, blocks, 1)
	var want: Array = g["cols"]
	if _same(cols.size(), want.size(), "nombre de boîtes du mortier"):
		for i in cols.size():
			_check_col(cols[i], want[i], "mortier boîte %d" % i)
	for h: Dictionary in g["heights"]:
		_same(MortarShared.column_height(blocks, int(h["p"]), int(h["x"]), int(h["z"])), int(h["h"]), "hauteur de colonne")
	print("mortier : %s" % ("OK" if _fails == before else "ÉCHEC"))


## Égalité profonde : nombres à EPS près (le JSON ne distingue pas entiers et flottants), clés de `want` seulement si `subset`.
func _deep(got: Variant, want: Variant, what: String, subset := false) -> void:
	if (got is float or got is int) and (want is float or want is int):
		_near(float(got), float(want), what)
	elif want is Dictionary:
		if not got is Dictionary:
			_same(type_string(typeof(got)), "Dictionary", what)
			return
		for k: Variant in want:
			_deep(got.get(k), want[k], "%s.%s" % [what, k], subset)
		if not subset:
			for k: Variant in got:
				if not want.has(k):
					_same(k, null, what + " : clé en trop")
	elif want is Array:
		if not got is Array or got.size() != want.size():
			_same(got, want, what)
			return
		for i in want.size():
			_deep(got[i], want[i], "%s[%d]" % [what, i], subset)
	else:
		_same(got, want, what)


func _test_server() -> void:
	var d := _load("server.json")
	for l: Dictionary in d["levels"]:
		var what: String = l["level"]["name"]
		var err: Array = []
		var got := LevelStore.normalize(l["raw"], err)
		_same(err, [], what + " : erreurs de lecture")
		got["name"] = l["raw"]["name"]
		_deep(got, l["level"], what + " (schéma)", true)
		var v := LevelValidate.validate(got)
		_same(v["ok"], l["ok"], what + " : terminable")
		_deep(v["path"], l["path"], what + " : chemin")
		_deep(v["stats"]["pathLength"], l["pathLength"], what + " : longueur")
	_deep(GameMetas.all(), d["metas"], "fiches des jeux")
	for st: Dictionary in d["settings"]:
		_deep(Scoring.sanitize_settings(st["raw"], d["metas"]), st["out"], "réglages %s" % JSON.stringify(st["raw"]))
	var seq: Array = d["seq"]
	for r: Dictionary in d["rounds"]:
		var k: Array = [int(r["start"])]
		var list := Scoring.build_round_list(r["settings"], func() -> float:
			k[0] += 1
			return seq[(k[0] - 1) % seq.size()])
		_deep(list, r["list"], "ordre des manches")
	for r: Dictionary in d["results"]:
		_deep(Scoring.score_round(r["results"]), r["rows"], "points")
	print("serveur : OK (%d niveaux)" % d["levels"].size())
