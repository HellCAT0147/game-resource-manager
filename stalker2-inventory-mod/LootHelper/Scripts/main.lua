-- LootHelper — ШАГ 1: РАЗВЕДКА.
-- Задача этого скрипта — НЕ читать инвентарь по-настоящему, а убедиться, что
-- UE4SS работает, дотянуться до игрока и напечатать «якоря» (имена классов),
-- по которым мы дальше найдём объект инвентаря и его поля (стоимость/вес/кол-во).
--
-- Всё пишется в UE4SS.log (рядом с игрой: Stalker2/Binaries/Win64/**/UE4SS.log)
-- и в окно консоли UE4SS. После нажатия F8 в игре — пришли мне строки [LootHelper].

local UEHelpers = require("UEHelpers")

local function log(msg)
    print("[LootHelper] " .. tostring(msg) .. "\n")
end

log("Загружен. Зайди в игру (не в меню), открой инвентарь и нажми F8.")

-- Догадки по именам «инвентарных» классов. Мы их НЕ знаем точно — просто пробуем,
-- вдруг повезёт. Настоящие имена возьмём из Live View (см. README).
local GUESS_CLASSES = {
    "Inventory", "InventoryComponent", "InventoryManagerComponent",
    "ItemContainer", "ItemsContainer", "ObjPrototypeInventory",
    "PlayerInventory", "EquipmentComponent",
}

local function safe(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    log("  (ошибка: " .. tostring(res) .. ")")
    return nil
end

local function isValid(o)
    return o ~= nil and safe(function() return o:IsValid() end) == true
end

local function scan()
    log("---- F8: скан ----")

    local pc = safe(function() return UEHelpers:GetPlayerController() end)
    if not isValid(pc) then
        log("PlayerController не найден. Ты точно в игре (загружен сейв), а не в меню?")
        return
    end
    log("PlayerController: " .. safe(function() return pc:GetClass():GetFullName() end))

    local pawn = safe(function() return pc.Pawn end)
    if isValid(pawn) then
        log("Pawn класс: " .. safe(function() return pawn:GetClass():GetFullName() end))
        log("Pawn объект: " .. safe(function() return pawn:GetFullName() end))
    else
        log("Pawn невалиден (возможно, идёт загрузка).")
    end

    -- Пробуем догадки: печатаем только те классы, что реально нашлись.
    local hits = 0
    for _, cn in ipairs(GUESS_CLASSES) do
        local obj = safe(function() return FindFirstOf(cn) end)
        if isValid(obj) then
            hits = hits + 1
            log("НАЙДЕН кандидат '" .. cn .. "' -> " .. safe(function() return obj:GetFullName() end))
        end
    end
    if hits == 0 then
        log("Из догадок ничего не нашлось — это ок, имена узнаем через Live View.")
    end

    log(">> Теперь: окно UE4SS -> вкладка Live View -> найди класс Pawn (см. выше),")
    log(">> разверни его и поищи компонент/поле со словом Inventory. Пришли мне имена.")
end

RegisterKeyBind(Key.F8, function()
    -- Работа с игровыми объектами — только в игровом потоке.
    ExecuteInGameThread(function()
        scan()
    end)
end)
