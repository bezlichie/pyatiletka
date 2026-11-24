--!strict
-- Здания региона: установка и снос, модели зданий, подъезды к дорогам, тик производства.
-- Аргументы от клиента проверяет Commands; здесь — только правила региона.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Sim = Shared:WaitForChild("Sim")
local BuildingsConfig = require(Config:WaitForChild("Buildings"))
local GridConfig = require(Config:WaitForChild("Grid"))
local Recipes = require(Config:WaitForChild("Recipes"))
local Text = require(Config:WaitForChild("Text"))
local Grid = require(Sim:WaitForChild("Grid"))
local Roads = require(Sim:WaitForChild("Roads"))
local Production = require(Sim:WaitForChild("Production"))
local RegionState = require(script.Parent:WaitForChild("RegionState"))

local BuildingService = {}

local LABEL_MAX_DISTANCE = 300

type Entry = {
	id: string,
	typeId: string,
	x: number,
	z: number,
	rotation: number,
	model: Model,
	connected: boolean, -- есть ли дорога у края здания
	recipe: Production.Recipe?,
	state: Production.State?,
	label: TextLabel?,
	note: string?, -- дополнительная строка таблички (например, у автопарка)
}

local grid = RegionState.grid
local roads = RegionState.roads
local entries: { [string]: Entry } = {}
local nextId = 1
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
	gui.Size = UDim2.fromOffset(180, 52)
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
	label.RichText = true
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
	local label = entry.label
	if label == nil then
		return
	end
	local name = BuildingsConfig[entry.typeId].name.ru
	local lines = {}
	local state = entry.state
	if state then
		local status = Text.status[state.status]
		table.insert(lines, `{name}: {if status then status.ru else state.status}`)
		local input = stockText(state.input)
		local output = stockText(state.output)
		if input ~= "" then
			table.insert(lines, `{Text.labels.input.ru}: {input}`)
		end
		if output ~= "" then
			table.insert(lines, `{Text.labels.output.ru}: {output}`)
		end
		entry.model:SetAttribute("Status", state.status)
	else
		table.insert(lines, name)
	end
	if entry.note then
		table.insert(lines, entry.note)
	end
	if not entry.connected then
		table.insert(lines, `<font color="#ff8a7a">{Text.status.no_road.ru}</font>`)
	end
	label.Text = table.concat(lines, "\n")
end

local function checkConnection(entry: Entry)
	local def = BuildingsConfig[entry.typeId]
	local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, entry.rotation)
	entry.connected = #Roads.entrances(roads, entry.x, entry.z, w, d) > 0
	entry.model:SetAttribute("Connected", entry.connected)
	updateLabel(entry)
end

-- Ставит здание. Возвращает true и id или false и код ошибки.
function BuildingService.place(typeId: string, x: number, z: number, rotation: number): (boolean, string)
	local def = BuildingsConfig[typeId]
	local id = `b{nextId}`
	local ok, placeErr = Grid.place(grid, id, x, z, def.sizeX, def.sizeZ, rotation)
	if not ok then
		return false, placeErr or "occupied"
	end
	nextId += 1

	local model = buildModel(id, typeId, x, z, rotation)
	local entry: Entry = {
		id = id,
		typeId = typeId,
		x = x,
		z = z,
		rotation = rotation,
		model = model,
		connected = false,
	}
	entry.label = makeLabel(model, def.height)
	local recipe = Recipes[typeId]
	if recipe then
		entry.recipe = recipe
		entry.state = Production.new()
	end
	checkConnection(entry)
	model.Parent = folder
	entries[id] = entry
	return true, id
end

function BuildingService.has(id: string): boolean
	return entries[id] ~= nil
end

function BuildingService.remove(id: string): (boolean, string)
	local entry = entries[id]
	if entry == nil then
		return false, "not_found"
	end
	Grid.remove(grid, id)
	entry.model:Destroy()
	entries[id] = nil
	return true, id
end

-- Клетки дороги у края здания (пусто, если здания нет или подъезда нет).
function BuildingService.entrances(id: string): { Roads.Cell }
	local entry = entries[id]
	if entry == nil then
		return {}
	end
	local def = BuildingsConfig[entry.typeId]
	local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, entry.rotation)
	return Roads.entrances(roads, entry.x, entry.z, w, d)
end

-- Краткие сведения о здании для логистики или nil.
function BuildingService.info(id: string): (string?, Production.Recipe?, Production.State?)
	local entry = entries[id]
	if entry == nil then
		return nil, nil, nil
	end
	return entry.typeId, entry.recipe, entry.state
end

-- Все id зданий.
function BuildingService.ids(): { string }
	local result = {}
	for id in entries do
		table.insert(result, id)
	end
	return result
end

-- Забрать продукцию с выходного склада. Возвращает, сколько забрано.
function BuildingService.take(id: string, resource: string, amount: number): number
	local entry = entries[id]
	if entry == nil or entry.state == nil then
		return 0
	end
	local taken = Production.take(entry.state, resource, amount)
	updateLabel(entry)
	return taken
end

-- Привезти сырьё на входной склад. Возвращает, сколько принято.
function BuildingService.deliver(id: string, resource: string, amount: number): number
	local entry = entries[id]
	if entry == nil or entry.recipe == nil or entry.state == nil then
		return 0
	end
	local accepted = Production.deliver(entry.recipe, entry.state, resource, amount)
	updateLabel(entry)
	return accepted
end

-- Дополнительная строка на табличке здания (nil — убрать).
function BuildingService.setNote(id: string, note: string?)
	local entry = entries[id]
	if entry == nil or entry.note == note then
		return
	end
	entry.note = note
	updateLabel(entry)
end

-- Пересчитать подъезды всех зданий. Вызывается после изменения дорог.
function BuildingService.refreshConnections()
	for _, entry in entries do
		checkConnection(entry)
	end
end

-- region — Persistent-модель региона (см. World): всё содержимое региона живёт в ней.
function BuildingService.start(region: Model)
	folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = region
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

return BuildingService
