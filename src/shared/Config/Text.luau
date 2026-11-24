--!strict
-- Тексты интерфейса. Пока показываем русские, английские добавим вместе с выбором языка (этап 2).

export type Text = { ru: string, en: string }

return {
	resources = {
		logs = { ru = "брёвна", en = "logs" },
		boards = { ru = "доски", en = "boards" },
		gravel = { ru = "гравий", en = "gravel" },
		concrete = { ru = "бетон", en = "concrete" },
		grain = { ru = "зерно", en = "grain" },
		food = { ru = "продукты", en = "food" },
		ore = { ru = "руда", en = "ore" },
		coal = { ru = "уголь", en = "coal" },
		steel = { ru = "сталь", en = "steel" },
		vehicles = { ru = "техника", en = "vehicles" },
	} :: { [string]: Text },

	status = {
		working = { ru = "работает", en = "working" },
		no_input = { ru = "нет сырья", en = "no input" },
		output_full = { ru = "склад полон", en = "storage full" },
		no_workers = { ru = "нет рабочих", en = "no workers" },
	} :: { [string]: Text },

	buildErrors = {
		bad_args = { ru = "Ошибка команды", en = "Bad command" },
		unknown_building = { ru = "Неизвестное здание", en = "Unknown building" },
		locked = { ru = "Ещё не открыто", en = "Not unlocked yet" },
		out_of_bounds = { ru = "За краем региона", en = "Outside the region" },
		occupied = { ru = "Место занято", en = "Space is taken" },
		bad_size = { ru = "Ошибка размера", en = "Bad size" },
		not_found = { ru = "Здание не найдено", en = "Building not found" },
		too_fast = { ru = "Слишком быстро", en = "Too fast" },
	} :: { [string]: Text },

	buildMode = {
		demolish = { ru = "Снос", en = "Demolish" },
		cancel = { ru = "Отмена", en = "Cancel" },
		placeHint = {
			ru = "ЛКМ — поставить · R — повернуть · та же цифра или «Отмена» — выйти",
			en = "LMB — place · R — rotate · same number or Cancel — exit",
		},
		placeHintTouch = {
			ru = "Коснитесь места, затем коснитесь ещё раз, чтобы поставить",
			en = "Tap a spot, then tap again to place",
		},
		demolishHint = {
			ru = "ЛКМ по зданию — снести · X или «Отмена» — выйти",
			en = "Click a building to demolish · X or Cancel — exit",
		},
	} :: { [string]: Text },
}
