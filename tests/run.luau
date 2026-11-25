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
local RegionSave = require("../src/shared/Sim/RegionSave")
local SaveConfig = require("../src/shared/Config/Save")
local TickStats = require("../src/shared/Sim/TickStats")
local StressLayout = require("../src/shared/Sim/StressLayout")
local Perf = require("../src/shared/Config/Perf")
local Population = require("../src/shared/Sim/Population")
local PopulationConfig = require("../src/shared/Config/Population")

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

-- Сохранение

test("снимок региона проходит проверку и чистит мусор", function()
	local raw = {
		version = RegionSave.VERSION,
		savedAt = 100,
		buildings = {
			{
				typeId = "forestry",
				x = 5,
				z = 6,
				rotation = 1,
				production = { running = true, progress = 2, input = {}, output = { logs = 3, bad = "x" } },
			},
			{
				typeId = "house",
				x = 10,
				z = 10,
				rotation = 0,
				construction = { delivered = { boards = 4 }, progress = 0 },
			},
			{ typeId = "castle", x = 1, z = 1, rotation = 0 },
			{ typeId = "sawmill", x = 1.5, z = 1, rotation = 0 },
			{ typeId = "sawmill", x = 1, z = 1, rotation = 7 },
			"мусор",
		},
		roads = { 1, 2, 3, 4, 5.5, 6, 7 },
	}
	local snap = RegionSave.sanitize(raw, Buildings)
	assert(snap, "снимок")
	eq(#snap.buildings, 2, "годных зданий")
	local f = snap.buildings[1]
	assert(f.production, "производство")
	eq(f.production.output.logs, 3, "брёвна")
	eq(f.production.output.bad, nil, "мусор в складе")
	local h = snap.buildings[2]
	assert(h.construction, "стройка")
	eq(h.construction.delivered.boards, 4, "доски на стройке")
	eq(#snap.roads, 4, "годные клетки дорог (пары)")
	eq(RegionSave.sanitize({ version = 999 }, Buildings), nil, "чужая версия")
	eq(RegionSave.sanitize("строка", Buildings), nil, "не таблица")
end)

test(
	"блокировка сессии: чужой свежий регион не открыть, брошенный — можно",
	function()
		local timeout = 300
		local rec = RegionSave.acquire(nil, "A", 1000, timeout)
		assert(rec and rec.lock, "первый сервер взял")
		eq(rec.lock.session, "A", "чья блокировка")
		eq(RegionSave.acquire(rec, "B", 1100, timeout), nil, "второй сервер не может")
		assert(RegionSave.acquire(rec, "A", 1100, timeout), "свой можно продлить")
		assert(
			RegionSave.acquire(rec, "B", 1000 + timeout + 1, timeout),
			"брошенный можно забрать"
		)
	end
)

test(
	"сохранение: чужая свежая блокировка не даёт писать, выход снимает свою",
	function()
		local timeout = 300
		local snap = RegionSave.emptySnapshot(0)
		local rec = RegionSave.acquire(nil, "A", 1000, timeout)
		eq(RegionSave.store(rec, "B", 1010, timeout, snap, false), nil, "B не пишет поверх A")
		local saved = RegionSave.store(rec, "A", 1010, timeout, snap, false)
		assert(saved and saved.lock and saved.region, "A сохранил и держит")
		eq(saved.lock.time, 1010, "блокировка продлена")
		local released = RegionSave.store(saved, "A", 1020, timeout, snap, true)
		assert(released, "запись")
		eq(released.lock, nil, "блокировка снята")
		assert(RegionSave.acquire(released, "B", 1021, timeout), "теперь B может открыть")
	end
)

test("конфиг сохранения корректный", function()
	assert(
		SaveConfig.autosaveSeconds < SaveConfig.lockTimeoutSeconds,
		"автосохранение чаще срока блокировки"
	)
	assert(#SaveConfig.dataStoreName > 0, "имя хранилища")
end)

test("снятие блокировки без записи региона", function()
	local snap = RegionSave.emptySnapshot(0)
	local rec = RegionSave.store(nil, "A", 1000, 300, snap, false)
	eq(RegionSave.unlock(rec, "B"), nil, "чужую не снимаем")
	local unlocked = RegionSave.unlock(rec, "A")
	assert(unlocked, "своя снимается")
	eq(unlocked.lock, nil, "без блокировки")
	eq(unlocked.region, snap, "регион прежний")
	eq(RegionSave.unlock(nil, "A"), nil, "пустая запись")
end)

-- Производительность (шаг 7)

test(
	"связность сети пересчитывается после стройки и сноса",
	function()
		local r = Roads.new(20)
		roadLine(r, 0, 0, 5, 0)
		roadLine(r, 8, 0, 12, 0)
		local a, b = { { x = 0, z = 0 } }, { { x = 12, z = 0 } }
		eq(Roads.connected(r, a, b), false, "разрыв")
		assert(Roads.component(r, 0, 0) ~= Roads.component(r, 12, 0), "разные куски")
		roadLine(r, 5, 0, 8, 0)
		eq(Roads.connected(r, a, b), true, "после стройки")
		Roads.remove(r, 7, 0)
		eq(Roads.connected(r, a, b), false, "после сноса")
		eq(Roads.component(r, 7, 0), nil, "нет дороги — нет куска")
		eq(Roads.connected(r, a, { { x = 15, z = 15 } }), false, "цель не на дороге")
		-- Край ряда не соединяется со следующим рядом: клетки (19, 0) и (0, 1) не соседи.
		local edge = Roads.new(20)
		Roads.add(edge, 19, 0)
		Roads.add(edge, 0, 1)
		eq(
			Roads.connected(edge, { { x = 19, z = 0 } }, { { x = 0, z = 1 } }),
			false,
			"перенос строки"
		)
	end
)

test("заказы: ограничение числа кандидатов", function()
	local offers, demands = {}, {}
	for i = 1, 10 do
		table.insert(offers, { id = `f{i}`, resource = "logs", amount = i, full = false })
		table.insert(demands, { id = `s{i}`, resource = "logs", amount = 20 })
	end
	eq(
		#Logistics.candidates(offers, demands, truckConfig),
		90,
		"без ограничения: все пары (кроме мелочи)"
	)
	local limited = table.clone(truckConfig) :: any
	limited.maxCandidates = 5
	local jobs = Logistics.candidates(offers, demands, limited)
	eq(#jobs, 5, "не больше лимита")
	eq(jobs[1].from, "f10", "самый большой склад первым")
	eq(jobs[1].amount, 6, "не больше вместимости")
end)

-- Тестовый регион для парка: дорога z = 0 от x = 0 до 20, подъезды у зданий как в makeWorld.
local function makeFleet(stock: { [string]: number }, space: { [string]: number })
	local r = Roads.new(32)
	roadLine(r, 0, 0, 20, 0)
	local doors =
		{ depot = { x = 0, z = 0 }, f = { x = 10, z = 0 }, s = { x = 20, z = 0 }, s2 = { x = 15, z = 0 } }
	local ids = { "depot", "f", "s", "s2" }
	local source = {
		ids = function()
			return ids
		end,
		offers = function(id)
			local n = stock[id] or 0
			return if n > 0 then { { resource = "logs", amount = n, full = false } } else {}
		end,
		demands = function(id)
			local n = space[id] or 0
			return if n > 0 then { { resource = "logs", amount = n } } else {}
		end,
		findPath = function(from, to)
			return Roads.findPath(r, from, to)
		end,
		connected = function(a, b)
			return Roads.connected(r, a, b)
		end,
		entrances = function(id)
			return if doors[id] then { doors[id] } else {}
		end,
		isRoad = function(c)
			return Roads.has(r, c.x, c.z)
		end,
		take = function(id, _res, amount)
			local n = math.min(stock[id] or 0, amount)
			stock[id] = (stock[id] or 0) - n
			return n
		end,
		deliver = function(id, _res, amount)
			local n = math.min(space[id] or 0, amount)
			space[id] = (space[id] or 0) - n
			stock[`got_{id}`] = (stock[`got_{id}`] or 0) + n
			return n
		end,
	}
	return Logistics.newFleet(source)
end

test("парк: два грузовика не едут за одним грузом", function()
	local stock, space = { f = 6 }, { s = 20 }
	local fleet = makeFleet(stock, space)
	for i = 1, 2 do
		Logistics.addTruck(fleet, Logistics.newTruck(`t{i}`, "depot", { x = 0, z = 0 }))
	end
	Logistics.stepFleet(fleet, 0.25, truckConfig)
	eq(fleet.trucks[1].state, "to_pickup", "первый поехал")
	eq(fleet.trucks[2].state, "idle", "второму груза не осталось")
	for _ = 1, 80 do
		Logistics.stepFleet(fleet, 0.25, truckConfig)
	end
	eq(stock.got_s, 6, "довезено ровно 6")
	eq(next(fleet.reservedOut), nil, "резервы отправителя сняты")
	eq(next(fleet.reservedIn), nil, "резервы получателя сняты")
end)

test(
	"парк: заказы ищут не больше N грузовиков за шаг, по кругу",
	function()
		local stock, space = { f = 60 }, { s = 100 }
		local fleet = makeFleet(stock, space)
		for i = 1, 5 do
			Logistics.addTruck(fleet, Logistics.newTruck(`t{i}`, "depot", { x = 0, z = 0 }))
		end
		local limited = table.clone(truckConfig) :: any
		limited.maxDispatchPerStep = 2
		local function busy(): number
			local n = 0
			for _, t in fleet.trucks do
				if t.state ~= "idle" then
					n += 1
				end
			end
			return n
		end
		Logistics.stepFleet(fleet, 0.25, limited)
		eq(busy(), 2, "после первого шага")
		Logistics.stepFleet(fleet, 0.25, limited)
		eq(busy(), 4, "после второго")
		Logistics.stepFleet(fleet, 0.25, limited)
		eq(busy(), 5, "после третьего все при деле")
	end
)

test(
	"парк: груз в кузове засчитывается получателю, снесённый автопарк убирает грузовик",
	function()
		local stock, space = { f = 6 }, { s = 20 }
		local fleet = makeFleet(stock, space)
		Logistics.addTruck(fleet, Logistics.newTruck("t1", "depot", { x = 0, z = 0 }))
		local t = fleet.trucks[1]
		for _ = 1, 40 do
			Logistics.stepFleet(fleet, 0.25, truckConfig)
			if t.state == "to_dropoff" then
				break
			end
		end
		eq(t.state, "to_dropoff", "везёт")
		local transit = Logistics.inTransit(fleet)
		eq(transit.s and transit.s.logs, 6, "6 брёвен едут на лесопилку")
		Logistics.removeTruck(fleet, "t1")
		eq(#fleet.trucks, 0, "грузовик убран")
		eq(next(fleet.reservedIn), nil, "резерв получателя снят")
	end
)

test("статистика тика: среднее, p95 и максимум по окну", function()
	local stats = TickStats.new(20)
	eq(TickStats.summary(stats).count, 0, "пусто")
	for i = 1, 25 do
		TickStats.add(stats, i) -- в окне остаются 6..25
	end
	local s = TickStats.summary(stats)
	eq(s.count, 20, "окно")
	eq(s.max, 25, "максимум")
	eq(s.avg, 15.5, "среднее")
	eq(s.p95, 24, "p95")
	assert(
		Perf.budgetMs > 0 and Perf.windowSeconds > 0 and Perf.reportSeconds > 0,
		"конфиг замера"
	)
end)

test(
	"стресс-регион: здания не пересекаются, у всех есть подъезд, сеть одна",
	function()
		local size = GridConfig.regionCells
		local layout = StressLayout.build(40, size, 0, 0, RoadsConfig.maxCellsPerCommand)
		eq(layout.chains, 40, "цепочек")
		eq(#layout.buildings, 200, "зданий")
		local g = Grid.new(GridConfig, 0, 0)
		local r = Roads.new(size)
		for _, line in layout.roads do
			local path = Roads.linePath(line.x1, line.z1, line.x2, line.z2)
			assert(
				#path <= RoadsConfig.maxCellsPerCommand,
				"отрезок не длиннее команды"
			)
			for _, c in path do
				if not Roads.has(r, c.x, c.z) then
					assert(Grid.place(g, `road_{c.x}_{c.z}`, c.x, c.z, 1, 1, 0), "дорога встала")
					Roads.add(r, c.x, c.z)
				end
			end
		end
		local first: { Roads.Cell }? = nil
		for i, p in layout.buildings do
			local def = Buildings[p.typeId]
			assert(def, `тип {p.typeId}`)
			assert(
				Grid.place(g, `b{i}`, p.x, p.z, def.sizeX, def.sizeZ, p.rotation),
				`здание {i} встало`
			)
			local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, p.rotation)
			local doors = Roads.entrances(r, p.x, p.z, w, d)
			assert(#doors > 0, `у здания {i} есть подъезд`)
			if first == nil then
				first = doors
			else
				assert(Roads.connected(r, first, doors), `здание {i} в общей сети`)
			end
		end
		local huge = StressLayout.build(10000, size, 0, 0, RoadsConfig.maxCellsPerCommand)
		assert(
			huge.chains < 10000 and huge.chains > 100,
			"лишние цепочки не помещаются"
		)
	end
)

-- Население (этап 2, шаг 1)

local popConfig = table.clone(PopulationConfig) :: any
popConfig.workerShare = 0.5
popConfig.walkRadius = 10
popConfig.moveInPerSecond = 1

test("население: расстояние между краями зданий", function()
	local a = { x = 0, z = 0, w = 2, d = 2 }
	eq(Population.gap(a, { x = 2, z = 0, w = 2, d = 2 }), 0, "вплотную")
	eq(Population.gap(a, { x = 5, z = 0, w = 1, d = 1 }), 3, "по x")
	eq(Population.gap(a, { x = 5, z = 6, w = 1, d = 1 }), 7, "по x и z")
	eq(Population.gap({ x = 5, z = 6, w = 1, d = 1 }, a), 7, "симметрично")
end)

test(
	"население: жильцы въезжают постепенно, работает доля",
	function()
		eq(Population.grow(0, 10, 3, popConfig), 3, "за 3 с")
		eq(Population.grow(9, 10, 5, popConfig), 10, "не больше вместимости")
		eq(Population.workersOf(9.7, popConfig), 4, "половина от целых жильцов")
	end
)

test(
	"население: рабочие из ближних домов, раньше поставленные первыми",
	function()
		local houses = {
			{ id = "near", x = 0, z = 0, w = 2, d = 2, capacity = 10, residents = 10 }, -- 5 рабочих
			{ id = "far", x = 40, z = 0, w = 2, d = 2, capacity = 10, residents = 10 }, -- вне радиуса
		}
		local places = {
			{ id = "f1", x = 4, z = 0, w = 3, d = 3, need = 4 },
			{ id = "f2", x = 4, z = 4, w = 3, d = 3, need = 4 },
		}
		local a = Population.allocate(houses, places, popConfig)
		eq(a.workers.f1, 4, "первое здание укомплектовано")
		eq(a.workers.f2, 1, "второму остался один")
		eq(a.employed.near, 5, "работают все из ближнего дома")
		eq(a.employed.far, 0, "дальний дом слишком далеко")
	end
)

test("население: конфиг и жилые здания", function()
	assert(PopulationConfig.workerShare > 0 and PopulationConfig.workerShare <= 1, "доля рабочих")
	assert(
		PopulationConfig.walkRadius > 0 and PopulationConfig.allocateSeconds > 0,
		"радиус и период"
	)
	assert(
		Buildings.barracks.residents and Buildings.barracks.cost == nil,
		"барак бесплатный и жилой"
	)
	assert(
		Buildings.house.residents and Buildings.house.cost,
		"дом жилой и стоит материалов"
	)
	local workers = Population.workersOf(Buildings.barracks.residents :: number, PopulationConfig)
	assert(
		workers >= Recipes.forestry.workers,
		"одного барака хватает на лесозаготовку"
	)
end)

test("сохранение: жильцы дома проходят проверку", function()
	local raw = {
		version = RegionSave.VERSION,
		savedAt = 1,
		buildings = {
			{ typeId = "house", x = 1, z = 1, rotation = 0, residents = 7.5 },
			{ typeId = "barracks", x = 5, z = 1, rotation = 0, residents = -3 },
		},
		roads = {},
	}
	local snap = RegionSave.sanitize(raw, Buildings)
	assert(snap, "снимок")
	eq(snap.buildings[1].residents, 7.5, "жильцы")
	eq(snap.buildings[2].residents, nil, "мусор отброшен")
end)

test(
	"парк: заказы только в радиусе автопарка, ближний получатель первым",
	function()
		-- Дорога z = 0 от x = 0 до 20: автопарк у x = 0, лесопилки s2 (x = 15) и s (x = 20).
		local stock, space = { f = 6 }, { s = 20, s2 = 20 }
		local fleet = makeFleet(stock, space)
		Logistics.addTruck(fleet, Logistics.newTruck("t1", "depot", { x = 0, z = 0 }))
		local near = table.clone(truckConfig) :: any
		near.serviceRadius = 16
		Logistics.stepFleet(fleet, 0.25, near)
		local t = fleet.trucks[1]
		eq(t.state, "to_pickup", "едет")
		assert(t.job, "заказ есть")
		eq(t.job.to, "s2", "s (x = 20) вне радиуса, везёт в s2")

		local stock2, space2 = { f = 6 }, { s = 20 }
		local fleet2 = makeFleet(stock2, space2)
		Logistics.addTruck(fleet2, Logistics.newTruck("t1", "depot", { x = 0, z = 0 }))
		local tight = table.clone(truckConfig) :: any
		tight.serviceRadius = 5
		Logistics.stepFleet(fleet2, 0.25, tight)
		eq(fleet2.trucks[1].state, "idle", "лесозаготовка (x = 10) вне радиуса 5")

		local jobs = Logistics.candidates(
			{ { id = "f", resource = "logs", amount = 6, full = false } },
			{ { id = "s", resource = "logs", amount = 20 }, { id = "s2", resource = "logs", amount = 5 } },
			truckConfig,
			function(_from, to)
				return if to == "s2" then 5 else 10
			end
		)
		eq(
			jobs[1].to,
			"s2",
			"ближний получатель первым, хоть места у него меньше"
		)
	end
)

-- Еда и довольство (этап 2, шаг 2)

local foodConfig = table.clone(PopulationConfig) :: any
foodConfig.foodPerResidentPerSecond = 0.1 -- 10 жильцов съедают 1 продукт в секунду
foodConfig.shopRadius = 5

local function eater(id: string, x: number, residents: number)
	return { id = id, x = x, z = 0, w = 2, d = 2, residents = residents, debt = 0, fed = true }
end

test("еда: дом забирает порцию из ближнего магазина", function()
	local houses = { eater("h", 0, 10) }
	local shops = {
		{ id = "far", x = 6, z = 0, w = 2, d = 2, stock = 5 },
		{ id = "near", x = 3, z = 0, w = 2, d = 2, stock = 5 },
	}
	local r = Population.feed(houses, shops, 1, foodConfig)
	eq(r.taken.near, 1, "из ближнего")
	eq(r.taken.far, nil, "дальний не тронут")
	eq(r.fed.h, true, "сыт")
end)

test(
	"еда: пустой магазин — голод, без магазина — голод сразу",
	function()
		local r = Population.feed(
			{ eater("h", 0, 10) },
			{ { id = "s", x = 3, z = 0, w = 2, d = 2, stock = 0 } },
			1,
			foodConfig
		)
		eq(r.fed.h, false, "магазин пуст")
		assert(r.debt.h <= 1, "долг не копится сверх порции")
		local r2 = Population.feed(
			{ eater("h", 0, 10) },
			{ { id = "s", x = 30, z = 0, w = 2, d = 2, stock = 9 } },
			1,
			foodConfig
		)
		eq(r2.fed.h, false, "магазин далеко")
		eq(r2.taken.s, nil, "из дальнего не берёт")
	end
)

test("еда: маленький дом не голодает между порциями", function()
	local h = eater("h", 0, 2) -- 0,2 продукта в секунду
	local shops = { { id = "s", x = 3, z = 0, w = 2, d = 2, stock = 0 } }
	local r = Population.feed({ h }, shops, 1, foodConfig)
	eq(r.fed.h, true, "порция ещё не подошла")
	eq(r.debt.h, 0.2, "долг копится")
end)

test(
	"довольство: идёт к цели, голодные уезжают до остатка, сытые въезжают",
	function()
		eq(
			Population.happiness(50, true, 10, foodConfig),
			50 + 10 * foodConfig.happinessRatePerSecond,
			"растёт"
		)
		eq(
			Population.happiness(1, false, 100, foodConfig),
			foodConfig.hungryHappiness,
			"падает до цели"
		)
		local cap = 10
		local low = foodConfig.leaveBelowHappiness - 1
		eq(
			Population.migrate(10, cap, low, 10, foodConfig),
			10 - 10 * foodConfig.leavePerSecond,
			"уезжают"
		)
		eq(
			Population.migrate(10, cap, low, 1e6, foodConfig),
			cap * foodConfig.leaveFloorShare,
			"остаток остаётся"
		)
		local mid = (foodConfig.leaveBelowHappiness + foodConfig.growMinHappiness) / 2
		eq(Population.migrate(5, cap, mid, 10, foodConfig), 5, "середина — без движения")
		assert(Population.migrate(5, cap, 100, 4, foodConfig) > 5, "довольные въезжают")
	end
)

test("еда: конфиг и здания цепочки", function()
	assert(
		Recipes.farm.outputs.grain and Recipes.food_plant.inputs.grain,
		"ферма кормит пищекомбинат"
	)
	assert(Recipes.food_plant.outputs.food, "пищекомбинат делает продукты")
	assert(Buildings.farm and Buildings.food_plant, "здания цепочки")
	assert(
		Buildings.shop.stores and Buildings.shop.stores.food,
		"магазин принимает продукты"
	)
	assert(
		PopulationConfig.leaveBelowHappiness < PopulationConfig.growMinHappiness,
		"пороги довольства"
	)
	assert(
		PopulationConfig.startHappiness >= PopulationConfig.growMinHappiness,
		"новый дом заселяется"
	)
	local orders = {}
	for id, def in Buildings do
		assert(
			not orders[def.order],
			`порядок кнопки {def.order} у {id} не повторяется`
		)
		orders[def.order] = true
	end
	local raw = {
		version = RegionSave.VERSION,
		savedAt = 1,
		buildings = {
			{ typeId = "shop", x = 1, z = 1, rotation = 0, stock = { food = 7, bad = -1 } },
			{ typeId = "house", x = 9, z = 1, rotation = 0, residents = 3, happiness = 140 },
		},
		roads = {},
	}
	local snap = RegionSave.sanitize(raw, Buildings)
	assert(snap, "снимок")
	eq((snap.buildings[1].stock :: any).food, 7, "склад магазина")
	eq((snap.buildings[1].stock :: any).bad, nil, "мусор отброшен")
	eq(snap.buildings[2].happiness, nil, "довольство вне 0–100 отброшено")
end)

test(
	"производство: настоящая причина простоя важнее нехватки рабочих",
	function()
		local r = Recipes.sawmill
		local s = Production.new()
		eq(Production.tick(r, s, 1, 0), "no_input", "нет сырья, даже без рабочих")
		eq(Production.canWork(r, s), false, "без сырья работать нечем")
		s.output.boards = r.storage
		s.input.logs = 2
		eq(
			Production.tick(r, s, 1, 0),
			"output_full",
			"склад полон, даже без рабочих"
		)
		eq(Production.canWork(r, s), false, "склад полон")
		s.output.boards = 0
		eq(Production.canWork(r, s), true, "есть сырьё и место")
		eq(Production.tick(r, s, 1, 0), "no_workers", "только теперь — нет рабочих")
		eq(s.input.logs, 2, "без рабочих сырьё не списано")
		local snap = RegionSave.sanitize({
			version = RegionSave.VERSION,
			savedAt = 1,
			buildings = { { typeId = "house", x = 1, z = 1, rotation = 0, residents = 3, fed = false } },
			roads = {},
		}, Buildings)
		assert(snap, "снимок")
		eq(
			snap.buildings[1].fed,
			false,
			"голодный дом остаётся голодным после загрузки"
		)
	end
)

print(`\nИтого: {passed} пройдено, {failed} упало`)
if failed > 0 then
	error("тесты упали")
end
