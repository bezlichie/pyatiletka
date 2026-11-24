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
local Construction = require(Sim:WaitForChild("Construction"))
local RegionState = require(script.Parent:WaitForChild("RegionState"))
local RegionSave = require(Sim:WaitForChild("RegionSave"))

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
	construction: Construction.State?, -- есть, пока здание — стройплощадка
}

-- Что здание может отдать грузовику и что принять.
export type Offer = { resource: string, amount: number, full: boolean }
export type Demand = { resource: string, amount: number }

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
	local site = entry.construction
	if site then
		table.insert(lines, `{name}: {Text.labels.construction.ru}`)
		local materials = {}
		for resource, need in site.cost do
			local res = Text.resources[resource]
			table.insert(
				materials,
				`{if res then res.ru else resource} {site.delivered[resource] or 0}/{need}`
			)
		end
		table.sort(materials)
		table.insert(lines, table.concat(materials, ", "))
		if Construction.hasAllMaterials(site) then
			local percent = math.floor(site.progress / math.max(site.buildSeconds, 1e-3) * 100)
			table.insert(lines, `{Text.labels.building.ru} {percent}%`)
		else
			table.insert(lines, Text.labels.waitingMaterials.ru)
		end
		entry.model:SetAttribute("Status", "construction")
	elseif state then
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
		entry.model:SetAttribute("Status", nil)
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

-- Вид стройплощадки: полупрозрачный корпус без крыши.
local function setSiteLook(model: Model, isSite: boolean)
	local body = model:FindFirstChild("Body") :: BasePart?
	local roof = model:FindFirstChild("Roof") :: BasePart?
	if body then
		body.Transparency = if isSite then 0.65 else 0
		body.Material = if isSite then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
	end
	if roof then
		roof.Transparency = if isSite then 1 else 0
	end
	model:SetAttribute("UnderConstruction", isSite)
end

-- Ставит здание. Возвращает true и id или false и код ошибки.
-- asSite: здание с ценой ставится стройплощадкой (при загрузке сохранения — как было).
local function create(
	typeId: string,
	x: number,
	z: number,
	rotation: number,
	asSite: boolean
): (boolean, string)
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
	if def.cost and asSite then
		entry.construction = Construction.new(def.cost, def.buildSeconds or 0)
		setSiteLook(model, true)
	end
	checkConnection(entry)
	model.Parent = folder
	entries[id] = entry
	return true, id
end

function BuildingService.place(typeId: string, x: number, z: number, rotation: number): (boolean, string)
	return create(typeId, x, z, rotation, true)
end

-- Состояние всех зданий для сохранения.
function BuildingService.snapshot(): { RegionSave.BuildingSave }
	local result = {}
	for _, entry in entries do
		local save: RegionSave.BuildingSave =
			{ typeId = entry.typeId, x = entry.x, z = entry.z, rotation = entry.rotation }
		local state = entry.state
		if state then
			save.production = {
				running = state.running,
				progress = state.progress,
				input = table.clone(state.input),
				output = table.clone(state.output),
			}
		end
		local site = entry.construction
		if site then
			save.construction = { delivered = table.clone(site.delivered), progress = site.progress }
		end
		table.insert(result, save)
	end
	return result
end

-- Восстановить здание из сохранения. Возвращает false, если место занято.
function BuildingService.restore(save: RegionSave.BuildingSave): boolean
	local ok, id = create(save.typeId, save.x, save.z, save.rotation, save.construction ~= nil)
	if not ok then
		return false
	end
	local entry = entries[id]
	local p = save.production
	if p and entry.state and entry.recipe then
		local state = entry.state
		state.running = p.running
		state.progress = math.min(p.progress, entry.recipe.cycleSeconds)
		for resource, amount in p.input do
			if entry.recipe.inputs[resource] then
				state.input[resource] = math.min(amount, entry.recipe.storage)
			end
		end
		for resource, amount in p.output do
			if entry.recipe.outputs[resource] then
				state.output[resource] = math.min(amount, entry.recipe.storage)
			end
		end
	end
	local c = save.construction
	local site = entry.construction
	if c and site then
		for resource, amount in c.delivered do
			Construction.deliver(site, resource, amount)
		end
		site.progress = math.min(c.progress, site.buildSeconds)
	end
	updateLabel(entry)
	return true
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
	if entry == nil then
		return 0
	end
	local accepted = 0
	if entry.construction then
		accepted = Construction.deliver(entry.construction, resource, amount)
	elseif entry.recipe and entry.state then
		accepted = Production.deliver(entry.recipe, entry.state, resource, amount)
	end
	updateLabel(entry)
	return accepted
end

-- Что здание может отдать (без учёта резервов грузовиков).
function BuildingService.offers(id: string): { Offer }
	local entry = entries[id]
	local result = {}
	if entry == nil or entry.construction or entry.recipe == nil or entry.state == nil then
		return result
	end
	local state = entry.state
	for resource in entry.recipe.outputs do
		local amount = state.output[resource] or 0
		if amount > 0 then
			table.insert(
				result,
				{ resource = resource, amount = amount, full = state.status == "output_full" }
			)
		end
	end
	return result
end

-- Что здание может принять (без учёта резервов): материалы стройки или сырьё.
function BuildingService.demands(id: string): { Demand }
	local entry = entries[id]
	local result = {}
	if entry == nil then
		return result
	end
	local site = entry.construction
	if site then
		for resource in site.cost do
			local need = Construction.remaining(site, resource)
			if need > 0 then
				table.insert(result, { resource = resource, amount = need })
			end
		end
	elseif entry.recipe and entry.state then
		for resource in entry.recipe.inputs do
			local space = entry.recipe.storage - (entry.state.input[resource] or 0)
			if space > 0 then
				table.insert(result, { resource = resource, amount = space })
			end
		end
	end
	return result
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
		local site = entry.construction
		if site then
			-- Стройплощадка не производит, пока не достроена.
			if Construction.tick(site, dt) then
				entry.construction = nil
				setSiteLook(entry.model, false)
				print(
					`[Пятилетка] достроено: {BuildingsConfig[entry.typeId].name.ru} ({entry.id})`
				)
			end
			updateLabel(entry)
		else
			local recipe, state = entry.recipe, entry.state
			if recipe and state then
				Production.tick(recipe, state, dt, recipe.workers)
				updateLabel(entry)
			end
		end
	end
end

return BuildingService
