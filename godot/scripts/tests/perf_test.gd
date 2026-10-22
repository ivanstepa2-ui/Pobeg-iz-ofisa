extends Node
## Замер нагрузки на глубоком этаже: 24 зомби + 2 отряда людей, герой посреди этажа (его ищут и гонят).
##   godot --path . --rendering-driver opengl3 --resolution 1280x600 -- --perftest 12
## Печатает время логики (мс на кадр), FPS, число вызовов отрисовки и объектов в кадре.

var game: Node


func run(g: Node, floor_n: int) -> void:
	game = g
	await _frames(10)
	game.floor_num = floor_n
	game._load_floor(floor_n, false)
	game.state = "play"
	game.autotest = true        # бессмертие героя (бот не ведёт — стоит на месте)
	game._spawn_squad(5)
	game._spawn_squad(3)
	# 0.20: с 20-го этажа — добить бандитов до потолка волн с пожарных лестниц (худший случай)
	if floor_n >= 20 and floor_n < 30:
		while game.enemies.filter(func(e): return e is Human).size() < game.escape_cap():
			game._spawn_squad(3, false, game.L.escapes[0] if not game.L.escapes.is_empty() else {})
	var p: Player = game.player
	var c := Vector2i(game.L.W / 2, game.L.H / 2)
	var cell: Vector2i = game.L.nearest_walkable(c.x, c.y, 6)
	p.position = Vector3(cell.x + 0.5, 0, cell.y + 0.5)
	# все враги знают, где герой — худший случай: погоня всей толпой
	for e in game.enemies:
		e.foe = p
		e.alert()
	await _frames(30)
	var logic_ms: Array = []
	var frame_ms: Array = []
	var draws: Array = []
	var objs: Array = []
	for i in 300:
		var t0 := Time.get_ticks_usec()
		game._update_world(1.0 / 30.0, false)
		logic_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		await game.get_tree().process_frame
		frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	logic_ms.sort()
	print("[perf] этаж %d, размер %dx%d, врагов %d (людей %d)" % [floor_n, game.L.W, game.L.H, game.enemies.size(),
		game.enemies.filter(func(e): return e is Human).size()])
	print("[perf] логика ИИ: в среднем %.2f мс, 95%% кадров ≤ %.2f мс, максимум %.2f мс" % [
		_avg(logic_ms), logic_ms[int(logic_ms.size() * 0.95)], logic_ms[-1]])
	print("[perf] весь _process: %.2f мс; FPS %d; вызовов отрисовки %d (макс %d); объектов в кадре %d" % [
		_avg(frame_ms), Engine.get_frames_per_second(), int(_avg(draws)), int(draws.max()), int(_avg(objs))])
	game.get_tree().quit()


func _avg(a: Array) -> float:
	var s := 0.0
	for x in a: s += x
	return s / maxf(1, a.size())


func _frames(n: int) -> void:
	for i in n:
		await game.get_tree().process_frame
