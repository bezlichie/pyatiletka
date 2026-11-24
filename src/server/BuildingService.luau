--!strict
-- Здания региона: приём команд стройки и сноса от клиента, модели зданий, тик производства.
-- Клиент только просит, сервер сам проверяет место и решает.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Sim = Shared:WaitForChild("Sim")
local BuildingsConfig = require(Config:WaitForChild("Buildings"))
local GridConfig = require(Config:WaitForChild("Grid"))
local Recipes = require(Config:WaitForChild("Recipes"))
local Text = require(Config:WaitForChild("Text"))
local Grid = require(Sim:WaitForChild("Grid"))
local Production = require(Sim:WaitForChild("Production"))
local BuildCommand = require(Sim:WaitForChild("BuildCommand"))

local BuildingService = {}

-- Пока у игрока одна эпоха — стартовая. Прогрессия появится вместе с пятилетним планом.
local CURRENT_ERA = 0
-- Не чаще одной команды за это время от одного игрока: защита от спама.
local COMMAND_COOLDOWN = 0.1
local LABEL_MAX_DISTANCE = 300

type Entry = {
	id: string,
	typeId: string,
	model: Model,
	recipe: Production.Recipe?,
	state: Production.State?,
	label: TextLabel?,
}

local grid = Grid.new(GridConfig, 0, 0)
local entries: { [string]: Entry } = {}
local nextId = 1
local lastCommand: { [Player]: number } = {}
local folder: Folder

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Простая low-poly модель: корпус и крыша чуть шире корпуса.
local function buildModel(id: string, typeId: string, x: number, z: number, rotation: number): Model
	local def = BuildingsConfig[typeId]
	local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, rotation)
	local cx, cz = Grid.areaCenter(grid, x, z, def.sizeX, def.sizeZ, rotation)
	local ground = GridConfig.groundHeight
	local margin = 0.6 -- зазор до края клеток, чтобы соседние здания не сливались
	local bodyW, bodyD = w * grid.cellSize - margin * 2, d * grid.cellSize - margin * 2

	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("TypeId", typeId)
	model:SetAttribute("CellX", x)
	model:SetAttribute("CellZ", z)
	model:SetAttribute("Rotation", rotation)

	local body = makePart(
		"Body",
		Vector3.new(bodyW, def.height, bodyD),
		Vector3.new(cx, ground + def.height / 2, cz),
		rgb(def.color),
		model
	)
	makePart(
		"Roof",
		Vector3.new(bodyW + 0.6, 0.8, bodyD + 0.6),
		Vector3.new(cx, ground + def.height + 0.4, cz),
		rgb(def.roofColor),
		model
	)
	model.PrimaryPart = body
	return model
end

local function makeLabel(model: Model, height: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Status"
	gui.Size = UDim2.fromOffset(180, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + 3, 0)
	gui.MaxDistance = LABEL_MAX_DISTANCE
	gui.AlwaysOnTop = true
	gui.Adornee = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextWrapped = true
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	gui.Parent = model
	return label
end

local function stockText(stock: { [string]: number }): string
	local parts = {}
	for resource, amount in stock do
		if amount > 0 then
			local name = Text.resources[resource]
			table.insert(parts, `{if name then name.ru else resource} {amount}`)
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function updateLabel(entry: Entry)
	local label, state = entry.label, entry.state
	if label == nil or state == nil then
		return
	end
	local name = BuildingsConfig[entry.typeId].name.ru
	local status = Text.status[state.status]
	local line = if status then status.ru else state.status
	local stock = stockText(state.output)
	label.Text = `{name}: {line}` .. (if stock ~= "" then `\n{stock}` else "")
	entry.model:SetAttribute("Status", state.status)
end

local function throttled(player: Player): boolean
	local now = os.clock()
	local last = lastCommand[player]
	if last and now - last < COMMAND_COOLDOWN then
		return true
	end
	lastCommand[player] = now
	return false
end

local function place(player: Player, typeId: any, x: any, z: any, rotation: any): (boolean, string)
	if throttled(player) then
		return false, "too_fast"
	end
	local command, err = BuildCommand.parse(BuildingsConfig, CURRENT_ERA, typeId, x, z, rotation)
	if command == nil then
		return false, err or "bad_args"
	end
	local def = BuildingsConfig[command.typeId]
	local id = `b{nextId}`
	local ok, placeErr = Grid.place(grid, id, command.x, command.z, def.sizeX, def.sizeZ, command.rotation)
	if not ok then
		return false, placeErr or "occupied"
	end
	nextId += 1

	local model = buildModel(id, command.typeId, command.x, command.z, command.rotation)
	local entry: Entry = { id = id, typeId = command.typeId, model = model }
	local recipe = Recipes[command.typeId]
	if recipe then
		entry.recipe = recipe
		entry.state = Production.new()
		entry.label = makeLabel(model, def.height)
		updateLabel(entry)
	end
	model.Parent = folder
	entries[id] = entry
	print(`[Пятилетка] {player.Name} построил {def.name.ru} ({id}) в клетке {command.x}, {command.z}`)
	return true, id
end

local function remove(player: Player, id: any): (boolean, string)
	if throttled(player) then
		return false, "too_fast"
	end
	if type(id) ~= "string" then
		return false, "bad_args"
	end
	local entry = entries[id]
	if entry == nil then
		return false, "not_found"
	end
	Grid.remove(grid, id)
	entry.model:Destroy()
	entries[id] = nil
	print(`[Пятилетка] {player.Name} снёс {id}`)
	return true, id
end

-- region — Persistent-модель региона (см. World): всё содержимое региона живёт в ней.
function BuildingService.start(region: Model)
	folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = region

	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local placeRemote = Instance.new("RemoteFunction")
	placeRemote.Name = "PlaceBuilding"
	placeRemote.OnServerInvoke = place
	placeRemote.Parent = remotes
	local removeRemote = Instance.new("RemoteFunction")
	removeRemote.Name = "RemoveBuilding"
	removeRemote.OnServerInvoke = remove
	removeRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastCommand[player] = nil
	end)
end

-- Один шаг симуляции всех зданий. Пока рабочих хватает всегда: население появится позже.
function BuildingService.tick(dt: number)
	for _, entry in entries do
		local recipe, state = entry.recipe, entry.state
		if recipe and state then
			Production.tick(recipe, state, dt, recipe.workers)
			updateLabel(entry)
		end
	end
end

function BuildingService.count(): number
	local n = 0
	for _ in entries do
		n += 1
	end
	return n
end

return BuildingService
