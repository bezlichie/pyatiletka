--!strict
-- Точка входа сервера: строит регион, принимает команды игроков и крутит тик симуляции.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Perf = require(Shared:WaitForChild("Config"):WaitForChild("Perf"))
local TickStats = require(Shared:WaitForChild("Sim"):WaitForChild("TickStats"))
local World = require(script.Parent:WaitForChild("World"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local RoadService = require(script.Parent:WaitForChild("RoadService"))
local TruckService = require(script.Parent:WaitForChild("TruckService"))
local Commands = require(script.Parent:WaitForChild("Commands"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))
local StressTest = require(script.Parent:WaitForChild("StressTest"))

local TICK_SECONDS = 1

local region = World.build()
BuildingService.start(region)
RoadService.start(region)
TruckService.start(region)
Commands.start()
SaveService.start()
StressTest.start()
print("[Пятилетка] сервер запущен")

-- Замер: сколько миллисекунд симуляция тратит за секунду (тик зданий + шаги грузовиков).
-- Итог пишется в атрибуты модели региона (TickAvgMs, TickP95Ms, TickMaxMs),
-- в Studio — ещё и в Output. Если среднее выше бюджета — предупреждение и на живом сервере.
local stats = TickStats.new(Perf.windowSeconds)
local sinceReport = 0

local function report()
	local s = TickStats.summary(stats)
	region:SetAttribute("TickAvgMs", math.floor(s.avg * 100) / 100)
	region:SetAttribute("TickP95Ms", math.floor(s.p95 * 100) / 100)
	region:SetAttribute("TickMaxMs", math.floor(s.max * 100) / 100)
	local text = string.format(
		"[Пятилетка] тик за %d с: среднее %.2f мс, p95 %.2f мс, макс %.2f мс (бюджет %d мс). "
			.. "Зданий %d, грузовиков %d",
		s.count,
		s.avg,
		s.p95,
		s.max,
		Perf.budgetMs,
		#BuildingService.ids(),
		TruckService.count()
	)
	if s.avg > Perf.budgetMs then
		warn(text)
	elseif RunService:IsStudio() then
		print(text)
	end
end

while true do
	task.wait(TICK_SECONDS)
	local t0 = os.clock()
	BuildingService.tick(TICK_SECONDS)
	local ms = (os.clock() - t0) * 1000 + TruckService.takeBusyMs()
	TickStats.add(stats, ms)
	sinceReport += TICK_SECONDS
	if sinceReport >= Perf.reportSeconds then
		sinceReport = 0
		report()
	end
end
