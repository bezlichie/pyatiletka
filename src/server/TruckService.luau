--!strict
-- Автопарки и грузовики. Сервер двигает грузовик по клеткам дорог (Sim/Logistics),
-- а клиент плавно анимирует модель (client/TruckView).
-- Автопарк выпускает грузовики, когда у него появляется подъезд к дороге.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GridConfig = require(Config:WaitForChild("Grid"))
local TrucksConfig = require(Config:WaitForChild("Trucks"))
local Text = require(Config:WaitForChild("Text"))
local Roads = require(Shared:WaitForChild("Sim"):WaitForChild("Roads"))
local Logistics = require(Shared:WaitForChild("Sim"):WaitForChild("Logistics"))
local RegionState = require(script.Parent:WaitForChild("RegionState"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))

local TruckService = {}

-- Как часто считаем грузовики. Чаще общего тика, чтобы клиенту было что сглаживать.
local STEP_SECONDS = 0.2
local TRUCK_SIZE = Vector3.new(1.8, 1.6, 3.2)
local DEPOT_TYPE = "depot"

-- shownState и shownCargo — что уже записано в атрибуты модели.
type Entry = { truck: Logistics.Truck, model: Model, root: BasePart, shownState: string?, shownCargo: number? }

local grid = RegionState.grid
local roads = RegionState.roads
local trucks: { [string]: Entry } = {}
local depotTrucks: { [string]: { string } } = {}
local nextTruckId = 1
local folder: Folder
local busyMs = 0 -- сколько миллисекунд ушло на шаги парка с прошлого вопроса (см. takeBusyMs)

-- Парк грузовиков (Sim/Logistics): резервы складов и раздача заказов живут там.
local fleet = Logistics.newFleet({
	ids = BuildingService.ids,
	offers = BuildingService.offers,
	demands = BuildingService.demands,
	findPath = function(from, to)
		return Roads.findPath(roads, from, to)
	end,
	connected = function(a, b)
		return Roads.connected(roads, a, b)
	end,
	entrances = BuildingService.entrances,
	isRoad = function(cell)
		return Roads.has(roads, cell.x, cell.z)
	end,
	take = BuildingService.take,
	deliver = BuildingService.deliver,
})

local function makePart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false -- не мешает кликам по зданиям и дорогам
	part.CanTouch = false
	return part
end

-- Модель грузовика: корпус Root и детали на нём. Все детали якорные, без сварки:
-- положение каждой задаётся смещением от корпуса (атрибут Offset), так и на клиенте.
local function makeModel(id: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = id
	local root = makePart("Root", TRUCK_SIZE, Color3.fromRGB(70, 110, 160))
	root.Anchored = true
	root.Parent = model
	local function attach(part: Part, offset: CFrame)
		part.Anchored = true
		part:SetAttribute("Offset", offset)
		part.CFrame = root.CFrame * offset
		part.Parent = model
	end
	attach(makePart("Cab", Vector3.new(1.7, 0.9, 1.1), Color3.fromRGB(220, 220, 210)), CFrame.new(0, 1.2, -1))
	-- Груз показывает клиент по атрибуту Cargo модели.
	local cargo = makePart("Cargo", Vector3.new(1.6, 0.8, 1.8), Color3.fromRGB(150, 105, 60))
	attach(cargo, CFrame.new(0, 1.2, 0.6))
	model.PrimaryPart = root
	return model, root
end

-- Ставит детали модели по их смещению от корпуса.
local function placeParts(model: Model, rootCFrame: CFrame)
	for _, child in model:GetChildren() do
		local offset = child:GetAttribute("Offset")
		if child:IsA("BasePart") and typeof(offset) == "CFrame" then
			child.CFrame = rootCFrame * offset
		end
	end
end

-- Мировое положение и направление грузовика.
local function truckCFrame(truck: Logistics.Truck): CFrame
	local fx, fz = Logistics.position(truck)
	local x = grid.originX + (fx + 0.5) * grid.cellSize
	local z = grid.originZ + (fz + 0.5) * grid.cellSize
	local pos = Vector3.new(x, GridConfig.groundHeight + 0.3 + TRUCK_SIZE.Y / 2, z)
	local path = truck.path
	if path and truck.pathIndex < #path then
		local nextCell = path[truck.pathIndex + 1]
		local dir = Vector3.new(nextCell.x - truck.cell.x, 0, nextCell.z - truck.cell.z)
		if dir.Magnitude > 0 then
			return CFrame.lookAt(pos, pos + dir)
		end
	end
	return CFrame.new(pos)
end

local function syncModel(entry: Entry)
	local truck = entry.truck
	local cf = truckCFrame(truck)
	local current = entry.root.CFrame
	-- Стоящий грузовик сохраняет направление, в котором приехал.
	if truck.path == nil or truck.pathIndex >= #(truck.path :: { any }) then
		cf = CFrame.new(cf.Position) * current.Rotation
	end
	-- Стоящие грузовики не двигаем: каждая запись CFrame уходит всем клиентам.
	if cf ~= current then
		entry.root.CFrame = cf
		placeParts(entry.model, cf)
	end
	if entry.shownState ~= truck.state then
		entry.shownState = truck.state
		entry.model:SetAttribute("State", truck.state)
	end
	if entry.shownCargo ~= truck.cargo then
		entry.shownCargo = truck.cargo
		entry.model:SetAttribute("Cargo", truck.cargo)
	end
end

local function removeTruck(id: string)
	local entry = trucks[id]
	if entry == nil then
		return
	end
	Logistics.removeTruck(fleet, id)
	entry.model:Destroy()
	trucks[id] = nil
end

-- Новые автопарки с подъездом получают грузовики, снесённые — теряют.
local function syncDepots()
	for depotId, ids in depotTrucks do
		if not BuildingService.has(depotId) then
			for _, id in ids do
				removeTruck(id)
			end
			depotTrucks[depotId] = nil
		end
	end
	for _, id in BuildingService.ids() do
		local typeId = BuildingService.info(id)
		if typeId == DEPOT_TYPE and depotTrucks[id] == nil then
			local doors = BuildingService.entrances(id)
			if #doors > 0 then
				local ids = {}
				for _ = 1, TrucksConfig.perDepot do
					local truckId = `t{nextTruckId}`
					nextTruckId += 1
					local model, root = makeModel(truckId)
					local truck = Logistics.newTruck(truckId, id, doors[1])
					local entry: Entry = { truck = truck, model = model, root = root }
					syncModel(entry)
					model.Parent = folder
					trucks[truckId] = entry
					Logistics.addTruck(fleet, truck)
					table.insert(ids, truckId)
				end
				depotTrucks[id] = ids
			end
		end
	end
end

local function updateDepotNotes()
	for depotId, ids in depotTrucks do
		local free = 0
		for _, id in ids do
			local entry = trucks[id]
			if entry and entry.truck.state == "idle" then
				free += 1
			end
		end
		BuildingService.setNote(
			depotId,
			`{Text.labels.trucks.ru}: {#ids}, {Text.labels.trucksFree.ru}: {free}`
		)
	end
end

local function step(dt: number)
	local t0 = os.clock()
	syncDepots()
	Logistics.stepFleet(fleet, dt, TrucksConfig)
	for _, entry in trucks do
		syncModel(entry)
	end
	updateDepotNotes()
	busyMs += (os.clock() - t0) * 1000
end

-- Сколько миллисекунд ушло на грузовики с прошлого вызова (для замера тика).
function TruckService.takeBusyMs(): number
	local ms = busyMs
	busyMs = 0
	return ms
end

function TruckService.count(): number
	return #fleet.trucks
end

-- Груз в кузовах по получателям — для сохранения (см. Logistics.inTransit).
function TruckService.inTransit(): { [string]: { [string]: number } }
	return Logistics.inTransit(fleet)
end

function TruckService.start(region: Model)
	folder = Instance.new("Folder")
	folder.Name = "Trucks"
	folder.Parent = region

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		while accumulator >= STEP_SECONDS do
			accumulator -= STEP_SECONDS
			step(STEP_SECONDS)
		end
	end)
end

return TruckService
