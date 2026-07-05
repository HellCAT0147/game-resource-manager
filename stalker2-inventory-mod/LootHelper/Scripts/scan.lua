-- LootHelper / scan.lua — перечитывается на каждый F9/F7 (см. main.lua).
-- Режим: _LOOT_MODE = "fast" (F9) | "deep" (F7).
--
-- HOVER-СКАНЕР. Рабочий канал чтения: тултип инвентаря, W_Text_C:GetText():ToString().
-- F9 = вкл/выкл запись. Пока запись включена, читаем тултип раз в 100 мс;
-- новые предметы копятся (дедуп) и пишутся в inventory_dump.json.
-- Кол-во в стаке: qty = вес_стака / вес_за_штуку (тултип даёт оба).
-- Износ < 100% дописывается к имени: «АКМ-74С [74%]».
--
-- Глобальные _LOOT_* переживают перезагрузку скрипта (dofile) — состояние не теряется.

local UEHelpers = require("UEHelpers")

local DUMP_PATH = "D:/Games/STALKER2/Stalker2/Binaries/Win64/ue4ss/Mods/LootHelper/inventory_dump.json"
-- Флаг «запись идёт» для внешней панели (REC-индикатор): при записи файл
-- освежается каждые ~2 с, при выключении удаляется. Панель гасит REC, если файл старше 5 с.
local FLAG_PATH = "D:/Games/STALKER2/Stalker2/Binaries/Win64/ue4ss/Mods/LootHelper/recording.flag"

local function touchFlag()
    local f = io.open(FLAG_PATH, "w")
    if f then f:write(tostring(os.time())) f:close() end
end

local function log(msg)
    print("[LootHelper] " .. tostring(msg) .. "\n")
end

local function safe(fn)
    local ok, r = pcall(fn)
    if ok then return r end
    return nil
end

local function isValid(o)
    return o ~= nil and safe(function() return o:IsValid() end) == true
end

local function unwrap(v)
    if v == nil then return nil end
    local ok, got = pcall(function() return v:get() end)
    if ok and got ~= nil then return got end
    return v
end

-- «0.4 кг» / «(0.4 кг)» / «65» -> число (запятая тоже понимается).
local function pnum(s)
    s = tostring(s or ""):gsub(",", ".")
    return tonumber(string.match(s, "([%d%.]+)"))
end

-- Текст из GSC-виджета W_Text_C: единственный рабочий путь — GetText():ToString().
local function wtext(owner, field)
    local w = unwrap(safe(function() return owner[field] end))
    if not isValid(w) then return nil end
    local s = safe(function() return w:GetText():ToString() end)
    if s == nil or s == "" then return nil end
    return tostring(s)
end

-- Видим ли виджет: скрытые поля тултипа хранят ПРОТУХШИЕ значения (баг с [93%] у еды).
local function isShown(owner, field)
    local w = unwrap(safe(function() return owner[field] end))
    if not isValid(w) then return false end
    return safe(function() return w:IsVisible() end) == true
end

-- ================= Состояние сессии записи (живёт между dofile) =================
_LOOT_ITEMS = _LOOT_ITEMS or {}          -- key -> {name, price, weight, qty}
_LOOT_COUNT = _LOOT_COUNT or 0
_LOOT_POLL = _LOOT_POLL or false
_LOOT_LOOP_STARTED = _LOOT_LOOP_STARTED or false

-- После рестарта игры подхватываем прошлый дамп: оверлей полный без пересканирования.
-- Формат файла наш собственный (см. writeDump) — парсим строки паттерном.
local function loadDump()
    local f = io.open(DUMP_PATH, "r")
    if not f then return end
    local n = 0
    for line in f:lines() do
        local name, price, weight, qty = string.match(line,
            '"name": "(.-)", "price": ([%d%.]+), "weight": ([%d%.]+), "qty": (%d+)')
        if name then
            name = name:gsub('\\"', '"'):gsub("\\\\", "\\")
            local key = name .. "|" .. price .. "|" .. weight
            if not _LOOT_ITEMS[key] then
                _LOOT_ITEMS[key] = {
                    name = name,
                    price = tonumber(price) or 0,
                    weight = tonumber(weight) or 0,
                    qty = tonumber(qty) or 1,
                    gear = string.find(line, '"gear": true', 1, true) ~= nil,
                }
                n = n + 1
            end
        end
    end
    f:close()
    if n > 0 then
        _LOOT_COUNT = _LOOT_COUNT + n
        log("Подхватил прошлый дамп: " .. n .. " поз.")
    end
end

if _LOOT_COUNT == 0 then
    safe(loadDump)
end


-- ================= Чтение наведённого предмета из тултипа =================
-- FindFirstOf — полный скан таблицы объектов, дорого для 4 раз/сек: кэшируем.
_LOOT_INV = _LOOT_INV or nil
local function getInventoryWidget()
    if isValid(_LOOT_INV) then return _LOOT_INV end
    _LOOT_INV = safe(function() return FindFirstOf("W_Inventory_C") end)
    return _LOOT_INV
end

local function readHovered()
    local inv = getInventoryWidget()
    if not isValid(inv) then return nil end
    local tt = unwrap(safe(function() return inv.ItemTooltip end))
    if not isValid(tt) then return nil end

    local name = wtext(tt, "HeaderText")
    if not name then return nil end

    local price = pnum(wtext(tt, "Price"))
    local wTotal = pnum(wtext(tt, "Weight"))
    local wOne = pnum(wtext(tt, "OneItemWeight"))
    if not price or not wTotal then return nil end

    local unitW = wOne or wTotal
    local qty = 1
    if wOne and wOne > 0 then
        qty = math.max(1, math.floor(wTotal / wOne + 0.5))
    end

    -- Видимый блок прочности = снаряжение (оружие/броня) — панель фильтрует по этому флагу.
    local gear = isShown(tt, "DurabilityOverlay")

    -- Износ: только у снаряжения (у скрытого блока — протухшее значение), и не «100%».
    -- Пишем в имя — различает стволы разного состояния.
    if gear and isShown(tt, "DurabilityPercentText") then
        local dur = wtext(tt, "DurabilityPercentText")
        if dur and dur ~= "100%" then
            name = name .. " [" .. dur .. "]"
        end
    end

    return { name = name, price = price, weight = unitW, qty = qty, gear = gear }
end

-- ================= Экспорт в JSON для приложения =================
local function jesc(s)
    return tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function writeDump()
    local keys = {}
    for k in pairs(_LOOT_ITEMS) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local it = _LOOT_ITEMS[k]
        parts[#parts + 1] = string.format(
            '    { "name": "%s", "price": %s, "weight": %s, "qty": %d, "gear": %s }',
            jesc(it.name), tostring(it.price), tostring(it.weight), it.qty,
            tostring(it.gear == true))
    end
    local f = io.open(DUMP_PATH, "w")
    if not f then
        log("НЕ МОГУ записать " .. DUMP_PATH)
        return
    end
    f:write('{\n  "source": "stalker2-hover-scan",\n  "items": [\n')
    f:write(table.concat(parts, ",\n"))
    f:write("\n  ]\n}\n")
    f:close()
end

-- ================= ОВЕРЛЕЙ: панель ₽/кг поверх игры (UMG, без ImGui) =================
_OVERLAY = _OVERLAY or nil
_OVERLAY_ON = _OVERLAY_ON or false

-- FText из строки. ВАЖНО: конструктор FText(s) ЗАПРЕЩЁН — сигнатура FText::FText(FString&&)
-- не найдена PS-сканом на 1.9, вызов = прыжок по нулевому указателю = краш игры.
-- FText берём ТОЛЬКО из возвращаемых значений игровых UFUNCTION (это направление работает).
local function makeText(s)
    local candidates = {
        "/Script/Engine.Default__KismetTextLibrary",
        "/Script/UMG.Default__KismetTextLibrary",
    }
    for _, p in ipairs(candidates) do
        local ktl = safe(function() return StaticFindObject(p) end)
        if isValid(ktl) then
            local ok, t = pcall(function() return ktl:Conv_StringToText(s) end)
            if ok and t ~= nil then return t end
            log("makeText: " .. p .. " есть, но Conv_StringToText не сработал: " .. tostring(t))
        else
            log("makeText: CDO не найден: " .. p)
        end
    end
    -- Фолбэк: класс -> CDO вручную.
    local cls = safe(function() return StaticFindObject("/Script/Engine.KismetTextLibrary") end)
    if isValid(cls) then
        local cdo = safe(function() return cls:GetCDO() end)
        if isValid(cdo) then
            local ok, t = pcall(function() return cdo:Conv_StringToText(s) end)
            if ok and t ~= nil then return t end
            log("makeText: GetCDO путь тоже не сработал: " .. tostring(t))
        else
            log("makeText: класс есть, GetCDO не дал объект")
        end
    else
        log("makeText: класс KismetTextLibrary не найден вовсе")
    end
    return nil
end

-- Создаём текстовый виджет игры и вешаем на экран.
local function ensureOverlay()
    if isValid(_OVERLAY) then return _OVERLAY end
    local wbl = safe(function() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    local cls = safe(function() return StaticFindObject("/Game/GameLite/FPS_Game/UIRemaster/CommonWidgets/W_Text.W_Text_C") end)
    local pc = safe(function() return UEHelpers:GetPlayerController() end)
    if not isValid(wbl) then log("оверлей: нет WidgetBlueprintLibrary") return nil end
    if not isValid(cls) then log("оверлей: нет класса W_Text_C") return nil end
    if not isValid(pc) then log("оверлей: нет PlayerController") return nil end
    local w = safe(function() return wbl:Create(pc, cls, pc) end)
    if not isValid(w) then log("оверлей: Create не сработал") return nil end
    safe(function() w:AddToViewport(1000) end)
    _OVERLAY = w
    return w
end

-- Пишем текст: сначала собственный SetText виджета, иначе — внутренний TextBlock.
local function setOverlayText(s)
    -- Сначала текст, потом виджет: не создаём виджет, если текст не из чего делать,
    -- и не оставляем «голый» GSC-виджет на экране (подозрение на краш отрисовки).
    local ft = makeText(s)
    if ft == nil then
        log("оверлей: не могу сделать FText — виджет не создаю")
        if isValid(_OVERLAY) then safe(function() _OVERLAY:RemoveFromParent() end) end
        _OVERLAY = nil
        return false
    end
    local w = ensureOverlay()
    if not w then return false end
    if safe(function() w:SetText(ft) return true end) then return true end
    -- Фолбэк: ищем TextBlock внутри дерева виджета.
    local tree = unwrap(safe(function() return w.WidgetTree end))
    local root = isValid(tree) and unwrap(safe(function() return tree.RootWidget end)) or nil
    if isValid(root) then
        if safe(function() root:SetText(ft) return true end) then return true end
    end
    log("оверлей: SetText не нашёлся (виджет: " .. tostring(safe(function() return w:GetFullName() end)) .. ")")
    return false
end

local function densityOf(it)
    if it.weight and it.weight > 0 then return it.price / it.weight end
    return math.huge
end

-- Текст панели: топ по ₽/кг + итоги.
local function buildOverlayText()
    local list = {}
    for _, it in pairs(_LOOT_ITEMS) do list[#list + 1] = it end
    table.sort(list, function(a, b) return densityOf(a) > densityOf(b) end)
    local lines = { "== ВЫГОДНЫЙ ХАБАР · ₽/кг ==" }
    local totalV, totalW = 0, 0
    for i, it in ipairs(list) do
        totalV = totalV + it.price * it.qty
        totalW = totalW + it.weight * it.qty
        if i <= 14 then
            local d = densityOf(it)
            local ds = (d == math.huge) and "∞" or tostring(math.floor(d + 0.5))
            local q = (it.qty > 1) and (" x" .. it.qty) or ""
            lines[#lines + 1] = ds .. "  —  " .. it.name .. q
        end
    end
    if #list > 14 then lines[#lines + 1] = "… ещё " .. (#list - 14) .. " поз." end
    if #list == 0 then lines[#lines + 1] = "(пусто: включи запись F9 и наведи на предметы)" end
    lines[#lines + 1] = string.format("Итого: %d поз · ₽%d · %.1f кг", #list, totalV, totalW)
    return table.concat(lines, "\n")
end

local function refreshOverlay()
    if _OVERLAY_ON then setOverlayText(buildOverlayText()) end
end

local function toggleOverlay()
    if _OVERLAY_ON then
        _OVERLAY_ON = false
        if isValid(_OVERLAY) then safe(function() _OVERLAY:RemoveFromParent() end) end
        _OVERLAY = nil
        log("Оверлей скрыт.")
    else
        _OVERLAY_ON = true
        if setOverlayText(buildOverlayText()) then
            log("Оверлей показан (обновляется при скане новых предметов).")
        else
            _OVERLAY_ON = false
            log("Оверлей не удалось показать — смотри строки выше, буду чинить.")
        end
    end
end

-- ================= Тик записи (в игровом потоке) =================
-- ВРЕМЕННАЯ диагностика: кто из durability-виджетов реально прячется на еде.
local DUR_FIELDS = { "DurabilityOverlay", "DurabilityRetainerBox", "Durability", "DurabilityBackground", "DurabilityPercentText", "DurabilityText", "WeightBox", "ItemStatValueBox" }
local function debugVisibility()
    local inv = getInventoryWidget()
    if not isValid(inv) then return end
    local tt = unwrap(safe(function() return inv.ItemTooltip end))
    if not isValid(tt) then return end
    local parts = {}
    for _, f in ipairs(DUR_FIELDS) do
        local w = unwrap(safe(function() return tt[f] end))
        local vis = "nil"
        if isValid(w) then
            local iv = safe(function() return w:IsVisible() end)
            local gv = safe(function() return w:GetVisibility() end)
            vis = tostring(iv) .. "/" .. tostring(gv)
        end
        parts[#parts + 1] = f .. "=" .. vis
    end
    log("VIS: " .. table.concat(parts, "  "))
end

local function recordTick()
    if not _LOOT_POLL then return end
    -- Держим REC-флаг свежим для панели (каждые ~20 тиков ≈ 2 с).
    _LOOT_TICKN = (_LOOT_TICKN or 0) + 1
    if _LOOT_TICKN % 20 == 1 then touchFlag() end
    -- Ускоряем тултип (float-запись, безопасно): свайп по сетке вместо ожидания на каждом.
    if not _LOOT_FASTTIP then
        local inv = getInventoryWidget()
        if isValid(inv) then
            local old = safe(function() return inv.ItemTooltipShowDelay end)
            safe(function() inv.ItemTooltipShowDelay = 0.02 end)
            _LOOT_FASTTIP = true
            log("Тултип ускорен: " .. tostring(old) .. " -> 0.02")
        end
    end
    local rec = safe(readHovered)
    if not rec then return end
    local key = rec.name .. "|" .. tostring(rec.price) .. "|" .. tostring(rec.weight)
    local old = _LOOT_ITEMS[key]
    if old == nil then
        _LOOT_ITEMS[key] = rec
        _LOOT_COUNT = _LOOT_COUNT + 1
        log(string.format("+ «%s»  ₽%s  %s кг  x%d   (итого: %d)",
            rec.name, tostring(rec.price), tostring(rec.weight), rec.qty, _LOOT_COUNT))
        writeDump()
        refreshOverlay()
    elseif old.qty ~= rec.qty then
        -- Тот же предмет, но стак изменился (или навели на другой стак) — берём больший.
        if rec.qty > old.qty then
            old.qty = rec.qty
            log(string.format("~ «%s» кол-во -> x%d", rec.name, rec.qty))
            writeDump()
            refreshOverlay()
        end
    end
end

-- Тик публикуется в глобаль: работающий LoopAsync всегда зовёт СВЕЖУЮ версию
-- (урок зомби-цикла: замыкание переживает dofile и держит старый код).
_LOOT_TICK = recordTick

-- ================= F9: вкл/выкл запись =================
local function fastScan()
    _LOOT_POLL = not _LOOT_POLL
    if _LOOT_POLL then
        -- Каждое включение — новый снимок инвентаря с нуля.
        _LOOT_ITEMS = {}
        _LOOT_COUNT = 0
        touchFlag()
        log("=== ЗАПИСЬ ВКЛ (список очищен) ===")
        log("Веди курсором по предметам инвентаря (жди тултип на каждом).")
        log("Повторный F9 — стоп. Файл: " .. DUMP_PATH)
        if not _LOOT_LOOP_STARTED then
            _LOOT_LOOP_STARTED = true
            -- 100 мс: поспевать за автосвайпом панели (курсор ~120 мс на ячейку).
            LoopAsync(100, function()
                ExecuteInGameThread(function()
                    local ok, err = pcall(function() _LOOT_TICK() end)
                    if not ok then log("tick error: " .. tostring(err)) end
                end)
                return false -- false = продолжать цикл
            end)
        end
    else
        pcall(os.remove, FLAG_PATH)
        log("=== ЗАПИСЬ ВЫКЛ === собрано предметов: " .. _LOOT_COUNT)
        log("Файл: " .. DUMP_PATH)
        writeDump()
    end
end

-- ================= F7: глубокий обход всех UObject (разведка, без изменений) =================
local KEYWORDS = { "invent", "item", "stash", "contain", "equip", "weapon", "loot", "trade", "money", "price", "cost", "weight", "count", "sid", "prototype" }
local function interesting(s)
    s = string.lower(tostring(s))
    for _, k in ipairs(KEYWORDS) do
        if string.find(s, k, 1, true) then return true end
    end
    return false
end

local function deepScan()
    log("---- F7: глубокий обход UObject (жди, игра может замереть) ----")
    local seen = {}
    safe(function()
        ForEachUObject(function(obj)
            pcall(function()
                local cname = obj:GetClass():GetFName():ToString()
                if interesting(cname) then
                    local rec = seen[cname]
                    if not rec then
                        rec = { count = 0, ex = {} }
                        seen[cname] = rec
                    end
                    rec.count = rec.count + 1
                    if #rec.ex < 2 then
                        rec.ex[#rec.ex + 1] = tostring(obj:GetFullName())
                    end
                end
            end)
        end)
    end)
    local list = {}
    for k, v in pairs(seen) do list[#list + 1] = { k, v.count, v.ex } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    log("Классов с ключевыми словами: " .. #list)
    for i, kv in ipairs(list) do
        if i > 250 then log("... (обрезано на 250)") break end
        log(string.format("CLASS x%-5d %s", kv[2], kv[1]))
        for _, e in ipairs(kv[3]) do
            log("        например: " .. e)
        end
    end
    log("---- конец F7 ----")
end

-- ================= F7: ХУК-СНИФФЕР =================
-- Статически параметры функций не видны (билд не отдаёт), но в момент вызова —
-- видны: RegisterHook даёт аргументы живьём. Ищем, в каком виде UI получает
-- ДАННЫЕ ПРЕДМЕТА: узнаем класс — считаем весь инвентарь через FindAllOf.
_SNIFF_ARMED = _SNIFF_ARMED or false
_SNIFF_SEEN = _SNIFF_SEEN or {}

local SNIFF_TARGETS = {
    "/Script/Stalker2.InventoryNew:ShowTooltip",
    "/Script/Stalker2.WidgetBase:UpdateWidget",
    "/Script/Stalker2.CustomGrid:SetCurrentCellDelayed",
    "/Script/Stalker2.CustomGrid:SetTargetCellDelayed",
    "/Script/Stalker2.InventoryNew:UIInventoryItemAction",
}

local function describeArg(v)
    local u = unwrap(v)
    if u == nil then return "nil" end
    local cls = safe(function() return u:GetClass():GetFName():ToString() end)
    if cls then
        return cls .. " | " .. tostring(safe(function() return u:GetFullName() end))
    end
    return type(u) .. " | " .. tostring(u)
end

local function armSniffer()
    if _SNIFF_ARMED then
        log("Сниффер уже взведён — наводи мышку на предметы, смотри лог.")
        return
    end
    _SNIFF_ARMED = true
    for _, path in ipairs(SNIFF_TARGETS) do
        local short = string.match(path, ":(%w+)$") or path
        local ok, err = pcall(function()
            RegisterHook("Function " .. path, function(ctx, p1, p2, p3)
                -- Логируем только первые 8 срабатываний каждой функции — иначе спам.
                local c = (_SNIFF_SEEN[short] or 0) + 1
                _SNIFF_SEEN[short] = c
                if c > 8 then return end
                log("HOOK " .. short .. " #" .. c)
                log("  ctx: " .. describeArg(ctx))
                if p1 ~= nil then log("  p1:  " .. describeArg(p1)) end
                if p2 ~= nil then log("  p2:  " .. describeArg(p2)) end
                if p3 ~= nil then log("  p3:  " .. describeArg(p3)) end
            end)
        end)
        if ok then
            log("ХУК ВЗВЕДЁН: " .. short)
        else
            log("хук не встал (" .. short .. "): " .. tostring(err))
        end
    end
    log(">>> Теперь: открой инвентарь и наведи мышку на 2-3 предмета. Потом зови Клода.")
end

-- ================= F7: перепись нативных ФУНКЦИЙ GSC =================
-- Квестовые BP зовут нативные геттеры/гиверы предметов — такие функции
-- вызываемы из Lua напрямую (без хуков). Ищем их по именам.
local FN_KEYWORDS = { "item", "invent", "money", "weight", "cost", "price", "count", "stash", "contain", "sid", "loot", "backpack" }
local function fnInteresting(s)
    s = string.lower(tostring(s))
    for _, k in ipairs(FN_KEYWORDS) do
        if string.find(s, k, 1, true) then return true end
    end
    return false
end

local function functionCensus()
    log("---- F7: перепись функций /Script/Stalker2 (жди) ----")
    local names = {}
    safe(function()
        ForEachUObject(function(obj)
            pcall(function()
                if obj:GetClass():GetFName():ToString() == "Function" then
                    local full = tostring(obj:GetFullName())
                    -- только нативные сталкерские и только с ключевыми словами
                    if string.find(full, "/Script/Stalker2.", 1, true) and fnInteresting(full) then
                        names[#names + 1] = string.gsub(full, "^Function /Script/Stalker2%.", "")
                    end
                end
            end)
        end)
    end)
    table.sort(names)
    log("Функций с ключевыми словами: " .. #names)
    for i, n in ipairs(names) do
        if i > 400 then log("... (обрезано на 400)") break end
        log("  FN " .. n)
    end
    log("---- конец переписи функций ----")
end

if _LOOT_MODE == "deep" then
    -- F7: топ-10 ₽/кг в лог (запасной просмотр без панели).
    -- История разведки полного автосъёма — в README («кровью написано») и в git-истории:
    -- хуки на нативные функции не срабатывают (вызовы мимо ProcessEvent),
    -- CppMediator (квестовый мост) умеет считать предметы только по SID —
    -- перечислителя инвентаря у GSC нет. Плато: hover-свайп остаётся способом.
    local list = {}
    for _, it in pairs(_LOOT_ITEMS) do list[#list + 1] = it end
    table.sort(list, function(a, b) return densityOf(a) > densityOf(b) end)
    log("=== ТОП ₽/кг ===")
    for i, it in ipairs(list) do
        if i > 10 then break end
        local d = densityOf(it)
        local ds = (d == math.huge) and "∞" or tostring(math.floor(d + 0.5))
        log(string.format("%2d. %s — %s ₽/кг%s", i, it.name, ds, it.qty > 1 and (" x" .. it.qty) or ""))
    end
    log("Всего позиций: " .. #list)
else
    fastScan()
end
