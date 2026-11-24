--!strict
-- Сохранение региона в DataStore с блокировкой сессии.
-- Пока регион один на сервер: им владеет первый вошедший игрок, сохраняется под его UserId.
-- Остальные игроки строят в том же регионе, но их изменения сохраняются владельцу.
--
-- В Studio DataStore работает, только если плейс опубликован в Roblox и включено
-- File → Experience Settings → Security → Enable Studio Access to API Services.
-- Иначе игра идёт без сохранения.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Buildings"))
local SaveConfig = require(Shared:WaitForChild("Config"):WaitForChild("Save"))
local RegionSave = require(Shared:WaitForChild("Sim"):WaitForChild("RegionSave"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local TruckService = require(script.Parent:WaitForChild("TruckService"))
local RoadService = require(script.Parent:WaitForChild("RoadService"))

local SaveService = {}

-- Id этого сервера для блокировки. JobId в Studio пустой, поэтому свой GUID.
local SESSION = HttpService:GenerateGUID(false)

local store: DataStore? = nil
local ownerId: number? = nil
local key: string? = nil
local opened = false -- регион загружен и блокировка наша
local released = false
local saving = false
local disabledReason: string? = nil -- сохранение отключено (стресс-тест)

local function log(text: string)
	print(`[Пятилетка] {text}`)
end

local function apply(snapshot: RegionSave.Snapshot)
	-- Сначала здания, потом дороги: так дороги не займут клетки под зданиями.
	local placed = 0
	for _, b in snapshot.buildings do
		if BuildingService.restore(b) then
			placed += 1
		end
	end
	local roadCells = RoadService.restore(snapshot.roads)
	log(`регион загружен: зданий {placed}, клеток дорог {roadCells}`)
end

local function open(player: Player)
	local ds = store
	local k = key
	if ds == nil or k == nil then
		return
	end
	for attempt = 1, SaveConfig.lockRetries do
		local locked = false
		local loaded: any = nil
		local ok, err = pcall(function()
			ds:UpdateAsync(k, function(old)
				local record = RegionSave.acquire(old, SESSION, os.time(), SaveConfig.lockTimeoutSeconds)
				if record == nil then
					locked = true
					return nil -- не писать: регион открыт другим сервером
				end
				loaded = record.region
				return record
			end)
		end)
		if not ok then
			warn(
				`[Пятилетка] сохранение недоступно, игра идёт без него: {err}. `
					.. "В Studio: опубликуйте плейс и включите File → Experience Settings → Security → "
					.. "Enable Studio Access to API Services."
			)
			store = nil
			return
		end
		if not locked then
			opened = true
			local snapshot = RegionSave.sanitize(loaded, BuildingsConfig)
			if snapshot then
				apply(snapshot)
			else
				log("новый регион: сохранения ещё нет")
			end
			return
		end
		log(
			`регион открыт на другом сервере, попытка {attempt} из {SaveConfig.lockRetries}`
		)
		task.wait(SaveConfig.lockRetrySeconds)
		if player.Parent == nil then
			return
		end
	end
	player:Kick(
		"Ваш регион сейчас открыт на другом сервере. Попробуйте зайти через минуту."
	)
end

-- Сохранить регион. release = true снимает блокировку (владелец вышел, сервер закрывается).
local function save(release: boolean)
	local ds = store
	local k = key
	if ds == nil or k == nil or not opened or released or disabledReason ~= nil then
		return
	end
	while saving do
		task.wait(0.1)
	end
	saving = true
	local snapshot: RegionSave.Snapshot = {
		version = RegionSave.VERSION,
		savedAt = os.time(),
		-- Груз в кузовах засчитывается получателям: грузовики не сохраняются.
		buildings = BuildingService.snapshot(TruckService.inTransit()),
		roads = RoadService.snapshot(),
	}
	local refused = false
	local ok, err = pcall(function()
		ds:UpdateAsync(k, function(old)
			local record =
				RegionSave.store(old, SESSION, os.time(), SaveConfig.lockTimeoutSeconds, snapshot, release)
			refused = record == nil
			return record
		end)
	end)
	saving = false
	if not ok then
		warn(`[Пятилетка] не удалось сохранить регион: {err}`)
	elseif refused then
		-- Блокировку забрал другой сервер: этот больше не пишет, чтобы не затереть.
		opened = false
		warn(
			"[Пятилетка] регион открыт на другом сервере, сохранение остановлено"
		)
	else
		log(
			`регион сохранён: зданий {#snapshot.buildings}, клеток дорог {math.floor(
				#snapshot.roads / 2
			)}`
		)
		if release then
			released = true
		end
	end
end

-- Отключить сохранение до конца сессии (стресс-тест в Studio не должен попасть в сохранение).
function SaveService.disable(reason: string)
	if disabledReason ~= nil then
		return
	end
	disabledReason = reason
	warn(`[Пятилетка] сохранение отключено до конца игры: {reason}`)
	-- Снять блокировку сразу, не трогая сохранённый регион: иначе следующий запуск
	-- ждал бы, пока блокировка устареет.
	local ds, k = store, key
	if ds == nil or k == nil or not opened or released then
		return
	end
	released = true
	task.spawn(function()
		while saving do
			task.wait(0.1)
		end
		local ok, err = pcall(function()
			ds:UpdateAsync(k, function(old)
				return RegionSave.unlock(old, SESSION)
			end)
		end)
		if not ok then
			warn(
				`[Пятилетка] не удалось снять блокировку региона: {err}`
			)
		end
	end)
end

local function onPlayerAdded(player: Player)
	if ownerId ~= nil then
		return -- регион уже чей-то: гость строит в нём же
	end
	ownerId = player.UserId
	key = `region_{player.UserId}`
	open(player)
end

function SaveService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(SaveConfig.dataStoreName)
	end)
	if ok then
		store = result
	else
		warn(
			`[Пятилетка] DataStore недоступен, игра идёт без сохранения: {result}`
		)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player.UserId == ownerId then
			save(true)
		end
	end)
	game:BindToClose(function()
		save(true)
	end)

	task.spawn(function()
		while true do
			task.wait(SaveConfig.autosaveSeconds)
			save(false)
		end
	end)
end

return SaveService
