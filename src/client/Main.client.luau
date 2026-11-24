--!strict
-- Точка входа клиента: камера над регионом и отображение сетки.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GridConfig = require(Config:WaitForChild("Grid"))
local CameraConfig = require(Config:WaitForChild("Camera"))
local Grid = require(ReplicatedStorage.Shared:WaitForChild("Sim"):WaitForChild("Grid"))
local RtsCamera = require(script.Parent:WaitForChild("RtsCamera"))
local GridView = require(script.Parent:WaitForChild("GridView"))

-- Регион пока один, с центром в начале координат (так же строит землю сервер).
local grid = Grid.new(GridConfig, 0, 0)
local side = grid.size * grid.cellSize

RtsCamera.start(CameraConfig, {
	minX = grid.originX,
	maxX = grid.originX + side,
	minZ = grid.originZ,
	maxZ = grid.originZ + side,
	groundY = GridConfig.groundHeight,
})
GridView.start(grid, GridConfig.groundHeight)

print("[Пятилетка] клиент запущен")
