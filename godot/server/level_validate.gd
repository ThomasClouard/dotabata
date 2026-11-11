class_name LevelValidate
extends RefCounted
## Vérifie qu'un niveau est terminable et calcule le chemin suivi par les bots : graphe des surfaces atteignables
## d'un saut, avec la physique du jeu. Portage de shared/src/level-validate.ts (le MCP garde la version TypeScript ;
## les deux sont comparées par les tests de parité).

const SAFETY := 0.85


class VNode extends RefCounted:
	var i := 0
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	var top_min := 0.0
	var top_max := 0.0
	var bottom := 0.0
	var v0 := Phys.JUMP_V
	var speed := Phys.SPEED
	var g := 1.0
	var fan := false
	var parts: Array = []  # vide = pas de sous-parties
	var arrive_only := false
	var has_boost := false
	var boost_dir: Array = [0.0, 0.0]
	var boost_speed := 0.0
	var has_ballistic := false
	var bal_p: Array = []
	var bal_v: Array = []
	var has_exits := false
	var exits: Array = []


static func _box_node(i: int, c: Array, hx: float, hz: float, yaw: float, top: float) -> VNode:
	var co := absf(cos(yaw))
	var si := absf(sin(yaw))
	var ex := co * hx + si * hz
	var ez := si * hx + co * hz
	var n := VNode.new()
	n.i = i
	n.min_x = c[0] - ex
	n.max_x = c[0] + ex
	n.min_z = c[2] - ez
	n.max_z = c[2] + ez
	n.top_min = top
	n.top_max = top
	n.bottom = top
	return n


static func _zone_node(i: int, c: Array, hx: float, hz: float, yaw: float, bottom: float, top: float, p: Array, v: Array) -> VNode:
	var n := _box_node(i, c, hx, hz, yaw, top)
	n.fan = true
	n.bottom = bottom
	n.has_ballistic = true
	n.bal_p = p
	n.bal_v = v
	return n


static func _make_node(e: Dictionary, i: int) -> VNode:
	var pos: Array = e["pos"]
	var size: Array = e["size"]
	var yaw: float = e.get("yaw", 0.0)
	var type: String = e["type"]
	var top: float = pos[1] + size[1] / 2.0
	var n := _box_node(i, pos, size[0] / 2.0, size[2] / 2.0, yaw, top)
	match type:
		"launcher":
			return _zone_node(i, pos, size[0] / 2.0, size[2] / 2.0, yaw, pos[1] - size[1] / 2.0, top, [e["to"][0], e["to"][1], e["to"][2]], [0.0, 0.0, 0.0])
		"teleport":
			var ev: Array = e.get("exitVel", [0.0, 0.0, 0.0])
			return _zone_node(i, pos, size[0] / 2.0, size[2] / 2.0, yaw, pos[1] - size[1] / 2.0, top, [e["to"][0], e["to"][1], e["to"][2]], [ev[0], ev[1], ev[2]])
		"zipline":
			# accroche : les pieds doivent passer près de pos − zipHang ; lâcher au bout avec l'élan du câble
			var cb := Level.zip_cable(e)
			var f := Level.zip_feet(e, 0.0)
			var r := Phys.ZIP_GRAB * 0.7
			var sp: float = e.get("speed", 10.0)
			var dir: Array = cb["dir"]
			return _zone_node(i, f, r, r, 0.0, f[1] - r, f[1] + r, Level.zip_feet(e, cb["len"]), [dir[0] * sp, dir[1] * sp, dir[2] * sp])
		"jumppad":
			n.has_ballistic = true
			n.bal_p = [pos[0], top, pos[2]]
			n.bal_v = Level.jumppad_vel(e)
			return n
		"mud":
			n.v0 = Phys.JUMP_V * e.get("jumpFactor", 0.6)
			n.speed = Phys.SPEED * e.get("slow", 0.45)
			return n
		"jelly":
			n.v0 = Phys.JUMP_V * e.get("jumpFactor", 1.2)
			return n
		"boost":
			var bv := Level.boost_vel(e)
			var bs: float = e.get("speed", 18.0)
			n.has_boost = true
			n.boost_dir = [bv[0] / bs, bv[1] / bs]
			n.boost_speed = bs
			return n
		"bubble":
			n.top_max = top + e.get("rise", 6.0) * 0.85  # on saute avant que la bulle éclate
			return n
		"ramp":
			# tranches de ≤ 2 m le long de la pente ; toboggan : on ne repart que de la tranche la plus basse
			var s := Level.ramp_slope(e)
			var k := maxi(1, ceili(size[2] / 2.0))
			var dz: float = size[2] / k
			for j in k:
				var lz: float = -size[2] / 2.0 + (j + 0.5) * dz
				var c := [pos[0] + lz * sin(yaw), pos[1], pos[2] + lz * cos(yaw)]
				var p := _box_node(i, c, size[0] / 2.0, dz / 2.0, yaw, top + s * lz)
				p.top_min = top + s * lz - absf(s * dz) / 2.0
				p.top_max = top + s * lz + absf(s * dz) / 2.0
				if e.get("slide", false) and j != (0 if s > 0.0 else k - 1):
					p.arrive_only = true
				n.parts.append(p)
	if type == "turntable":
		# disque : on ne compte que le carré central (0.75 × rayon), sûr quelle que soit la rotation
		var r: float = 0.75 * (size[0] / 2.0)
		return _box_node(i, pos, r, r, 0.0, top)
	if type == "ferris":
		# 12 positions échantillonnées d'une nacelle sur son orbite (le bot attend la bonne)
		var radius: float = e.get("radius", 5.0)
		for k in 12:
			var th := (k / 12.0) * PI * 2.0
			var lx := radius * cos(th)
			var c := [pos[0] + lx * cos(yaw), pos[1] + radius * sin(th), pos[2] - lx * sin(yaw)]
			n.parts.append(_box_node(i, c, size[0] / 2.0, size[2] / 2.0, yaw, c[1] + size[1] / 2.0))
	if type == "pistons":
		var count := int(e.get("count", 4))
		var w: float = size[0] / count
		for k in count:
			var lx: float = -size[0] / 2.0 + (k + 0.5) * w
			var c := [pos[0] + lx * cos(yaw), pos[1], pos[2] - lx * sin(yaw)]
			var p := _box_node(i, c, w / 2.0, size[2] / 2.0, yaw, top)
			p.top_max = top + e.get("height", 2.0)
			n.parts.append(p)
	if not n.parts.is_empty():
		# enveloppe globale ; les sauts se calculent sur les parties
		n.min_x = INF
		n.max_x = -INF
		n.min_z = INF
		n.max_z = -INF
		n.top_min = INF
		n.top_max = -INF
		for p: VNode in n.parts:
			n.min_x = minf(n.min_x, p.min_x)
			n.max_x = maxf(n.max_x, p.max_x)
			n.min_z = minf(n.min_z, p.min_z)
			n.max_z = maxf(n.max_z, p.max_z)
			n.top_min = minf(n.top_min, p.top_min)
			n.top_max = maxf(n.top_max, p.top_max)
		return n
	if type == "fan":
		var force: Array = e.get("force", [0.0, 42.0, 0.0])
		if force[1] <= Phys.GRAVITY + 4.0:
			return null  # ventilateur latéral ou trop faible : simple perturbation
		n.fan = true
		n.bottom = pos[1] - size[1] / 2.0
		n.v0 = 5.0  # élan résiduel en sortant par le haut
		return n
	if not type in Level.STANDABLE:
		return null
	if type == "moving":
		var d: Array = e["delta"]
		n.min_x = minf(n.min_x, n.min_x + d[0])
		n.max_x = maxf(n.max_x, n.max_x + d[0])
		n.min_z = minf(n.min_z, n.min_z + d[2])
		n.max_z = maxf(n.max_z, n.max_z + d[2])
		n.top_min = minf(top, top + d[1])
		n.top_max = maxf(top, top + d[1])
	if type == "trampoline":
		n.v0 = e.get("bounce", 15.0)
	return n


static func _gap(a: VNode, b: VNode) -> float:
	var gx := maxf(0.0, maxf(b.min_x - a.max_x, a.min_x - b.max_x))
	var gz := maxf(0.0, maxf(b.min_z - a.max_z, a.min_z - b.max_z))
	return sqrt(gx * gx + gz * gz)


## Coût du saut de a vers b, ou -1 s'il est infaisable. Les longs sauts coûtent plus cher : le chemin retenu est le plus sûr.
static func _jump_cost(a: VNode, b: VNode) -> float:
	if not a.parts.is_empty() or not b.parts.is_empty():
		var best := -1.0
		for pa: VNode in (a.parts if not a.parts.is_empty() else [a]):
			if pa.arrive_only:
				continue
			for pb: VNode in (b.parts if not b.parts.is_empty() else [b]):
				var c := _jump_cost(pa, pb)
				if c >= 0.0 and (best < 0.0 or c < best):
					best = c
		return best
	var g := _gap(a, b)
	var gg := Phys.GRAVITY * a.g
	var speed := a.speed
	if a.has_boost:
		# speed pad : élan complet seulement si la cible est dans la direction du pad
		var dx := (b.min_x + b.max_x - a.min_x - a.max_x) / 2.0
		var dz := (b.min_z + b.max_z - a.min_z - a.max_z) / 2.0
		if dx * a.boost_dir[0] + dz * a.boost_dir[1] >= 0.7 * sqrt(dx * dx + dz * dz):
			speed = a.boost_speed
	var reach: float
	if b.fan:
		# il faut entrer dans la colonne d'air : par le côté ou en sautant dedans
		if a.top_min > b.top_max + 0.5:
			reach = Phys.jump_reach(b.top_max - a.top_min, a.v0, speed, gg)
		else:
			var up := maxf(0.0, b.bottom - a.top_max)
			if up > Phys.jump_height(a.v0, gg) * SAFETY:
				return -1.0
			reach = Phys.jump_reach(up, a.v0, speed, gg)
	else:
		reach = Phys.jump_reach(b.top_min - a.top_max, a.v0, speed, gg)
	reach *= SAFETY
	if reach < 0.0 or g > reach:
		return -1.0
	return 0.5 + g * (1.0 + (2.0 * g) / maxf(reach, 0.1))


## Surface où retombe un vol libre parti de p à la vitesse v (première traversée d'un dessus en descendant), -1 sinon.
static func _landing(nodes: Array, from: VNode, p: Array, v: Array, level: Dictionary) -> int:
	var gg := Phys.GRAVITY * Level.lowgrav_at(level, p[0], p[1], p[2])
	var tol := 0.3
	var best := -1
	var best_t := INF
	for n: VNode in nodes:
		if n == from or n.fan:
			continue
		for q: VNode in (n.parts if not n.parts.is_empty() else [n]):
			var disc: float = v[1] * v[1] + 2.0 * gg * (p[1] + 0.3 - q.top_max)  # 0.3 : un point posé sur la dalle compte
			if disc < 0.0:
				continue
			var t: float = (v[1] + sqrt(disc)) / gg
			var x: float = p[0] + v[0] * t
			var z: float = p[2] + v[2] * t
			if x < q.min_x - tol or x > q.max_x + tol or z < q.min_z - tol or z > q.max_z + tol or t >= best_t:
				continue
			best_t = t
			best = n.i
	return best


## { nodes: Array[VNode], adj: { i: [[j, coût], …] } }
static func _build_graph(level: Dictionary) -> Dictionary:
	var nodes: Array = []
	var els: Array = level["elements"]
	for i in els.size():
		var n := _make_node(els[i], i)
		if n != null:
			nodes.append(n)
	# zones lunaires : gravité réduite au départ des surfaces qui y sont
	for n: VNode in nodes:
		for q: VNode in (n.parts if not n.parts.is_empty() else [n]):
			q.g = Level.lowgrav_at(level, (q.min_x + q.max_x) / 2.0, q.top_max + 0.05, (q.min_z + q.max_z) / 2.0)
	for n: VNode in nodes:
		if n.has_ballistic:
			var to := _landing(nodes, n, n.bal_p, n.bal_v, level)
			n.has_exits = true
			n.exits = [to] if to >= 0 else []
	var adj := {}
	for a: VNode in nodes:
		var edges: Array = []
		if a.has_exits:
			for to: int in a.exits:
				edges.append([to, 0.5])
		else:
			for b: VNode in nodes:
				var c := -1.0 if b == a else _jump_cost(a, b)
				if c >= 0.0:
					edges.append([b.i, c])
		adj[a.i] = edges
	return {"nodes": nodes, "adj": adj}


## Plus courts chemins (Dijkstra) depuis `from` : prédécesseur de chaque surface atteignable (ordre de découverte).
static func _bfs(adj: Dictionary, from: int) -> Dictionary:
	var prev := {from: -1}
	var dist := {from: 0.0}
	var done := {}
	while true:
		var cur := -1
		var best := INF
		for i: int in dist:
			if not done.has(i) and dist[i] < best:
				best = dist[i]
				cur = i
		if cur < 0:
			break
		done[cur] = true
		for e: Array in adj.get(cur, []):
			var nx: int = e[0]
			if best + e[1] < dist.get(nx, INF):
				dist[nx] = best + e[1]
				prev[nx] = cur
	return prev


static func _path_to(prev: Dictionary, to: int) -> Array:
	if not prev.has(to):
		return []
	var out: Array = []
	var c := to
	while c != -1:
		out.push_front(c)
		c = prev[c]
	return out


static func _label(level: Dictionary, i: int) -> String:
	var e: Dictionary = level["elements"][i]
	var id: String = str(e.get("id", ""))
	return "#%d (%s%s)" % [i, e["type"], (" « %s »" % id) if id != "" else ""]


## { ok, errors, warnings, path, stats: {elements, checkpoints, pathLength, estimatedSeconds} }
static func validate(level: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var els: Array = level["elements"]
	var starts: Array = []
	var finishes: Array = []
	var cps: Array = []
	for i in els.size():
		match els[i]["type"]:
			"start":
				starts.append(i)
			"finish":
				finishes.append(i)
			"checkpoint":
				cps.append(i)
	if starts.size() != 1:
		errors.append("Il faut exactement un élément \"start\" (trouvé : %d)." % starts.size())
	if finishes.is_empty():
		errors.append("Il faut au moins un élément \"finish\".")
	var graph := _build_graph(level)
	var nodes: Array = graph["nodes"]
	var adj: Dictionary = graph["adj"]
	var path: Array = []
	var path_length := 0.0
	if errors.is_empty():
		var from_start := _bfs(adj, starts[0])
		# le parcours doit s'enchaîner : départ → checkpoint 1 → … → arrivée
		var cur: int = starts[0]
		path.append(cur)
		for target: int in cps + [-1]:
			var prev := _bfs(adj, cur)
			var goal := target
			if target == -1:
				goal = finishes[0]
				for f: int in finishes:
					if prev.has(f):
						goal = f
						break
			var seg := _path_to(prev, goal)
			if seg.is_empty():
				var reached: Array = prev.keys().map(func(i: int) -> String: return _label(level, i))
				errors.append("%s est inatteignable depuis %s. Dernières surfaces atteintes : %s." % [_label(level, goal), _label(level, cur), ", ".join(reached.slice(-4))])
				break
			path.append_array(seg.slice(1))
			cur = goal
		for n: VNode in nodes:
			if not from_start.has(n.i):
				warnings.append("%s n'est atteignable par aucun saut depuis le départ." % _label(level, n.i))
		for k in range(1, path.size()):
			var a: Array = els[path[k - 1]]["pos"]
			var b: Array = els[path[k]]["pos"]
			path_length += sqrt((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2 + (b[2] - a[2]) ** 2)
	return {
		"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "path": path,
		"stats": {"elements": els.size(), "checkpoints": cps.size(), "pathLength": roundi(path_length), "estimatedSeconds": roundi((path_length / Phys.SPEED) * 1.8)},
	}
