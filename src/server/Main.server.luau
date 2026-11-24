--!strict
-- Точка входа сервера: строит регион, принимает команды игроков и крутит тик симуляции.

local World = require(script.Parent:WaitForChild("World"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local RoadService = require(script.Parent:WaitForChild("RoadService"))
local Commands = require(script.Parent:WaitForChild("Commands"))

local TICK_SECONDS = 1

local region = World.build()
BuildingService.start(region)
RoadService.start(region)
Commands.start()
print("[Пятилетка] сервер запущен")

while true do
	task.wait(TICK_SECONDS)
	BuildingService.tick(TICK_SECONDS)
end
