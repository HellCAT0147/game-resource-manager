-- LootHelper — загрузчик (стабильный, менять не нужно).
-- Вся логика разведки/чтения — в scan.lua, который перечитывается dofile'ом
-- на КАЖДОЕ нажатие клавиши: скрипт можно править, НЕ перезапуская игру.
--
-- F8 — вкл/выкл запись инвентаря (hover-скан тултипа).
-- F7 — вкл/выкл оверлей «Выгодный хабар» (рейтинг ₽/кг поверх игры).
--
-- Всё пишется в UE4SS.log (Stalker2/Binaries/Win64/ue4ss/UE4SS.log).

local SCRIPTS = "D:/Games/STALKER2/Stalker2/Binaries/Win64/ue4ss/Mods/LootHelper/Scripts/"

local function log(msg)
    print("[LootHelper] " .. tostring(msg) .. "\n")
end

log("Загружен. В игре: F8 = запись инвентаря, F7 = оверлей ₽/кг.")

local function runScan(mode)
    ExecuteInGameThread(function()
        _LOOT_MODE = mode
        local ok, err = pcall(dofile, SCRIPTS .. "scan.lua")
        if not ok then log("ОШИБКА scan.lua: " .. tostring(err)) end
    end)
end

RegisterKeyBind(Key.F8, function() runScan("fast") end)
RegisterKeyBind(Key.F7, function() runScan("deep") end)
