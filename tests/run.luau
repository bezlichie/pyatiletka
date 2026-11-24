--!strict
-- Тесты чистой логики. Запуск из корня репозитория: `lune run tests/run`

local Production = require("../src/shared/Sim/Production")
local Recipes = require("../src/shared/Config/Recipes")
local Grid = require("../src/shared/Sim/Grid")
local GridConfig = require("../src/shared/Config/Grid")

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

print(`\nИтого: {passed} пройдено, {failed} упало`)
if failed > 0 then
	error("тесты упали")
end
