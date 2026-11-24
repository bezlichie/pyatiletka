--!strict
-- Сохранение региона в DataStore.

return {
	dataStoreName = "Regions_v1", -- смена имени = чистый лист для всех игроков
	autosaveSeconds = 60,
	lockTimeoutSeconds = 300, -- блокировка старше этого считается брошенной (сервер упал)
	lockRetries = 4, -- сколько раз пробовать взять занятый регион
	lockRetrySeconds = 5,
}
