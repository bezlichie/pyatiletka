--!strict
-- Команды от клиента: RemoteFunction в ReplicatedStorage.Remotes.
-- Каждая возвращает (true, результат) или (false, код ошибки из Config/Text.buildErrors).
-- Клиенту не доверяем: все аргументы проверяются здесь.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BuildingsConfig = require(Config:WaitForChild("Buildings"))
local RoadsConfig = require(Config:WaitForChild("Roads"))
local BuildCommand = require(Shared:WaitForChild("Sim"):WaitForChild("BuildCommand"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local RoadService = require(script.Parent:WaitForChild("RoadService"))

local Commands = {}

-- Пока у игрока одна эпоха — стартовая. Прогрессия появится вместе с пятилетним планом.
local CURRENT_ERA = 0
-- Не чаще одной команды за это время от одного игрока: защита от спама.
local COMMAND_COOLDOWN = 0.1

local lastCommand: { [Player]: number } = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	local last = lastCommand[player]
	if last and now - last < COMMAND_COOLDOWN then
		return true
	end
	lastCommand[player] = now
	return false
end

local function placeBuilding(player: Player, typeId: any, x: any, z: any, rotation: any): (boolean, any)
	if throttled(player) then
		return false, "too_fast"
	end
	local command, err = BuildCommand.parse(BuildingsConfig, CURRENT_ERA, typeId, x, z, rotation)
	if command == nil then
		return false, err or "bad_args"
	end
	local ok, result = BuildingService.place(command.typeId, command.x, command.z, command.rotation)
	if ok then
		print(`[Пятилетка] {player.Name}: {BuildingsConfig[command.typeId].name.ru} ({result}) в {command.x}, {command.z}`)
	end
	return ok, result
end

local function placeRoad(player: Player, x1: any, z1: any, x2: any, z2: any): (boolean, any)
	if throttled(player) then
		return false, "too_fast"
	end
	local command, err = BuildCommand.parseRoad(RoadsConfig.maxCellsPerCommand, x1, z1, x2, z2)
	if command == nil then
		return false, err or "bad_args"
	end
	local ok, result = RoadService.placeLine(command.x1, command.z1, command.x2, command.z2)
	if ok then
		print(`[Пятилетка] {player.Name}: дорога {command.x1},{command.z1} → {command.x2},{command.z2}, новых клеток {result}`)
	end
	return ok, result
end

local function demolish(player: Player, id: any): (boolean, any)
	if throttled(player) then
		return false, "too_fast"
	end
	if type(id) ~= "string" or #id > 64 then
		return false, "bad_args"
	end
	local ok, result
	if RoadService.isRoadId(id) then
		ok, result = RoadService.remove(id)
	else
		ok, result = BuildingService.remove(id)
	end
	if ok then
		print(`[Пятилетка] {player.Name}: снос {id}`)
	end
	return ok, result
end

function Commands.start()
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local handlers: { [string]: (Player, ...any) -> (boolean, any) } = {
		PlaceBuilding = placeBuilding,
		PlaceRoad = placeRoad,
		Demolish = demolish,
	}
	for name, handler in handlers do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = handler
		remote.Parent = remotes
	end
	remotes.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		lastCommand[player] = nil
	end)
end

return Commands
