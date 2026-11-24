--!strict
-- Тесты чистой логики. Запуск из корня репозитория: `lune run tests/run`

local Production = require("../src/shared/Sim/Production")
local Recipes = require("../src/shared/Config/Recipes")

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

test("лесопилка списывает брёвна в начале цикла и выпускает доски", function()
	local r = Recipes.sawmill
	local s = Production.new()
	eq(Production.deliver(r, s, "logs", 4), 4, "принято брёвен")
	Production.tick(r, s, 1, r.workers)
	eq(s.input.logs, 2, "брёвна после старта цикла")
	run(r, s, r.cycleSeconds - 1, r.workers)
	eq(s.output.boards, 1, "доски")
end)

test("склад не принимает больше ёмкости и чужие ресурсы", function()
	local r = Recipes.sawmill
	local s = Production.new()
	eq(Production.deliver(r, s, "logs", 100), r.storage, "принято брёвен")
	eq(Production.deliver(r, s, "grain", 5), 0, "принято зерна")
end)

test("полный выходной склад останавливает здание, не тратя сырьё", function()
	local r = Recipes.sawmill
	local s = Production.new()
	s.output.boards = r.storage
	Production.deliver(r, s, "logs", 2)
	eq(Production.tick(r, s, 1, r.workers), "output_full", "статус")
	eq(s.input.logs, 2, "брёвна не списаны")
	eq(Production.take(s, "boards", 5), 5, "забрано досок")
	eq(Production.tick(r, s, 1, r.workers), "working", "статус после разгрузки")
end)

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

print(`\nИтого: {passed} пройдено, {failed} упало`)
if failed > 0 then
	error("тесты упали")
end
