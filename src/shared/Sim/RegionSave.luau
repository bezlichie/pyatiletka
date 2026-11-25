--!strict
-- Формат сохранения региона и блокировка сессии.
-- Чистый модуль: DataStore и состояние сервера передаются извне, здесь только данные.
--
-- Запись в DataStore: { lock = Lock?, region = Snapshot? }.
-- Блокировка сессии: сервер, открывший регион, пишет свой id и время. Другой сервер
-- не откроет регион, пока блокировка свежая, — так два сервера не перезапишут друг друга.

local RegionSave = {}

RegionSave.VERSION = 1

export type ProductionSave = {
	running: boolean,
	progress: number,
	input: { [string]: number },
	output: { [string]: number },
}
export type ConstructionSave = { delivered: { [string]: number }, progress: number }

export type BuildingSave = {
	typeId: string,
	x: number,
	z: number,
	rotation: number,
	production: ProductionSave?,
	construction: ConstructionSave?,
	residents: number?, -- жилое здание: сколько живёт (этап 2)
	happiness: number?, -- жилое здание: довольство 0–100
	stock: { [string]: number }?, -- магазин: склад
}

export type Snapshot = {
	version: number,
	savedAt: number,
	buildings: { BuildingSave },
	roads: { number }, -- плоский список x1, z1, x2, z2, ...: так короче
}

export type Lock = { session: string, time: number }
export type Record = { lock: Lock?, region: Snapshot? }

function RegionSave.emptySnapshot(now: number): Snapshot
	return { version = RegionSave.VERSION, savedAt = now, buildings = {}, roads = {} }
end

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and math.abs(v) < 1e6
end

local function cleanStock(t: any): { [string]: number }
	local result = {}
	if type(t) == "table" then
		for k, v in t do
			if type(k) == "string" and type(v) == "number" and v == v and v >= 0 and v < 1e9 then
				result[k] = v
			end
		end
	end
	return result
end

-- Проверяет и чистит снимок, прочитанный из DataStore. Испорченные записи пропускает.
-- knownTypes — id зданий из конфига: неизвестные (удалённые из игры) пропускаются.
function RegionSave.sanitize(raw: any, knownTypes: { [string]: any }): Snapshot?
	if type(raw) ~= "table" or raw.version ~= RegionSave.VERSION then
		return nil
	end
	local snapshot: Snapshot = {
		version = RegionSave.VERSION,
		savedAt = if type(raw.savedAt) == "number" then raw.savedAt else 0,
		buildings = {},
		roads = {},
	}
	if type(raw.buildings) == "table" then
		for _, b in raw.buildings do
			if
				type(b) == "table"
				and type(b.typeId) == "string"
				and knownTypes[b.typeId] ~= nil
				and isInt(b.x)
				and isInt(b.z)
				and isInt(b.rotation)
				and b.rotation >= 0
				and b.rotation <= 3
			then
				local entry: BuildingSave = { typeId = b.typeId, x = b.x, z = b.z, rotation = b.rotation }
				local p = b.production
				if type(p) == "table" then
					entry.production = {
						running = p.running == true,
						progress = if type(p.progress) == "number" and p.progress >= 0 then p.progress else 0,
						input = cleanStock(p.input),
						output = cleanStock(p.output),
					}
				end
				local r = b.residents
				if type(r) == "number" and r == r and r >= 0 and r < 1e6 then
					entry.residents = r
				end
				local h = b.happiness
				if type(h) == "number" and h == h and h >= 0 and h <= 100 then
					entry.happiness = h
				end
				if type(b.stock) == "table" then
					entry.stock = cleanStock(b.stock)
				end
				local c = b.construction
				if type(c) == "table" then
					entry.construction = {
						delivered = cleanStock(c.delivered),
						progress = if type(c.progress) == "number" and c.progress >= 0 then c.progress else 0,
					}
				end
				table.insert(snapshot.buildings, entry)
			end
		end
	end
	if type(raw.roads) == "table" then
		local roads = raw.roads
		for i = 1, #roads - 1, 2 do
			if isInt(roads[i]) and isInt(roads[i + 1]) then
				table.insert(snapshot.roads, roads[i])
				table.insert(snapshot.roads, roads[i + 1])
			end
		end
	end
	return snapshot
end

-- Можно ли сессии session взять или продлить блокировку.
function RegionSave.canLock(record: Record?, session: string, now: number, timeout: number): boolean
	local lock = if record then record.lock else nil
	if lock == nil or type(lock) ~= "table" then
		return true
	end
	if lock.session == session then
		return true
	end
	return type(lock.time) ~= "number" or now - lock.time > timeout
end

-- Функция-преобразование для UpdateAsync при открытии региона.
-- Возвращает новую запись (с нашей блокировкой) или nil, если регион занят другим сервером.
function RegionSave.acquire(record: Record?, session: string, now: number, timeout: number): Record?
	if not RegionSave.canLock(record, session, now, timeout) then
		return nil
	end
	return { lock = { session = session, time = now }, region = if record then record.region else nil }
end

-- Преобразование для сохранения. release = true снимает блокировку (игрок вышел).
-- Возвращает nil (не писать), если блокировку уже забрал другой сервер.
function RegionSave.store(
	record: Record?,
	session: string,
	now: number,
	timeout: number,
	snapshot: Snapshot,
	release: boolean
): Record?
	local lock = if record then record.lock else nil
	if lock and lock.session ~= session and not RegionSave.canLock(record, session, now, timeout) then
		return nil
	end
	return { lock = if release then nil else { session = session, time = now }, region = snapshot }
end

-- Преобразование для снятия блокировки без записи региона (сохранение отключено).
-- Сохранённый регион остаётся прежним. nil (не писать), если блокировка не наша.
function RegionSave.unlock(record: Record?, session: string): Record?
	if record == nil or record.lock == nil or record.lock.session ~= session then
		return nil
	end
	return { lock = nil, region = record.region }
end

return RegionSave
