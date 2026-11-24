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

type Entry = { truck: Logistics.Truck, model: Model, root: BasePart }

local grid = RegionState.grid
local roads = RegionState.roads
local trucks: { [string]: Entry } = {}
local depotTrucks: { [string]: { string } } = {}
-- Резервы: сколько уже обещано забрать у здания и привезти в здание.
local reservedOut: { [string]: { [string]: number } } = {}
local reservedIn: { [string]: { [string]: number } } = {}
local nextTruckId = 1
local folder: Folder

local function reserve(map: { [string]: { [string]: number } }, id: string, resource: string, delta: number)
	local byRes = map[id]
	if byRes == nil then
		byRes = {}
		map[id] = byRes
	end
	byRes[resource] = math.max(0, (byRes[resource] or 0) + delta)
end

local function reserved(map: { [string]: { [string]: number } }, id: string, resource: string): number
	local byRes = map[id]
	return if byRes then byRes[resource] or 0 else 0
end

local world: Logistics.World = {
	findPath = function(from, to)
		return Roads.findPath(roads, from, to)
	end,
	entrances = BuildingService.entrances,
	isRoad = function(cell)
		return Roads.has(roads, cell.x, cell.z)
	end,
	take = BuildingService.take,
	deliver = BuildingService.deliver,
	release = function(job, side)
		if side == "out" then
			reserve(reservedOut, job.from, job.resource, -job.amount)
		else
			reserve(reservedIn, job.to, job.resource, -job.amount)
		end
	end,
}

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

-- Модель грузовика: корпус (Root, якорный) и приваренные кабина и груз.
local function makeModel(id: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = id
	local root = makePart("Root", TRUCK_SIZE, Color3.fromRGB(70, 110, 160))
	root.Anchored = true
	root.Parent = model
	local function attach(part: Part, offset: CFrame)
		part.Anchored = false
		part.CFrame = root.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
	attach(makePart("Cab", Vector3.new(1.7, 0.9, 1.1), Color3.fromRGB(220, 220, 210)), CFrame.new(0, 1.2, -1))
	local cargo = makePart("Cargo", Vector3.new(1.6, 0.8, 1.8), Color3.fromRGB(150, 105, 60))
	cargo.Transparency = 1
	attach(cargo, CFrame.new(0, 1.2, 0.6))
	model.PrimaryPart = root
	return model, root
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
	entry.root.CFrame = cf
	entry.model:SetAttribute("State", truck.state)
	entry.model:SetAttribute("Cargo", truck.cargo)
	local cargo = entry.model:FindFirstChild("Cargo") :: BasePart?
	if cargo then
		cargo.Transparency = if truck.cargo > 0 then 0 else 1
	end
end

local function removeTruck(id: string)
	local entry = trucks[id]
	if entry == nil then
		return
	end
	Logistics.abort(entry.truck, world)
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
					local entry =
						{ truck = Logistics.newTruck(truckId, id, doors[1]), model = model, root = root }
					syncModel(entry)
					model.Parent = folder
					trucks[truckId] = entry
					table.insert(ids, truckId)
				end
				depotTrucks[id] = ids
			end
		end
	end
end

-- Что можно забрать и куда можно привезти с учётом резервов.
local function collectOrders(): ({ Logistics.Offer }, { Logistics.Demand })
	local offers, demands = {}, {}
	for _, id in BuildingService.ids() do
		local _, recipe, state = BuildingService.info(id)
		if recipe and state then
			for resource in recipe.outputs do
				local free = (state.output[resource] or 0) - reserved(reservedOut, id, resource)
				if free > 0 then
					table.insert(offers, {
						id = id,
						resource = resource,
						amount = free,
						full = state.status == "output_full",
					})
				end
			end
			for resource in recipe.inputs do
				local space = recipe.storage
					- (state.input[resource] or 0)
					- reserved(reservedIn, id, resource)
				if space > 0 then
					table.insert(demands, { id = id, resource = resource, amount = space })
				end
			end
		end
	end
	return offers, demands
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
	syncDepots()
	for _, entry in trucks do
		local truck = entry.truck
		if truck.state == "idle" and not world.isRoad(truck.cell) then
			-- Дорогу под стоящим грузовиком снесли: он возвращается к автопарку.
			local doors = BuildingService.entrances(truck.depotId)
			if #doors > 0 then
				truck.cell = doors[1]
			end
		end
		if truck.state == "idle" then
			-- Заказы пересчитываем для каждого грузовика: предыдущий мог занять резерв.
			local offers, demands = collectOrders()
			local job = Logistics.dispatch(truck, Logistics.candidates(offers, demands, TrucksConfig), world)
			if job then
				reserve(reservedOut, job.from, job.resource, job.amount)
				reserve(reservedIn, job.to, job.resource, job.amount)
			else
				Logistics.sendHome(truck, world)
			end
		end
		Logistics.step(truck, dt, TrucksConfig, world)
		syncModel(entry)
	end
	updateDepotNotes()
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
