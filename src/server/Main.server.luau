--!strict
-- Точка входа сервера. Пока это проверка «первой клетки»: код из репозитория
-- попал в Studio через Rojo, общие модули подключаются, тик симуляции идёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Recipes = require(Shared:WaitForChild("Config"):WaitForChild("Recipes"))
local Production = require(Shared:WaitForChild("Sim"):WaitForChild("Production"))

local TICK_SECONDS = 1

print("[Пятилетка] сервер запущен")

-- Тестовое здание: лесозаготовка с полной бригадой.
local recipe = Recipes.forestry
local forestry = Production.new()

local elapsed = 0
while true do
	task.wait(TICK_SECONDS)
	Production.tick(recipe, forestry, TICK_SECONDS, recipe.workers)
	elapsed += TICK_SECONDS
	if elapsed % 10 == 0 then
		print(
			`[Пятилетка] лесозаготовка: {forestry.status}, брёвен на складе: {forestry.output.logs or 0}`
		)
	end
end
