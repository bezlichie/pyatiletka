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
}

export type World = {
	findPath: (from: { Cell }, to: { Cell }) -> { Cell }?,
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

-- Возможные заказы, самые выгодные первыми: сначала полные склады, потом по объёму.
function Logistics.candidates(offers: { Offer }, demands: { Demand }, config: Config): { Job }
	local jobs: { Job } = {}
	local fullness: { [Job]: boolean } = {}
	for _, offer in offers do
		if offer.amount >= config.minLoad or (offer.full and offer.amount > 0) then
			for _, demand in demands do
				if demand.resource == offer.resource and demand.id ~= offer.id and demand.amount > 0 then
					local amount = math.min(offer.amount, demand.amount, config.capacity)
					local job =
						{ from = offer.id, to = demand.id, resource = offer.resource, amount = amount }
					fullness[job] = offer.full
					table.insert(jobs, job)
				end
			end
		end
	end
	table.sort(jobs, function(a, b)
		if fullness[a] ~= fullness[b] then
			return fullness[a]
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
			if path and world.findPath(fromEntrances, toEntrances) then
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

return Logistics
