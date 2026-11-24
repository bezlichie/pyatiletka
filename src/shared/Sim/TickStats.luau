--!strict
-- Статистика времени тика: последние N замеров, среднее, 95-й перцентиль и максимум.
-- Чистый модуль: замеры (в миллисекундах) передаёт сервер.

local TickStats = {}

export type Stats = {
	window: number, -- сколько последних замеров хранить
	samples: { number },
	nextIndex: number, -- куда писать следующий замер (кольцевой буфер)
}

export type Summary = { count: number, avg: number, p95: number, max: number }

function TickStats.new(window: number): Stats
	return { window = math.max(1, window), samples = {}, nextIndex = 1 }
end

function TickStats.add(stats: Stats, ms: number)
	stats.samples[stats.nextIndex] = ms
	stats.nextIndex = stats.nextIndex % stats.window + 1
end

function TickStats.summary(stats: Stats): Summary
	local count = #stats.samples
	if count == 0 then
		return { count = 0, avg = 0, p95 = 0, max = 0 }
	end
	local sorted = table.clone(stats.samples)
	table.sort(sorted)
	local sum = 0
	for _, ms in sorted do
		sum += ms
	end
	local p95 = sorted[math.max(1, math.ceil(count * 0.95))]
	return { count = count, avg = sum / count, p95 = p95, max = sorted[count] }
end

return TickStats
