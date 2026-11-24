--!strict
-- Точка входа сервера: строит регион, принимает команды игроков и крутит тик симуляции.

local World = require(script.Parent:WaitForChild("World"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local RoadService = require(script.Parent:WaitForChild("RoadService"))
local TruckService = require(script.Parent:WaitForChild("TruckService"))
local Commands = require(script.Parent:WaitForChild("Commands"))
local SaveService = require(script.Parent:WaitForChild("SaveService"))

local TICK_SECONDS = 1

local region = World.build()
BuildingService.start(region)
RoadService.start(region)
TruckService.start(region)
Commands.start()
SaveService.start()
print("[Пятилетка] сервер запущен")

while true do
	task.wait(TICK_SECONDS)
	BuildingService.tick(TICK_SECONDS)
end
