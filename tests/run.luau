--!strict
-- Тесты чистой логики. Запуск из корня репозитория: `lune run tests/run`

local Production = require("../src/shared/Sim/Production")
local Recipes = require("../src/shared/Config/Recipes")
local Grid = require("../src/shared/Sim/Grid")
local GridConfig = require("../src/shared/Config/Grid")
local BuildCommand = require("../src/shared/Sim/BuildCommand")
local Buildings = require("../src/shared/Config/Buildings")
local Text = require("../src/shared/Config/Text")
local Roads = require("../src/shared/Sim/Roads")
local RoadsConfig = require("../src/shared/Config/Roads")
local Logistics = require("../src/shared/Sim/Logistics")
local TrucksConfig = require("../src/shared/Config/Trucks")
local Construction = require("../src/shared/Sim/Construction")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`  ok  {name}`)
	else
		failed += 1
		print(`  FAIL {name}\n       {err}`)
	end
end

local function eq(actual: any, expected: any, what: string)
	if actual ~= expected then
		error(`{what}: ожидалось {expected}, получено {actual}`, 2)
	end
end

local function run(recipe, state, seconds: number, workers: number)
	for _ = 1, seconds do
		Production.tick(recipe, state, 1, workers)
	end
end

test("лесозаготовка выпускает бревно за полный цикл", function()
	local r = Recipes.forestry
	local s = Production.new()
	run(r, s, r.cycleSeconds, r.workers)
	eq(s.output.logs, 1, "брёвна")
	eq(s.status, "working", "статус")
end)

test("половина рабочих — вдвое медленнее", function()
	local r = Recipes.forestry
	local s = Production.new()
	run(r, s, r.cycleSeconds, r.workers / 2)
	eq(s.output.logs, nil, "брёвна после одного цикла")
	run(r, s, r.cycleSeconds, r.workers / 2)
	eq(s.output.logs, 1, "брёвна после двух циклов")
end)

test("без рабочих здание стоит", function()
	local r = Recipes.forestry
	local s = Production.new()
	eq(Production.tick(r, s, 1, 0), "no_workers", "статус")
end)

test("лесопилка без брёвен ждёт сырьё", function()
	local r = Recipes.sawmill
	local s = Production.new()
	eq(Production.tick(r, s, 1, r.workers), "no_input", "статус")
end)

test(
	"лесопилка списывает брёвна в начале цикла и выпускает доски",
	function()
		local r = Recipes.sawmill
		local s = Production.new()
		eq(Production.deliver(r, s, "logs", 4), 4, "принято брёвен")
		Production.tick(r, s, 1, r.workers)
		eq(s.input.logs, 2, "брёвна после старта цикла")
		run(r, s, r.cycleSeconds - 1, r.workers)
		eq(s.output.boards, 1, "доски")
	end
)

test("склад не принимает больше ёмкости и чужие ресурсы", function()
	local r = Recipes.sawmill
	local s = Production.new()
	eq(Production.deliver(r, s, "logs", 100), r.storage, "принято брёвен")
	eq(Production.deliver(r, s, "grain", 5), 0, "принято зерна")
end)

test(
	"полный выходной склад останавливает здание, не тратя сырьё",
	function()
		local r = Recipes.sawmill
		local s = Production.new()
		s.output.boards = r.storage
		Production.deliver(r, s, "logs", 2)
		eq(Production.tick(r, s, 1, r.workers), "output_full", "статус")
		eq(s.input.logs, 2, "брёвна не списаны")
		eq(Production.take(s, "boards", 5), 5, "забрано досок")
		eq(Production.tick(r, s, 1, r.workers), "working", "статус после разгрузки")
	end
)

test("у каждого рецепта корректные числа", function()
	for id, r in Recipes do
		assert(r.cycleSeconds > 0, `{id}: cycleSeconds`)
		assert(r.workers >= 0, `{id}: workers`)
		assert(r.storage > 0, `{id}: storage`)
		for res, n in r.outputs do
			assert(n > 0 and n <= r.storage, `{id}: выход {res}`)
		end
		for res, n in r.inputs do
			assert(n > 0 and n <= r.storage, `{id}: вход {res}`)
		end
	end
end)

-- Сетка

local function smallGrid()
	-- 10 × 10 клеток по 4 студа, центр в (0, 0): регион от -20 до 20
	return Grid.new({ cellSize = 4, regionCells = 10 }, 0, 0)
end

test("мировая точка переводится в клетку и обратно", function()
	local g = smallGrid()
	local c = Grid.toCell(g, -20, -20)
	assert(c, "угол региона в сетке")
	eq(c.x, 0, "x угла")
	eq(c.z, 0, "z угла")
	local c2 = Grid.toCell(g, 1, -1)
	assert(c2, "центр в сетке")
	eq(c2.x, 5, "x")
	eq(c2.z, 4, "z")
	local wx, wz = Grid.cellCenter(g, 5, 4)
	eq(wx, 2, "центр x")
	eq(wz, -2, "центр z")
end)

test("точка за краем региона не даёт клетку", function()
	local g = smallGrid()
	eq(Grid.toCell(g, 20, 0), nil, "правый край")
	eq(Grid.toCell(g, -20.01, 0), nil, "левее левого края")
end)

test("поворот меняет стороны прямоугольника", function()
	eq(#Grid.footprint(0, 0, 3, 2, 0), 6, "клеток")
	local w, d = Grid.rotatedSize(3, 2, 1)
	eq(w, 2, "ширина после поворота")
	eq(d, 3, "глубина после поворота")
	local cx, cz = Grid.areaCenter(smallGrid(), 0, 0, 3, 2, 1)
	eq(cx, -16, "центр x")
	eq(cz, -14, "центр z")
end)

test("занятые клетки и край региона мешают стройке", function()
	local g = smallGrid()
	local ok = Grid.place(g, "a", 2, 2, 3, 3, 0)
	eq(ok, true, "первое здание")
	local ok2, err2 = Grid.canPlace(g, 4, 4, 2, 2, 0)
	eq(ok2, false, "пересечение")
	eq(err2, "occupied", "причина")
	local ok3, err3 = Grid.canPlace(g, 9, 9, 2, 1, 0)
	eq(ok3, false, "за краем")
	eq(err3, "out_of_bounds", "причина")
	eq(Grid.canPlace(g, 5, 5, 2, 2, 0), true, "рядом свободно")
	eq(Grid.objectAt(g, 3, 3), "a", "владелец клетки")
end)

test("снос освобождает клетки, повторный id не ставится", function()
	local g = smallGrid()
	Grid.place(g, "a", 0, 0, 2, 2, 0)
	eq(Grid.place(g, "a", 5, 5, 1, 1, 0), false, "тот же id")
	eq(Grid.remove(g, "a"), true, "снос")
	eq(Grid.objectAt(g, 1, 1), nil, "клетка свободна")
	eq(Grid.remove(g, "a"), false, "повторный снос")
	eq(Grid.canPlace(g, 0, 0, 0, 1, 0), false, "нулевой размер")
end)

test("конфиг сетки корректный", function()
	assert(GridConfig.cellSize > 0, "cellSize")
	assert(GridConfig.regionCells > 0 and GridConfig.regionCells % 1 == 0, "regionCells")
end)

-- Команда стройки

local testBuildings = {
	hut = { sizeX = 2, sizeZ = 2, era = 0 },
	tower = { sizeX = 1, sizeZ = 1, era = 2 },
}

test("правильная команда стройки разбирается", function()
	local cmd, err = BuildCommand.parse(testBuildings, 0, "hut", 3, 4, 1)
	eq(err, nil, "ошибка")
	assert(cmd, "команда")
	eq(cmd.typeId, "hut", "тип")
	eq(cmd.x, 3, "x")
	eq(cmd.rotation, 1, "поворот")
end)

test("мусор от клиента отклоняется", function()
	local cases = {
		{ 123, 0, 0, 0 },
		{ "hut", 1.5, 0, 0 },
		{ "hut", 0, "0", 0 },
		{ "hut", 0, 0, 4 },
		{ "hut", 0, 0, -1 },
		{ "hut", 0 / 0, 0, 0 },
		{ "hut", math.huge, 0, 0 },
		{ "hut", 0, 0, nil },
	}
	for i, c in cases do
		local cmd, err = BuildCommand.parse(testBuildings, 0, c[1], c[2], c[3], c[4])
		eq(cmd, nil, `случай {i}`)
		eq(err, "bad_args", `причина {i}`)
	end
end)

test("неизвестное и закрытое здание не строится", function()
	local _, err1 = BuildCommand.parse(testBuildings, 0, "castle", 0, 0, 0)
	eq(err1, "unknown_building", "неизвестное")
	local _, err2 = BuildCommand.parse(testBuildings, 0, "tower", 0, 0, 0)
	eq(err2, "locked", "закрытое")
	local cmd = BuildCommand.parse(testBuildings, 2, "tower", 0, 0, 0)
	assert(cmd, "после открытия эпохи")
end)

test("конфиг зданий корректный", function()
	for id, b in Buildings do
		assert(b.sizeX >= 1 and b.sizeX % 1 == 0, `{id}: sizeX`)
		assert(b.sizeZ >= 1 and b.sizeZ % 1 == 0, `{id}: sizeZ`)
		assert(b.height > 0, `{id}: height`)
		assert(#b.color == 3 and #b.roofColor == 3, `{id}: цвета`)
		assert(b.name.ru ~= "" and b.name.en ~= "", `{id}: название`)
		local recipe = Recipes[id]
		if recipe then
			eq(b.era, recipe.era, `{id}: эпоха совпадает с рецептом`)
		end
	end
end)

test("у всех ресурсов и статусов есть тексты", function()
	for id, r in Recipes do
		for res in r.outputs do
			assert(Text.resources[res], `{id}: нет текста для {res}`)
		end
		for res in r.inputs do
			assert(Text.resources[res], `{id}: нет текста для {res}`)
		end
	end
	for _, status in { "working", "no_input", "output_full", "no_workers" } do
		assert(Text.status[status], `нет текста статуса {status}`)
	end
end)

-- Дороги

local function roadLine(r, x1, z1, x2, z2)
	for _, c in Roads.linePath(x1, z1, x2, z2) do
		Roads.add(r, c.x, c.z)
	end
end

test("линия дороги идёт буквой «Г» без повторов", function()
	local p = Roads.linePath(2, 1, 4, 3)
	eq(#p, 5, "клеток")
	eq(p[1].x, 2, "начало x")
	eq(p[3].x, 4, "поворот x")
	eq(p[3].z, 1, "поворот z")
	eq(p[5].z, 3, "конец z")
	eq(#Roads.linePath(5, 5, 5, 5), 1, "одна клетка")
	local back = Roads.linePath(3, 3, 1, 3)
	eq(#back, 3, "назад по X")
	eq(back[3].x, 1, "конец назад")
	eq(#Roads.linePath(0, 4, 0, 0), 5, "назад по Z")
end)

test(
	"дороги добавляются, удаляются и не выходят за край",
	function()
		local r = Roads.new(10)
		eq(Roads.add(r, 1, 1), true, "добавлена")
		eq(Roads.add(r, 1, 1), false, "повтор")
		eq(Roads.add(r, 10, 0), false, "за краем")
		eq(r.count, 1, "число")
		eq(Roads.remove(r, 1, 1), true, "удалена")
		eq(Roads.has(r, 1, 1), false, "нет дороги")
		eq(r.count, 0, "число после удаления")
	end
)

test(
	"подъезд к зданию — дорога у края, но не по диагонали",
	function()
		local r = Roads.new(20)
		-- здание 3×2 с углом в (5, 5) занимает x 5..7, z 5..6
		Roads.add(r, 4, 4) -- диагональ, не считается
		eq(#Roads.entrances(r, 5, 5, 3, 2), 0, "только диагональ")
		Roads.add(r, 8, 6) -- справа от края
		local e = Roads.entrances(r, 5, 5, 3, 2)
		eq(#e, 1, "один подъезд")
		eq(e[1].x, 8, "x подъезда")
	end
)

test("поиск пути по дорогам находит кратчайший путь", function()
	local r = Roads.new(20)
	roadLine(r, 0, 0, 10, 0)
	roadLine(r, 10, 0, 10, 5)
	roadLine(r, 0, 0, 0, 5)
	roadLine(r, 0, 5, 10, 5)
	local path = Roads.findPath(r, { { x = 0, z = 0 } }, { { x = 10, z = 5 } })
	assert(path, "путь есть")
	eq(#path, 16, "длина пути")
	eq(path[1].x, 0, "старт")
	eq(path[#path].x, 10, "финиш x")
	eq(path[#path].z, 5, "финиш z")
	for i = 2, #path do
		local dx = math.abs(path[i].x - path[i - 1].x)
		local dz = math.abs(path[i].z - path[i - 1].z)
		eq(dx + dz, 1, `шаг {i} к соседу`)
	end
end)

test("без связи пути нет, разрыв дороги рвёт путь", function()
	local r = Roads.new(20)
	roadLine(r, 0, 0, 5, 0)
	roadLine(r, 8, 0, 12, 0)
	eq(Roads.findPath(r, { { x = 0, z = 0 } }, { { x = 12, z = 0 } }), nil, "разрыв")
	roadLine(r, 5, 0, 8, 0)
	assert(
		Roads.findPath(r, { { x = 0, z = 0 } }, { { x = 12, z = 0 } }),
		"после стройки есть"
	)
	Roads.remove(r, 6, 0)
	eq(Roads.findPath(r, { { x = 0, z = 0 } }, { { x = 12, z = 0 } }), nil, "после сноса нет")
	local same = Roads.findPath(r, { { x = 1, z = 0 } }, { { x = 1, z = 0 } })
	assert(same, "старт совпадает с целью")
	eq(#same, 1, "путь из одной клетки")
end)

test("команда дороги проверяет числа и длину", function()
	local cmd = BuildCommand.parseRoad(10, 0, 0, 4, 5)
	assert(cmd, "10 клеток можно")
	local _, err = BuildCommand.parseRoad(10, 0, 0, 5, 5)
	eq(err, "too_long", "11 клеток нельзя")
	local _, err2 = BuildCommand.parseRoad(10, 0, 0, 1.5, 0)
	eq(err2, "bad_args", "дробное")
	local _, err3 = BuildCommand.parseRoad(10, "0", 0, 1, 0)
	eq(err3, "bad_args", "строка")
	assert(RoadsConfig.maxCellsPerCommand >= 1, "конфиг дорог")
end)

-- Логистика

local truckConfig = { capacity = 6, minLoad = 2, cellsPerSecond = 2, loadSeconds = 1, unloadSeconds = 1 }

-- Тестовый мир: дорога по z = 0 от x = 0 до 20.
-- Автопарк «depot» подъезд в x = 0, лесозаготовка «f» в x = 10, лесопилка «s» в x = 20.
local function makeWorld()
	local r = Roads.new(32)
	roadLine(r, 0, 0, 20, 0)
	local w = {
		roads = r,
		stock = { f = 10, s = 0, s2 = 0 },
		exists = { depot = true, f = true, s = true, s2 = true },
		released = {},
		demands = {},
		caps = {}, -- ёмкость склада получателя (нет — без ограничения)
	}
	local doors =
		{ depot = { x = 0, z = 0 }, f = { x = 10, z = 0 }, s = { x = 20, z = 0 }, s2 = { x = 15, z = 0 } }
	w.api = {
		findPath = function(from, to)
			return Roads.findPath(r, from, to)
		end,
		entrances = function(id)
			if not w.exists[id] then
				return {}
			end
			return { doors[id] }
		end,
		isRoad = function(c)
			return Roads.has(r, c.x, c.z)
		end,
		take = function(id, _res, amount)
			local n = math.min(w.stock[id], amount)
			w.stock[id] -= n
			return n
		end,
		deliver = function(id, _res, amount)
			local cap = w.caps[id]
			if cap then
				amount = math.min(amount, cap - w.stock[id])
			end
			w.stock[id] += amount
			return amount
		end,
		release = function(job, side)
			table.insert(w.released, side)
		end,
		-- Другие получатели: id -> свободное место.
		claimDemand = function(_res, amount)
			for id, space in w.demands do
				if space > 0 and w.exists[id] then
					local n = math.min(space, amount)
					w.demands[id] -= n
					return id, n
				end
			end
			return nil, 0
		end,
	}
	return w
end

local function runTruck(t, w, seconds)
	for _ = 1, seconds * 4 do
		Logistics.step(t, 0.25, truckConfig, w.api)
	end
end

test("заказы: полный склад первым, мелочь не возим", function()
	local jobs = Logistics.candidates({
		{ id = "a", resource = "logs", amount = 1, full = false },
		{ id = "b", resource = "logs", amount = 4, full = false },
		{ id = "c", resource = "logs", amount = 2, full = true },
		{ id = "d", resource = "grain", amount = 9, full = false },
	}, { { id = "s", resource = "logs", amount = 5 } }, truckConfig)
	eq(#jobs, 2, "заказов")
	eq(jobs[1].from, "c", "полный первым")
	eq(jobs[2].from, "b", "потом по объёму")
	eq(jobs[2].amount, 4, "объём")
	local big = Logistics.candidates(
		{ { id = "b", resource = "logs", amount = 50, full = true } },
		{ { id = "s", resource = "logs", amount = 40 } },
		truckConfig
	)
	eq(big[1].amount, 6, "не больше вместимости")
end)

test(
	"грузовик везёт брёвна от лесозаготовки на лесопилку",
	function()
		local w = makeWorld()
		local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
		local job = Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
		assert(job, "заказ выдан")
		eq(t.state, "to_pickup", "едет за грузом")
		runTruck(t, w, 5) -- 10 клеток по 2 в секунду
		eq(t.state, "loading", "грузится")
		runTruck(t, w, 1)
		eq(t.state, "to_dropoff", "везёт")
		eq(t.cargo, 6, "в кузове")
		eq(w.stock.f, 4, "у лесозаготовки осталось")
		runTruck(t, w, 5)
		runTruck(t, w, 1)
		eq(t.state, "idle", "свободен")
		eq(w.stock.s, 6, "привезено")
		eq(#w.released, 2, "резервы сняты")
		Logistics.sendHome(t, w.api)
		eq(t.state, "returning", "едет домой")
		runTruck(t, w, 10)
		eq(t.state, "idle", "дома")
		eq(t.cell.x, 0, "у автопарка")
	end
)

test("положение грузовика плавно между клетками", function()
	local w = makeWorld()
	local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
	Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
	Logistics.step(t, 0.25, truckConfig, w.api) -- полклетки
	local x, z = Logistics.position(t)
	eq(x, 0.5, "x")
	eq(z, 0, "z")
end)

test("без дороги до получателя заказ не выдаётся", function()
	local w = makeWorld()
	Roads.remove(w.roads, 15, 0)
	local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
	eq(
		Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api),
		nil,
		"заказ"
	)
	eq(t.state, "idle", "стоит")
end)

test(
	"снос дороги до погрузки срывает заказ и снимает резервы",
	function()
		local w = makeWorld()
		local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
		Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
		runTruck(t, w, 1)
		Roads.remove(w.roads, 5, 0)
		runTruck(t, w, 2)
		eq(t.state, "idle", "заказ сорван")
		eq(#w.released, 2, "оба резерва сняты")
		eq(t.cargo, 0, "груза нет")
	end
)

test(
	"получателя снесли в пути: груз едет домой и ждёт, а не пропадает",
	function()
		local w = makeWorld()
		local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
		Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
		runTruck(t, w, 6)
		eq(t.state, "to_dropoff", "везёт")
		w.exists.s = false
		Logistics.step(t, 0.25, truckConfig, w.api)
		eq(t.state, "returning", "сразу повернул домой")
		eq(t.cargo, 6, "груз в кузове")
		runTruck(t, w, 10)
		eq(t.state, "idle", "ждёт дома")
		eq(t.cell.x, 0, "у автопарка")
		local again =
			Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
		eq(again, nil, "с грузом новый заказ не берёт")
		-- Появился новый получатель — грузовик везёт груз ему.
		w.demands.s2 = 10
		Logistics.redirect(t, w.api)
		eq(t.state, "to_dropoff", "везёт новому получателю")
		runTruck(t, w, 10)
		eq(w.stock.s2, 6, "доставлено")
		eq(t.cargo, 0, "кузов пуст")
	end
)

test(
	"получателя снесли в пути, но есть другой: едет сразу к нему",
	function()
		local w = makeWorld()
		w.demands.s2 = 4
		w.caps.s2 = 4
		local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
		Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
		runTruck(t, w, 6)
		w.exists.s = false
		Logistics.step(t, 0.25, truckConfig, w.api)
		eq(t.state, "to_dropoff", "везёт")
		assert(t.job and t.job.to == "s2", "к другому получателю")
		runTruck(t, w, 6)
		eq(w.stock.s2, 4, "принято сколько влезло")
		eq(t.cargo, 2, "остаток в кузове")
		eq(t.state, "returning", "с остатком домой")
	end
)

test(
	"получателя снесли до погрузки: заказ срывается сразу",
	function()
		local w = makeWorld()
		local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
		Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
		runTruck(t, w, 1)
		w.exists.s = false
		Logistics.step(t, 0.25, truckConfig, w.api)
		eq(t.state, "idle", "сорван сразу")
		eq(w.stock.f, 10, "у отправителя ничего не забрали")
	end
)

test("объезд: снесли участок, но есть другая дорога", function()
	local w = makeWorld()
	roadLine(w.roads, 4, 0, 4, 2)
	roadLine(w.roads, 4, 2, 8, 2)
	roadLine(w.roads, 8, 2, 8, 0)
	local t = Logistics.newTruck("t1", "depot", { x = 0, z = 0 })
	Logistics.dispatch(t, { { from = "f", to = "s", resource = "logs", amount = 6 } }, w.api)
	runTruck(t, w, 1)
	Roads.remove(w.roads, 6, 0)
	runTruck(t, w, 10)
	assert(
		t.state == "loading" or t.state == "to_dropoff",
		`доехал в объезд, состояние {t.state}`
	)
end)

test("конфиг грузовиков корректный", function()
	assert(TrucksConfig.perDepot >= 1, "perDepot")
	assert(TrucksConfig.capacity >= TrucksConfig.minLoad, "capacity")
	assert(TrucksConfig.cellsPerSecond > 0, "скорость")
end)

-- Стройка

test(
	"стройплощадка принимает только нужное и не больше нормы",
	function()
		local site = Construction.new({ boards = 8 }, 10)
		eq(Construction.deliver(site, "boards", 6), 6, "первая партия")
		eq(Construction.deliver(site, "logs", 5), 0, "чужой материал")
		eq(Construction.deliver(site, "boards", 6), 2, "только остаток")
		eq(Construction.remaining(site, "boards"), 0, "остаток")
		eq(Construction.hasAllMaterials(site), true, "всё привезено")
	end
)

test("стройка идёт только когда все материалы на месте", function()
	local site = Construction.new({ boards = 4, logs = 2 }, 5)
	Construction.deliver(site, "boards", 4)
	eq(Construction.tick(site, 10), false, "без брёвен не строится")
	eq(site.progress, 0, "прогресс стоит")
	Construction.deliver(site, "logs", 2)
	eq(Construction.tick(site, 3), false, "строится")
	eq(Construction.tick(site, 3), true, "достроено")
	eq(Construction.deliver(site, "boards", 1), 0, "после стройки не принимает")
end)

test(
	"у зданий со стройкой корректная цена и тексты материалов",
	function()
		local any = false
		for id, b in Buildings do
			if b.cost then
				any = true
				assert(b.buildSeconds and b.buildSeconds >= 0, `{id}: buildSeconds`)
				for res, n in b.cost do
					assert(n > 0 and n % 1 == 0, `{id}: цена {res}`)
					assert(Text.resources[res], `{id}: нет текста для {res}`)
				end
			end
		end
		assert(any, "хотя бы одно здание строится из материалов")
		assert(
			Buildings.forestry.cost == nil and Buildings.sawmill.cost == nil,
			"стартовая цепочка бесплатна"
		)
	end
)

test("цепочка: доски с лесопилки едут на стройку дома", function()
	local jobs = Logistics.candidates(
		{ { id = "saw", resource = "boards", amount = 3, full = false } },
		{ { id = "house", resource = "boards", amount = 8 } },
		truckConfig
	)
	eq(#jobs, 1, "заказ")
	eq(jobs[1].to, "house", "куда")
	eq(jobs[1].amount, 3, "сколько")
end)

print(`\nИтого: {passed} пройдено, {failed} упало`)
if failed > 0 then
	error("тесты упали")
end
