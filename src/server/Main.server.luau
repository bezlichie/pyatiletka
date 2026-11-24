--!strict
-- Точка входа сервера: строит регион, принимает команды стройки и крутит тик симуляции.

local World = require(script.Parent:WaitForChild("World"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))

local TICK_SECONDS = 1

local region = World.build()
BuildingService.start(region)
print("[Пятилетка] сервер запущен")

while true do
	task.wait(TICK_SECONDS)
	BuildingService.tick(TICK_SECONDS)
end
