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
local TruckModel = require(Shared:WaitForChild("Visual"):WaitForChild("TruckModel"))
local RegionState = require(script.Parent:WaitForChild("RegionState"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))

local TruckService = {}

-- Как часто считаем грузовики. Чаще общего тика, чтобы клиенту было что сглаживать.
local STEP_SECONDS = 0.2
local DEPOT_TYPE = "depot"

-- shown* — что уже записано в атрибуты модели (чтобы не писать то же самое).
type Entry = {
	truck: Logistics.Truck,
	model: Model,
	shownCFrame: CFrame?,
	shownState: string?,
	shownCargo: number?,
}

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

-- Грузовик на сервере — пустая модель с атрибутами: CFrame (положение), State, Cargo.
-- Детали не создаются и не двигаются: модель строит и плавно ведёт клиент (client/TruckView).
-- Так на каждый шаг приходится одна запись атрибута, а не перестановка трёх деталей.
local function makeModel(id: string): Model
	local model = Instance.new("Model")
	model.Name = id
	return model
end

-- Мировое положение и направление грузовика.
local function truckCFrame(truck: Logistics.Truck): CFrame
	local fx, fz = Logistics.position(truck)
	local x = grid.originX + (fx + 0.5) * grid.cellSize
	local z = grid.originZ + (fz + 0.5) * grid.cellSize
	local pos = Vector3.new(x, GridConfig.groundHeight + 0.3 + TruckModel.size.Y / 2, z)
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
	local current = entry.shownCFrame
	-- Стоящий грузовик сохраняет направление, в котором приехал.
	if current and (truck.path == nil or truck.pathIndex >= #(truck.path :: { any })) then
		cf = CFrame.new(cf.Position) * current.Rotation
	end
	-- Стоящие грузовики не трогаем: каждая запись уходит всем клиентам.
	if cf ~= current then
		entry.shownCFrame = cf
		entry.model:SetAttribute("CFrame", cf)
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
					local model = makeModel(truckId)
					local truck = Logistics.newTruck(truckId, id, doors[1])
					local entry: Entry = { truck = truck, model = model }
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
