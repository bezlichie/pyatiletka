--!strict
-- Стресс-регион для замера тика (этап 1, шаг 7). Работает только в Studio.
--
-- Как запустить: во время Play в Studio выделить Workspace и в Properties → Attributes
-- добавить числовой атрибут StressChains (например, 32). Сервер снесёт всё в регионе
-- и поставит столько цепочек «лесозаготовка → лесопилка → дом», каждая со своим автопарком.
-- Сохранение при этом отключается до конца игры, чтобы стресс-регион не попал в DataStore.
-- Замер тика пишется в Output каждые несколько секунд (см. Main и Config/Perf).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Roads"))
local StressLayout = require(Shared:WaitForChild("Sim"):WaitForChild("StressLayout"))
local RegionState = require(script.Parent:WaitForChild("RegionState"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local RoadService = require(script.Parent:WaitForChild("RoadService"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))

local StressTest = {}

local ATTRIBUTE = "StressChains"

-- Снести всё и поставить chains цепочек. Возвращает число поставленных цепочек.
function StressTest.fill(chains: number): number
	SaveService.disable("стресс-тест")
	for _, id in BuildingService.ids() do
		BuildingService.remove(id)
	end
	RoadService.clear()

	local layout = StressLayout.build(chains, RegionState.grid.size, 0, 0, RoadsConfig.maxCellsPerCommand)
	local failed = 0
	for _, line in layout.roads do
		local ok = RoadService.placeLine(line.x1, line.z1, line.x2, line.z2)
		if not ok then
			failed += 1
		end
	end
	for _, p in layout.buildings do
		local ok = BuildingService.place(p.typeId, p.x, p.z, p.rotation)
		if not ok then
			failed += 1
		end
	end
	print(
		`[Пятилетка] стресс-тест: цепочек {layout.chains}, зданий {#layout.buildings}, не встало {failed}`
	)
	return layout.chains
end

function StressTest.start()
	if not RunService:IsStudio() then
		return
	end
	local function check()
		local value = workspace:GetAttribute(ATTRIBUTE)
		if type(value) == "number" and value >= 1 then
			StressTest.fill(math.floor(value))
		end
	end
	workspace:GetAttributeChangedSignal(ATTRIBUTE):Connect(check)
	check()
end

return StressTest
