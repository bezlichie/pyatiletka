--!strict
-- Отображение сетки: линии клеток (включаются клавишей G) и подсветка клетки под курсором.
-- Это только картинка на клиенте: занятость клеток хранит сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Grid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sim"):WaitForChild("Grid"))
local GroundPick = require(script.Parent:WaitForChild("GroundPick"))

local GridView = {}

local LINE_THICKNESS = 0.15
local LINE_COLOR = Color3.fromRGB(40, 60, 30)
local LINE_TRANSPARENCY = 0.6
local HOVER_COLOR = Color3.fromRGB(255, 220, 90)
local TOGGLE_KEY = Enum.KeyCode.G

local function makeLines(grid: Grid.Grid, groundY: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "GridLines"
	local side = grid.size * grid.cellSize
	for i = 0, grid.size do
		local offset = i * grid.cellSize
		for _, alongX in { true, false } do
			local line = Instance.new("Part")
			line.Anchored = true
			line.CanCollide = false
			line.CanQuery = false
			line.CanTouch = false
			line.CastShadow = false
			line.Material = Enum.Material.SmoothPlastic
			line.Color = LINE_COLOR
			line.Transparency = LINE_TRANSPARENCY
			if alongX then
				line.Size = Vector3.new(side, LINE_THICKNESS, LINE_THICKNESS)
				line.Position = Vector3.new(grid.originX + side / 2, groundY, grid.originZ + offset)
			else
				line.Size = Vector3.new(LINE_THICKNESS, LINE_THICKNESS, side)
				line.Position = Vector3.new(grid.originX + offset, groundY, grid.originZ + side / 2)
			end
			line.Parent = folder
		end
	end
	return folder
end

local function makeLabel(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "GridInfo"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 12, 1, -12)
	label.Size = UDim2.fromOffset(260, 28)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Visible = false
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return label
end

function GridView.start(grid: Grid.Grid, groundY: number)
	local lines = makeLines(grid, groundY + 0.05)
	lines.Parent = nil -- по умолчанию сетка скрыта

	local hover = Instance.new("Part")
	hover.Name = "GridHover"
	hover.Anchored = true
	hover.CanCollide = false
	hover.CanQuery = false
	hover.CanTouch = false
	hover.CastShadow = false
	hover.Material = Enum.Material.Neon
	hover.Color = HOVER_COLOR
	hover.Transparency = 0.5
	hover.Size = Vector3.new(grid.cellSize, 0.2, grid.cellSize)
	hover.Parent = workspace

	local label = makeLabel()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			lines.Parent = if lines.Parent then nil else workspace
		end
	end)

	RunService.RenderStepped:Connect(function()
		local point = if GroundPick.usingMouse() then GroundPick.fromMouse(groundY) else nil
		local cell = if point then Grid.toCell(grid, point.X, point.Z) else nil
		if cell then
			local x, z = Grid.cellCenter(grid, cell.x, cell.z)
			hover.Position = Vector3.new(x, groundY + 0.1, z)
			hover.Transparency = 0.5
			label.Text = `Клетка {cell.x}, {cell.z}   ·   G — сетка`
			label.Visible = true
		else
			hover.Transparency = 1
			label.Visible = false
		end
	end)
end

return GridView
