--!strict
-- Проверка команды «поставить здание», пришедшей от клиента.
-- Клиенту нельзя доверять: аргументы могут быть любого типа и любого значения.
-- Чистый модуль: конфиг зданий и сетка передаются аргументами.

local BuildCommand = {}

export type BuildingSize = { sizeX: number, sizeZ: number, era: number }

export type Command = { typeId: string, x: number, z: number, rotation: number }

export type CommandError = "bad_args" | "unknown_building" | "locked" | "too_long"

export type RoadCommand = { x1: number, z1: number, x2: number, z2: number }

local function isInteger(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and math.abs(v) < 1e6
end

-- Возвращает разобранную команду или nil и причину отказа.
-- currentEra — эпоха игрока: здания более поздних эпох ставить нельзя.
function BuildCommand.parse(
	buildings: { [string]: BuildingSize },
	currentEra: number,
	typeId: any,
	x: any,
	z: any,
	rotation: any
): (Command?, CommandError?)
	if type(typeId) ~= "string" or not isInteger(x) or not isInteger(z) or not isInteger(rotation) then
		return nil, "bad_args"
	end
	if rotation < 0 or rotation > 3 then
		return nil, "bad_args"
	end
	local building = buildings[typeId]
	if building == nil then
		return nil, "unknown_building"
	end
	if building.era > currentEra then
		return nil, "locked"
	end
	return { typeId = typeId, x = x, z = z, rotation = rotation }, nil
end

-- Команда «проложить дорогу» от (x1, z1) до (x2, z2) буквой «Г».
-- maxCells — сколько клеток можно проложить за раз.
function BuildCommand.parseRoad(
	maxCells: number,
	x1: any,
	z1: any,
	x2: any,
	z2: any
): (RoadCommand?, CommandError?)
	if not isInteger(x1) or not isInteger(z1) or not isInteger(x2) or not isInteger(z2) then
		return nil, "bad_args"
	end
	local cells = math.abs(x2 - x1) + math.abs(z2 - z1) + 1
	if cells > maxCells then
		return nil, "too_long"
	end
	return { x1 = x1, z1 = z1, x2 = x2, z2 = z2 }, nil
end

return BuildCommand
