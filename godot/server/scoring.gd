class_name Scoring
extends RefCounted
## Scores et réglages de session (portage de shared/src/scoring.ts).


## Points d'une manche : n pour le premier (+2 de bonus), puis n-1, n-2… ; 1 point pour le dernier.
static func points_for_rank(rank: int, n: int) -> int:
	return maxi(1, n - rank) + (2 if rank == 0 else 0)


## RoundResult[] ({id, rank, label}) → RoundResultRow[] ({id, rank, label, points}), triés par rang.
static func score_round(results: Array) -> Array:
	var n := results.size()
	var sorted := results.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rank"] < b["rank"])
	var out: Array = []
	for r: Dictionary in sorted:
		out.append({"id": r["id"], "rank": r["rank"], "label": r["label"], "points": points_for_rank(r["rank"], n)})
	return out


## Liste ordonnée de groupes d'ex æquo ([[{id, label}…]…]) → rangs (0, 0, 2, 3…).
static func ranks_from_groups(groups: Array) -> Array:
	var out: Array = []
	var rank := 0
	for g: Array in groups:
		for e: Dictionary in g:
			out.append({"id": e["id"], "rank": rank, "label": e["label"]})
		rank += g.size()
	return out


static func default_game_settings(meta: Dictionary) -> Dictionary:
	var out := {}
	for k: String in meta["settings"]:
		var d: Variant = meta["settings"][k]["default"]
		out[k] = d.duplicate() if d is Array else d
	return out


static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and v.is_valid_float():
		return v.to_float()
	if v is bool:
		return 1.0 if v else 0.0
	return NAN


## Nettoie des réglages reçus du réseau ou d'un fichier : seules les valeurs valides sont gardées.
static func sanitize_settings(raw: Variant, metas: Array) -> Dictionary:
	var r: Dictionary = raw if raw is Dictionary else {}
	var ids: Array = metas.map(func(m: Dictionary) -> String: return m["id"])
	var pick := func(a: Variant) -> Array:
		var out: Array = []
		if a is Array:
			for x: Variant in a:
				if x is String and ids.has(x):
					out.append(x)
		return out
	var rn := _num(r.get("rounds"))
	var rounds := clampi(roundi(rn) if is_finite(rn) and rn != 0.0 else 5, 1, 15)
	var games: Array = []
	for g: String in pick.call(r.get("games")):
		if not games.has(g):
			games.append(g)
	if games.is_empty():
		games = ids.duplicate()
	var order: String = r["order"] if r.get("order") in ["random", "list"] else "alternate"
	var list: Array = pick.call(r.get("list")).slice(0, rounds)
	while list.size() < rounds:
		list.append(games[list.size() % games.size()])
	var game := {}
	var rg: Dictionary = r["game"] if r.get("game") is Dictionary else {}
	for meta: Dictionary in metas:
		var src: Dictionary = rg[meta["id"]] if rg.get(meta["id"]) is Dictionary else {}
		var dst := default_game_settings(meta)
		for k: String in meta["settings"]:
			var def: Dictionary = meta["settings"][k]
			if not src.has(k) or src[k] == null:
				continue
			var v: Variant = src[k]
			match def["type"]:
				"number":
					var n := _num(v)
					if is_finite(n):
						dst[k] = clampf(n, def["min"], def["max"])
				"bool":
					dst[k] = _truthy(v)
				"multi":
					if v is Array:
						var arr: Array = []
						for x: Variant in v:
							if x is String:
								arr.append(x)
						dst[k] = arr.slice(0, 100)
		game[meta["id"]] = dst
	return {"rounds": rounds, "order": order, "games": games, "list": list, "game": game}


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	if v is String:
		return v != ""
	return v != null


## Ordre des manches. `rnd` : Callable → [0, 1[.
static func build_round_list(s: Dictionary, rnd: Callable = Callable()) -> Array:
	if not rnd.is_valid():
		rnd = randf
	var out: Array = []
	var games: Array = s["games"]
	for i in int(s["rounds"]):
		if s["order"] == "list":
			out.append(s["list"][i] if i < s["list"].size() else games[i % games.size()])
		elif s["order"] == "random":
			# aléatoire, mais jamais trois fois le même jeu d'affilée s'il y a le choix
			var g: String = games[floori(rnd.call() * games.size())]
			if games.size() > 1 and i >= 2 and out[i - 1] == g and out[i - 2] == g:
				for x: String in games:
					if x != g:
						g = x
						break
			out.append(g)
		else:
			out.append(games[i % games.size()])
	return out
