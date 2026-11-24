--!strict
-- Общее состояние региона на сервере: занятость клеток и дорожная сеть.
-- Здания и дороги делят одну сетку: на клетке может быть что-то одно.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridConfig = require(Shared:WaitForChild("Config"):WaitForChild("Grid"))
local Grid = require(Shared:WaitForChild("Sim"):WaitForChild("Grid"))
local Roads = require(Shared:WaitForChild("Sim"):WaitForChild("Roads"))

local grid = Grid.new(GridConfig, 0, 0)

return {
	grid = grid,
	roads = Roads.new(grid.size),
}
