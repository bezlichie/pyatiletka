--!strict
-- Нагрузочный замер тика без Studio (этап 1, шаг 7).
-- Запуск из корня репозитория: `lune run tests/bench` или `lune run tests/bench 64` (число цепочек).
-- Мини-регион повторяет логику сервера: производство и стройка раз в секунду,
-- парк грузовиков каждые 0,2 с. Графики и Roblox API не участвуют.

local process = require("@lune/process")

local Production = require("../src/shared/Sim/Production")
local Construction = require("../src/shared/Sim/Construction")
local Recipes = require("../src/shared/Config/Recipes")
local Buildings = require("../src/shared/Config/Buildings")
local Grid = require("../src/shared/Sim/Grid")
local GridConfig = require("../src/shared/Config/Grid")
local Roads = require("../src/shared/Sim/Roads")
local RoadsConfig = require("../src/shared/Config/Roads")
local Logistics = require("../src/shared/Sim/Logistics")
local TrucksConfig = require("../src/shared/Config/Trucks")
local StressLayout = require("../src/shared/Sim/StressLayout")
local TickStats = require("../src/shared/Sim/TickStats")
local Perf = require("../src/shared/Config/Perf")

local STEP = 0.2
local SECONDS = 300 -- игровых секунд на один прогон

type Entry = {
	id: string,
	typeId: string,
	x: number,
	z: number,
	w: number,
	d: number,
	recipe: Production.Recipe?,
	state: Production.State?,
	site: Construction.State?,
	doors: { Roads.Cell }?,
	doorsVersion: number?,
}

local function makeRegion(chains: number)
	local grid = Grid.new(GridConfig, 0, 0)
	local roads = Roads.new(grid.size)
	local entries: { [string]: Entry } = {}
	local ids: { string } = {}
	local layout = StressLayout.build(chains, grid.size, 0, 0, RoadsConfig.maxCellsPerCommand)
	for _, line in layout.roads do
		for _, c in Roads.linePath(line.x1, line.z1, line.x2, line.z2) do
			if Grid.place(grid, `road_{c.x}_{c.z}`, c.x, c.z, 1, 1, 0) then
				Roads.add(roads, c.x, c.z)
			end
		end
	end
	for n, p in layout.buildings do
		local def = Buildings[p.typeId]
		local id = `b{n}`
		assert(Grid.place(grid, id, p.x, p.z, def.sizeX, def.sizeZ, p.rotation), `место для {id}`)
		local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, p.rotation)
		local entry: Entry = { id = id, typeId = p.typeId, x = p.x, z = p.z, w = w, d = d }
		local recipe = Recipes[p.typeId]
		if recipe then
			entry.recipe = recipe
			entry.state = Production.new()
		end
		if def.cost then
			entry.site = Construction.new(def.cost, def.buildSeconds or 0)
		end
		entries[id] = entry
		table.insert(ids, id)
	end

	local source: Logistics.Source = {
		ids = function()
			return ids
		end,
		offers = function(id)
			local e = entries[id]
			local result = {}
			if e and e.site == nil and e.recipe and e.state then
				for resource in e.recipe.outputs do
					local amount = e.state.output[resource] or 0
					if amount > 0 then
						table.insert(
							result,
							{ resource = resource, amount = amount, full = e.state.status == "output_full" }
						)
					end
				end
			end
			return result
		end,
		demands = function(id)
			local e = entries[id]
			local result = {}
			if e == nil then
				return result
			end
			if e.site then
				for resource in e.site.cost do
					local need = Construction.remaining(e.site, resource)
					if need > 0 then
						table.insert(result, { resource = resource, amount = need })
					end
				end
			elseif e.recipe and e.state then
				for resource in e.recipe.inputs do
					local space = e.recipe.storage - (e.state.input[resource] or 0)
					if space > 0 then
						table.insert(result, { resource = resource, amount = space })
					end
				end
			end
			return result
		end,
		findPath = function(from, to)
			return Roads.findPath(roads, from, to)
		end,
		connected = function(a, b)
			return Roads.connected(roads, a, b)
		end,
		-- Как на сервере: подъезды запоминаются до следующего изменения дорог.
		entrances = function(id)
			local e = entries[id]
			if e == nil then
				return {}
			end
			if e.doorsVersion ~= roads.version then
				e.doors = Roads.entrances(roads, e.x, e.z, e.w, e.d)
				e.doorsVersion = roads.version
			end
			return e.doors :: { Roads.Cell }
		end,
		isRoad = function(c)
			return Roads.has(roads, c.x, c.z)
		end,
		take = function(id, resource, amount)
			local e = entries[id]
			if e == nil or e.state == nil then
				return 0
			end
			return Production.take(e.state, resource, amount)
		end,
		deliver = function(id, resource, amount)
			local e = entries[id]
			if e == nil then
				return 0
			end
			if e.site then
				return Construction.deliver(e.site, resource, amount)
			elseif e.recipe and e.state then
				return Production.deliver(e.recipe, e.state, resource, amount)
			end
			return 0
		end,
	}
	local fleet = Logistics.newFleet(source)
	local truckCount = 0
	for _, id in ids do
		if entries[id].typeId == "depot" then
			local doors = source.entrances(id)
			assert(#doors > 0, `у автопарка {id} нет подъезда`)
			for _ = 1, TrucksConfig.perDepot do
				truckCount += 1
				Logistics.addTruck(fleet, Logistics.newTruck(`t{truckCount}`, id, doors[1]))
			end
		end
	end
	return {
		entries = entries,
		ids = ids,
		fleet = fleet,
		chains = layout.chains,
		trucks = truckCount,
		roadCells = roads.count,
	}
end

local function tickBuildings(entries: { [string]: Entry })
	for _, e in entries do
		if e.site then
			if Construction.tick(e.site, 1) then
				e.site = nil
			end
		elseif e.recipe and e.state then
			Production.tick(e.recipe, e.state, 1, e.recipe.workers)
		end
	end
end

local function run(chains: number, config: Logistics.Config, label: string)
	local region = makeRegion(chains)
	local stats = TickStats.new(SECONDS)
	local built = 0
	for _ = 1, SECONDS do
		local t0 = os.clock()
		tickBuildings(region.entries)
		for _ = 1, math.floor(1 / STEP + 0.5) do
			Logistics.stepFleet(region.fleet, STEP, config)
		end
		TickStats.add(stats, (os.clock() - t0) * 1000)
	end
	for _, e in region.entries do
		if e.typeId == "house" and e.site == nil then
			built += 1
		end
	end
	local s = TickStats.summary(stats)
	print(
		string.format(
			"%-14s цепочек %3d, зданий %3d, грузовиков %3d, дорог %4d | мс/с: среднее %6.2f, p95 %6.2f, макс %6.2f | домов построено %d",
			label,
			region.chains,
			#region.ids,
			region.trucks,
			region.roadCells,
			s.avg,
			s.p95,
			s.max,
			built
		)
	)
	return s
end

-- Без ограничений: как работал парк до шага 7 (все пары заказов, все свободные машины за шаг).
local unlimited = table.clone(TrucksConfig) :: any
unlimited.maxCandidates = nil
unlimited.maxDispatchPerStep = nil

local counts = { 16, 32, 64, 128 }
local arg = tonumber(process.args[1])
if arg then
	counts = { arg }
end

print(
	`Бюджет: {Perf.budgetMs} мс на секунду игры. {SECONDS} игровых секунд на прогон.`
)
local over = false
for _, n in counts do
	run(n, unlimited, "без лимитов")
	local s = run(n, TrucksConfig :: any, "с лимитами")
	if s.p95 > Perf.budgetMs then
		over = true
	end
end
if over then
	print("Есть прогоны дольше бюджета (p95 с лимитами).")
end
