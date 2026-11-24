--!strict
-- Дороги региона: прокладка и снос участков, модели полотна.
-- Каждая клетка дороги — отдельный объект сетки с id вида road_<x>_<z>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GridConfig = require(Config:WaitForChild("Grid"))
local RoadsConfig = require(Config:WaitForChild("Roads"))
local Grid = require(Shared:WaitForChild("Sim"):WaitForChild("Grid"))
local Roads = require(Shared:WaitForChild("Sim"):WaitForChild("Roads"))
local RegionState = require(script.Parent:WaitForChild("RegionState"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))

local RoadService = {}

local grid = RegionState.grid
local roads = RegionState.roads
local parts: { [string]: BasePart } = {}
local folder: Folder

local ROAD_PREFIX = "road_"

local function roadId(x: number, z: number): string
	return `{ROAD_PREFIX}{x}_{z}`
end

function RoadService.isRoadId(id: string): boolean
	return string.sub(id, 1, #ROAD_PREFIX) == ROAD_PREFIX
end

local function makePart(x: number, z: number): BasePart
	local cx, cz = Grid.cellCenter(grid, x, z)
	local c = RoadsConfig.color
	local part = Instance.new("Part")
	part.Name = roadId(x, z)
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(grid.cellSize, RoadsConfig.thickness, grid.cellSize)
	part.Position = Vector3.new(cx, GridConfig.groundHeight + RoadsConfig.thickness / 2, cz)
	part.Color = Color3.fromRGB(c[1], c[2], c[3])
	part.Material = Enum.Material.Asphalt
	part.TopSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("CellX", x)
	part:SetAttribute("CellZ", z)
	return part
end

-- Прокладывает дорогу буквой «Г». Клетки, где дорога уже есть, пропускает.
-- Если хоть одна клетка занята зданием или за краем — не строит ничего.
-- Возвращает true и число новых клеток или false и код ошибки.
function RoadService.placeLine(x1: number, z1: number, x2: number, z2: number): (boolean, string | number)
	local path = Roads.linePath(x1, z1, x2, z2)
	local toBuild = {}
	for _, cell in path do
		if not Roads.has(roads, cell.x, cell.z) then
			local ok, err = Grid.canPlace(grid, cell.x, cell.z, 1, 1, 0)
			if not ok then
				return false, err or "occupied"
			end
			table.insert(toBuild, cell)
		end
	end
	for _, cell in toBuild do
		local id = roadId(cell.x, cell.z)
		Grid.place(grid, id, cell.x, cell.z, 1, 1, 0)
		Roads.add(roads, cell.x, cell.z)
		local part = makePart(cell.x, cell.z)
		part.Parent = folder
		parts[id] = part
	end
	if #toBuild > 0 then
		BuildingService.refreshConnections()
	end
	return true, #toBuild
end

function RoadService.remove(id: string): (boolean, string)
	local part = parts[id]
	if part == nil then
		return false, "not_found"
	end
	local x, z = part:GetAttribute("CellX") :: number, part:GetAttribute("CellZ") :: number
	Grid.remove(grid, id)
	Roads.remove(roads, x, z)
	part:Destroy()
	parts[id] = nil
	BuildingService.refreshConnections()
	return true, id
end

-- Все клетки дорог плоским списком x1, z1, x2, z2, ... для сохранения.
function RoadService.snapshot(): { number }
	local result = {}
	for _, part in parts do
		table.insert(result, part:GetAttribute("CellX") :: number)
		table.insert(result, part:GetAttribute("CellZ") :: number)
	end
	return result
end

-- Восстановить дороги из сохранения. Занятые клетки пропускаются. Возвращает число клеток.
function RoadService.restore(flat: { number }): number
	local count = 0
	for i = 1, #flat - 1, 2 do
		local x, z = flat[i], flat[i + 1]
		if not Roads.has(roads, x, z) and Grid.canPlace(grid, x, z, 1, 1, 0) then
			local id = roadId(x, z)
			Grid.place(grid, id, x, z, 1, 1, 0)
			Roads.add(roads, x, z)
			local part = makePart(x, z)
			part.Parent = folder
			parts[id] = part
			count += 1
		end
	end
	BuildingService.refreshConnections()
	return count
end

function RoadService.start(region: Model)
	folder = Instance.new("Folder")
	folder.Name = "Roads"
	folder.Parent = region
end

return RoadService
