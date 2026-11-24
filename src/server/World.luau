--!strict
-- Земля региона. Пока регион один и стоит в центре мира.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Grid"))

local World = {}

local GROUND_THICKNESS = 4

function World.build()
	-- Игрок управляет камерой, а не персонажем: персонажей не создаём.
	Players.CharacterAutoLoads = false

	-- Стандартная плита шаблона Baseplate мешает нашей земле.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local side = GridConfig.regionCells * GridConfig.cellSize
	local ground = Instance.new("Part")
	ground.Name = "RegionGround"
	ground.Anchored = true
	ground.Size = Vector3.new(side, GROUND_THICKNESS, side)
	ground.Position = Vector3.new(0, GridConfig.groundHeight - GROUND_THICKNESS / 2, 0)
	ground.Material = Enum.Material.Grass
	ground.Color = Color3.fromRGB(106, 138, 76)
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = workspace
end

return World
