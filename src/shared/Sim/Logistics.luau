--!strict
-- Логистика: заказы на перевозку и поведение грузовика.
-- Чистый модуль: мир (дороги, склады зданий) передаётся набором функций World,
-- поэтому логика тестируется в Lune без Studio.
--
-- Цикл грузовика: idle → to_pickup → loading → to_dropoff → unloading → idle.
-- Свободный грузовик вдали от автопарка едет домой (returning).
-- Если получателя снесли, груз не пропадает: грузовик ищет другого получателя,
-- а если его нет — возвращается с грузом в автопарк и ждёт, пока он появится.

local Logistics = {}

export type Cell = { x: number, z: number }

export type Job = {
	from: string, -- id здания, откуда забрать
	to: string, -- id здания, куда привезти
	resource: string,
	amount: number, -- сколько зарезервировано
}

export type TruckState = "idle" | "to_pickup" | "loading" | "to_dropoff" | "unloading" | "returning"

export type Truck = {
	id: string,
	depotId: string,
	state: TruckState,
	cell: Cell, -- клетка дороги, где грузовик сейчас
	path: { Cell }?, -- текущий маршрут, path[1] — откуда выехал
	pathIndex: number, -- индекс клетки маршрута, на которой грузовик
	progress: number, -- доля пути до следующей клетки (0..1)
	job: Job?,
	cargo: number,
	cargoResource: string?, -- что в кузове
	timer: number, -- оставшееся время погрузки или разгрузки
}

-- Склад, с которого можно забрать: свободный (не зарезервированный) остаток.
export type Offer = { id: string, resource: string, amount: number, full: boolean }
-- Склад, который принимает: свободное (не зарезервированное) место.
export type Demand = { id: string, resource: string, amount: number }

export type Config = {
	capacity: number,
	minLoad: number,
	cellsPerSecond: number,
	loadSeconds: number,
	unloadSeconds: number,
	maxCandidates: number?, -- сколько заказов рассматривать за раз (нет — все)
	maxDispatchPerStep: number?, -- сколько свободных грузовиков ищут заказ за один шаг парка
	serviceRadius: number?, -- заказы только в этом радиусе от автопарка, в клетках (нет — по всей карте)
}

export type World = {
	findPath: (from: { Cell }, to: { Cell }) -> { Cell }?,
	-- Есть ли дорога между клетками (без построения маршрута). Нет — проверяется через findPath.
	connected: ((from: { Cell }, to: { Cell }) -> boolean)?,
	entrances: (buildingId: string) -> { Cell }, -- пусто, если здания нет или нет подъезда
	isRoad: (cell: Cell) -> boolean,
	take: (buildingId: string, resource: string, amount: number) -> number,
	deliver: (buildingId: string, resource: string, amount: number) -> number,
	-- Снять резерв: side = "out" (у отправителя) или "in" (у получателя).
	release: (job: Job, side: "out" | "in") -> (),
	-- Найти получателя для груза в кузове и зарезервировать у него место.
	-- Возвращает id здания и сколько зарезервировано или nil.
	claimDemand: (resource: string, amount: number) -> (string?, number),
}

function Logistics.newTruck(id: string, depotId: string, cell: Cell): Truck
	return {
		id = id,
		depotId = depotId,
		state = "idle",
		cell = cell,
		path = nil,
		pathIndex = 1,
		progress = 0,
		job = nil,
		cargo = 0,
		cargoResource = nil,
		timer = 0,
	}
end

-- Возможные заказы, самые выгодные первыми: сначала полные склады, потом ближние
-- (если передано расстояние distance между зданиями), потом по объёму.
-- Чтобы не перебирать все пары «откуда — куда» на большой карте, берутся лучшие
-- отправители и для каждого лучшие получатели, пока не наберётся config.maxCandidates заказов.
function Logistics.candidates(
	offers: { Offer },
	demands: { Demand },
	config: Config,
	distance: ((fromId: string, toId: string) -> number)?
): { Job }
	local eligible: { Offer } = {}
	for _, offer in offers do
		if offer.amount >= config.minLoad or (offer.full and offer.amount > 0) then
			table.insert(eligible, offer)
		end
	end
	table.sort(eligible, function(a, b)
		if a.full ~= b.full then
			return a.full
		end
		return a.amount > b.amount
	end)
	local byResource: { [string]: { Demand } } = {}
	for _, demand in demands do
		if demand.amount > 0 then
			local list = byResource[demand.resource]
			if list == nil then
				list = {}
				byResource[demand.resource] = list
			end
			table.insert(list, demand)
		end
	end
	for _, list in byResource do
		table.sort(list, function(a, b)
			return a.amount > b.amount
		end)
	end

	local limit = config.maxCandidates or math.huge
	local jobs: { Job } = {}
	local fullness: { [Job]: boolean } = {}
	local far: { [Job]: number } = {}
	for _, offer in eligible do
		local list = byResource[offer.resource] or {}
		local gaps: { [Demand]: number } = {}
		if distance then
			-- Для этого отправителя ближние получатели первыми.
			list = table.clone(list)
			for _, demand in list do
				gaps[demand] = distance(offer.id, demand.id)
			end
			table.sort(list, function(a, b)
				if gaps[a] ~= gaps[b] then
					return gaps[a] < gaps[b]
				end
				return a.amount > b.amount
			end)
		end
		for _, demand in list do
			if demand.id ~= offer.id then
				local amount = math.min(offer.amount, demand.amount, config.capacity)
				local job = { from = offer.id, to = demand.id, resource = offer.resource, amount = amount }
				fullness[job] = offer.full
				far[job] = gaps[demand] or 0
				table.insert(jobs, job)
				if #jobs >= limit then
					break
				end
			end
		end
		if #jobs >= limit then
			break
		end
	end
	table.sort(jobs, function(a, b)
		if fullness[a] ~= fullness[b] then
			return fullness[a]
		end
		if far[a] ~= far[b] then
			return far[a] < far[b]
		end
		return a.amount > b.amount
	end)
	return jobs
end

local function startPath(truck: Truck, path: { Cell }, state: TruckState)
	truck.path = path
	truck.pathIndex = 1
	truck.progress = 0
	truck.state = state
end

-- Пытается выдать свободному грузовику первый заказ, до отправителя которого есть дорога.
-- Возвращает выданный заказ (его резерв должен сделать вызывающий) или nil.
function Logistics.dispatch(truck: Truck, jobs: { Job }, world: World): Job?
	if truck.state ~= "idle" or truck.cargo > 0 then
		return nil -- грузовик с грузом сначала отвозит его (Logistics.redirect)
	end
	for _, job in jobs do
		local fromEntrances = world.entrances(job.from)
		local toEntrances = world.entrances(job.to)
		if #fromEntrances > 0 and #toEntrances > 0 then
			-- Есть дорога до отправителя и от отправителя до получателя.
			local path = world.findPath({ truck.cell }, fromEntrances)
			local connected = world.connected
			local linked = if connected
				then connected(fromEntrances, toEntrances)
				else world.findPath(fromEntrances, toEntrances) ~= nil
			if path and linked then
				truck.job = job
				startPath(truck, path, "to_pickup")
				return job
			end
		end
	end
	return nil
end

-- Отправить свободный грузовик домой, если он не у автопарка.
function Logistics.sendHome(truck: Truck, world: World)
	if truck.state ~= "idle" then
		return
	end
	local home = world.entrances(truck.depotId)
	for _, c in home do
		if c.x == truck.cell.x and c.z == truck.cell.z then
			return
		end
	end
	local path = world.findPath({ truck.cell }, home)
	if path then
		startPath(truck, path, "returning")
	end
end

-- Сорвать заказ: снять резервы, грузовик свободен там, где стоит.
-- Груз в кузове сохраняется: его отвезёт Logistics.redirect.
function Logistics.abort(truck: Truck, world: World)
	local job = truck.job
	if job then
		if truck.state == "to_pickup" or truck.state == "loading" then
			world.release(job, "out")
		end
		world.release(job, "in")
	end
	truck.job = nil
	truck.path = nil
	truck.state = "idle"
	if truck.cargo <= 0 then
		truck.cargo = 0
		truck.cargoResource = nil
	end
end

-- Груз в кузове, а заказа нет: везём его новому получателю, а если такого нет —
-- едем домой и ждём. Резерв прежнего получателя должен быть уже снят.
function Logistics.redirect(truck: Truck, world: World)
	truck.job = nil
	truck.path = nil
	truck.state = "idle"
	local resource = truck.cargoResource
	if resource == nil or truck.cargo <= 0 then
		truck.cargo = 0
		truck.cargoResource = nil
		return
	end
	local to, amount = world.claimDemand(resource, truck.cargo)
	if to then
		local job = { from = "", to = to, resource = resource, amount = amount }
		local path = world.findPath({ truck.cell }, world.entrances(to))
		if path then
			truck.job = job
			startPath(truck, path, "to_dropoff")
			return
		end
		world.release(job, "in")
	end
	Logistics.sendHome(truck, world)
end

-- Перестроить маршрут до той же цели, если дорогу впереди снесли.
local function reroute(truck: Truck, world: World): boolean
	local path = truck.path
	if path == nil then
		return false
	end
	local goal = path[#path]
	if not world.isRoad(truck.cell) then
		return false
	end
	local newPath = world.findPath({ truck.cell }, { goal })
	if newPath == nil then
		return false
	end
	truck.path = newPath
	truck.pathIndex = 1
	return true
end

-- Двигает грузовик по маршруту. Возвращает true, когда он доехал до конца.
local function advance(truck: Truck, dt: number, config: Config, world: World): boolean
	local path = truck.path
	if path == nil then
		return true
	end
	truck.progress += dt * config.cellsPerSecond
	while truck.progress >= 1 and truck.pathIndex < #path do
		local nextCell = path[truck.pathIndex + 1]
		if not world.isRoad(nextCell) then
			if not reroute(truck, world) then
				return false
			end
			path = truck.path :: { Cell }
			if #path == 1 then
				break
			end
			nextCell = path[2]
		end
		truck.pathIndex += 1
		truck.progress -= 1
		truck.cell = nextCell
	end
	if truck.pathIndex >= #path then
		truck.progress = 0
		return true
	end
	return false
end

-- Положение грузовика в клетках (дробное, между клетками маршрута).
function Logistics.position(truck: Truck): (number, number)
	local path = truck.path
	if path == nil or truck.pathIndex >= #path then
		return truck.cell.x, truck.cell.z
	end
	local a, b = path[truck.pathIndex], path[truck.pathIndex + 1]
	local t = math.clamp(truck.progress, 0, 1)
	return a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
end

-- Один шаг грузовика на dt секунд.
function Logistics.step(truck: Truck, dt: number, config: Config, world: World)
	local state = truck.state
	local job = truck.job

	-- Получателя снесли: грузовик сразу реагирует, а не едет к пустому месту.
	if job and (state == "to_pickup" or state == "loading") then
		if #world.entrances(job.from) == 0 or #world.entrances(job.to) == 0 then
			Logistics.abort(truck, world)
			return
		end
	elseif job and (state == "to_dropoff" or state == "unloading") then
		if #world.entrances(job.to) == 0 then
			world.release(job, "in")
			Logistics.redirect(truck, world)
			return
		end
	end

	if state == "to_pickup" or state == "to_dropoff" or state == "returning" then
		-- Дорогу снесли так, что маршрута нет: заказ срывается, груз остаётся в кузове.
		local path = truck.path
		if path and truck.pathIndex < #path and not world.isRoad(path[truck.pathIndex + 1]) then
			if not reroute(truck, world) then
				Logistics.abort(truck, world)
				return
			end
		end
		if not advance(truck, dt, config, world) then
			return
		end
		truck.path = nil
		if state == "returning" then
			truck.state = "idle"
		elseif state == "to_pickup" then
			truck.state = "loading"
			truck.timer = config.loadSeconds
		else
			truck.state = "unloading"
			truck.timer = config.unloadSeconds
		end
	elseif state == "loading" and job then
		truck.timer -= dt
		if truck.timer > 0 then
			return
		end
		truck.cargo = world.take(job.from, job.resource, job.amount)
		truck.cargoResource = job.resource
		world.release(job, "out")
		if truck.cargo <= 0 then
			Logistics.abort(truck, world)
			return
		end
		local path = world.findPath({ truck.cell }, world.entrances(job.to))
		if path == nil then
			world.release(job, "in")
			Logistics.redirect(truck, world)
			return
		end
		startPath(truck, path, "to_dropoff")
	elseif state == "unloading" and job then
		truck.timer -= dt
		if truck.timer > 0 then
			return
		end
		local accepted = world.deliver(job.to, job.resource, truck.cargo)
		world.release(job, "in")
		truck.cargo -= accepted
		-- Не всё приняли: остаток везём дальше.
		Logistics.redirect(truck, world)
	end
end

-- Парк грузовиков региона: все грузовики, резервы складов и раздача заказов.
-- Резервы не дают двум грузовикам поехать за одним и тем же грузом
-- или привезти в склад больше, чем в нём места.

-- Что нужно парку от региона: здания, их склады и дороги.
export type Source = {
	ids: () -> { string },
	offers: (id: string) -> { { resource: string, amount: number, full: boolean } },
	demands: (id: string) -> { { resource: string, amount: number } },
	findPath: (from: { Cell }, to: { Cell }) -> { Cell }?,
	connected: ((from: { Cell }, to: { Cell }) -> boolean)?,
	entrances: (buildingId: string) -> { Cell },
	isRoad: (cell: Cell) -> boolean,
	take: (buildingId: string, resource: string, amount: number) -> number,
	deliver: (buildingId: string, resource: string, amount: number) -> number,
}

type Reserves = { [string]: { [string]: number } }

export type Fleet = {
	source: Source,
	world: World,
	trucks: { Truck }, -- в порядке появления
	reservedOut: Reserves, -- сколько уже обещано забрать у здания
	reservedIn: Reserves, -- сколько уже обещано привезти в здание
	cursor: number, -- с какого грузовика начинать раздачу заказов (по кругу)
}

local function reserve(map: Reserves, id: string, resource: string, delta: number)
	local byRes = map[id]
	if byRes == nil then
		byRes = {}
		map[id] = byRes
	end
	local value = math.max(0, (byRes[resource] or 0) + delta)
	byRes[resource] = if value > 0 then value else nil
	if next(byRes) == nil then
		map[id] = nil
	end
end

local function reserved(map: Reserves, id: string, resource: string): number
	local byRes = map[id]
	return if byRes then byRes[resource] or 0 else 0
end

function Logistics.newFleet(source: Source): Fleet
	local reservedOut: Reserves = {}
	local reservedIn: Reserves = {}
	local world: World = {
		findPath = source.findPath,
		connected = source.connected,
		entrances = source.entrances,
		isRoad = source.isRoad,
		take = source.take,
		deliver = source.deliver,
		release = function(job, side)
			if side == "out" then
				reserve(reservedOut, job.from, job.resource, -job.amount)
			else
				reserve(reservedIn, job.to, job.resource, -job.amount)
			end
		end,
		claimDemand = function(resource, amount)
			local bestId, bestSpace = nil, 0
			for _, id in source.ids() do
				for _, demand in source.demands(id) do
					if demand.resource == resource then
						local space = demand.amount - reserved(reservedIn, id, resource)
						if space > bestSpace then
							bestId, bestSpace = id, space
						end
					end
				end
			end
			if bestId == nil then
				return nil, 0
			end
			local claimed = math.min(amount, bestSpace)
			reserve(reservedIn, bestId, resource, claimed)
			return bestId, claimed
		end,
	}
	return {
		source = source,
		world = world,
		trucks = {},
		reservedOut = reservedOut,
		reservedIn = reservedIn,
		cursor = 1,
	}
end

function Logistics.addTruck(fleet: Fleet, truck: Truck)
	table.insert(fleet.trucks, truck)
end

-- Убрать грузовик (снесли автопарк). Его заказ срывается, резервы снимаются.
function Logistics.removeTruck(fleet: Fleet, id: string): Truck?
	for i, truck in fleet.trucks do
		if truck.id == id then
			Logistics.abort(truck, fleet.world)
			table.remove(fleet.trucks, i)
			return truck
		end
	end
	return nil
end

-- Что можно забрать и куда можно привезти с учётом резервов.
local function collectOrders(fleet: Fleet): ({ Offer }, { Demand })
	local source = fleet.source
	local offers, demands = {}, {}
	for _, id in source.ids() do
		for _, offer in source.offers(id) do
			local free = offer.amount - reserved(fleet.reservedOut, id, offer.resource)
			if free > 0 then
				table.insert(offers, { id = id, resource = offer.resource, amount = free, full = offer.full })
			end
		end
		for _, demand in source.demands(id) do
			local space = demand.amount - reserved(fleet.reservedIn, id, demand.resource)
			if space > 0 then
				table.insert(demands, { id = id, resource = demand.resource, amount = space })
			end
		end
	end
	return offers, demands
end

-- Вычесть выданный заказ из списков, чтобы следующий грузовик не взял тот же груз.
local function consume(offers: { Offer }, demands: { Demand }, job: Job)
	for _, offer in offers do
		if offer.id == job.from and offer.resource == job.resource then
			offer.amount -= job.amount
		end
	end
	for _, demand in demands do
		if demand.id == job.to and demand.resource == job.resource then
			demand.amount -= job.amount
		end
	end
end

-- Один шаг всего парка: свободные грузовики получают заказы, все грузовики едут.
-- Заказы ищут не больше config.maxDispatchPerStep грузовиков за шаг, по кругу,
-- чтобы при сотне свободных машин шаг оставался дешёвым. Остальные ждут следующего шага.
function Logistics.stepFleet(fleet: Fleet, dt: number, config: Config)
	local world = fleet.world
	local trucks = fleet.trucks
	local count = #trucks
	local budget = config.maxDispatchPerStep or math.huge
	local offers: { Offer }?, demands: { Demand }?
	-- Заказы для автопарка (с радиусом) или общие (без радиуса), пересчитываются после выдачи.
	local jobsByDepot: { [string]: { Job } } = {}
	local radius = config.serviceRadius

	local function within(id: string, home: Cell): boolean
		local door = world.entrances(id)[1]
		return door ~= nil and math.abs(door.x - home.x) + math.abs(door.z - home.z) <= (radius :: number)
	end

	-- Расстояние между зданиями по первым подъездам (по сторонам, без диагоналей).
	local function distance(fromId: string, toId: string): number
		local a, b = world.entrances(fromId)[1], world.entrances(toId)[1]
		if a == nil or b == nil then
			return math.huge
		end
		return math.abs(a.x - b.x) + math.abs(a.z - b.z)
	end

	local function jobsFor(truck: Truck): { Job }
		local key = if radius then truck.depotId else ""
		local cached = jobsByDepot[key]
		if cached then
			return cached
		end
		if offers == nil or demands == nil then
			offers, demands = collectOrders(fleet)
		end
		local o, d = offers :: { Offer }, demands :: { Demand }
		if radius then
			local home = world.entrances(truck.depotId)[1] or truck.cell
			local nearOffers, nearDemands = {}, {}
			for _, offer in o do
				if offer.amount > 0 and within(offer.id, home) then
					table.insert(nearOffers, offer)
				end
			end
			for _, demand in d do
				if demand.amount > 0 and within(demand.id, home) then
					table.insert(nearDemands, demand)
				end
			end
			o, d = nearOffers, nearDemands
		end
		local list = Logistics.candidates(o, d, config, distance)
		jobsByDepot[key] = list
		return list
	end

	if count > 0 then
		local start = ((fleet.cursor - 1) % count) + 1
		local lastTried = start - 1
		for n = 0, count - 1 do
			local i = ((start - 1 + n) % count) + 1
			local truck = trucks[i]
			if truck.state == "idle" then
				if not world.isRoad(truck.cell) then
					-- Дорогу под стоящим грузовиком снесли: он переносится к автопарку.
					local doors = world.entrances(truck.depotId)
					if #doors > 0 then
						truck.cell = doors[1]
					end
				end
				if truck.cargo > 0 then
					-- Груз остался в кузове (получателя снесли): ищем, куда его отвезти.
					Logistics.redirect(truck, world)
				elseif budget > 0 then
					local list = jobsFor(truck)
					local job = nil
					if #list > 0 then
						budget -= 1
						lastTried = i
						job = Logistics.dispatch(truck, list, world)
					end
					if job then
						reserve(fleet.reservedOut, job.from, job.resource, job.amount)
						reserve(fleet.reservedIn, job.to, job.resource, job.amount)
						consume(offers :: { Offer }, demands :: { Demand }, job)
						table.clear(jobsByDepot) -- заказы изменились, пересчитать для следующего
					else
						Logistics.sendHome(truck, world)
					end
				end
			end
		end
		fleet.cursor = lastTried + 1
	end

	for _, truck in trucks do
		Logistics.step(truck, dt, config, world)
	end
end

-- Груз в кузовах, который едет к получателю: id здания -> ресурс -> сколько.
-- Нужен для сохранения: грузовики не сохраняются, а их груз засчитывается получателю.
function Logistics.inTransit(fleet: Fleet): { [string]: { [string]: number } }
	local result: { [string]: { [string]: number } } = {}
	for _, truck in fleet.trucks do
		local job = truck.job
		local resource = truck.cargoResource
		if
			job
			and resource
			and truck.cargo > 0
			and (truck.state == "to_dropoff" or truck.state == "unloading")
		then
			local byRes = result[job.to]
			if byRes == nil then
				byRes = {}
				result[job.to] = byRes
			end
			byRes[resource] = (byRes[resource] or 0) + truck.cargo
		end
	end
	return result
end

return Logistics
