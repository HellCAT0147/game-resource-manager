# 🎮 Game Resource Trackers

*Mobile-first PWA companion apps for survival games — track what you're short on, and decide what loot is actually worth carrying.*

**English** · [Русская версия ниже ↓](#-трекеры-ресурсов-игр)

A pick-a-game launcher opens one of two trackers, each storing its data locally in the browser (offline-first, no server, no account):

- **🌊 Subnautica 2** — a resource stock tracker: mark what's running low and auto-build a gathering list for your next run.
- **☢️ S.T.A.L.K.E.R. 2 — "Profitable Loot"** — ranks inventory by **value density (₽/kg)** and greedily computes the optimal "what to carry" set under a weight budget, so you stop hauling worthless junk.

### The standout: a live game → web inventory pipeline

The S.T.A.L.K.E.R. 2 tracker is backed by a genuinely novel bridge that reads your **real, live in-game inventory** (see [`stalker2-inventory-mod/`](stalker2-inventory-mod/)):

- A **UE4SS Lua mod** scrapes the in-game tooltip UI to capture every item's name, price, weight and stack count — necessary because the game's current v1.9 build defeats the usual engine-reflection modding APIs.
- An **always-on-top overlay panel** (PowerShell/WPF) ranks items in real time — *"drop these for the least money lost per kg freed"* — and can **auto-sweep the inventory grid with the mouse** so you don't hover items by hand.
- One keypress **syncs the snapshot into the PWA**.

Along the way the project documents hard-won, previously unpublished knowledge about modding S.T.A.L.K.E.R. 2 v1.9 (working signature setup, engine-reflection limits, crash pitfalls) that is directly reusable by the game's modding community. See the [mod README](stalker2-inventory-mod/README.md) for the technical write-up.

**Tech:** vanilla JS / HTML / CSS, no build step, `localStorage`, service-worker offline cache, Netlify deploy. Licensed under [MIT](LICENSE).

---

# 🎮 Трекеры ресурсов игр

Мобильное веб-приложение (PWA): отмечай на складе, каких ресурсов не хватает, и собирай список на вылазку.

При запуске открывается **экран выбора игры**:

- **🌊 Subnautica 2** — трекер собираемых ресурсов (ниже).
- **☢️ S.T.A.L.K.E.R. 2** — «Выгодный хабар»: по цене и весу подсказывает, что нести торговцу, а что бросить.

Каждая игра хранит данные отдельно в этом браузере. Последняя открытая игра подсвечивается на экране выбора и открывается в один тап; вернуться к выбору можно кнопкой «‹» в шапке (или «Сменить игру» в меню).

## Возможности
- **Каталог ресурсов** с иконками; предзаполнен. Можно добавлять/редактировать/удалять свои (название, эмодзи, фото с телефона).
- **4 состояния** запаса:
  - 🔴 **Нет** — закончился, набрать в первую очередь
  - 🟠 **Мало** — критично мало
  - 🟡 **Средне** — можно добрать, не срочно
  - 🟢 **Достаточно** — в список вылазки не попадает
- **Вкладка «Вылазка»** — только то, что не 🟢, отсортированное по срочности.
- **Сортировки**: по срочности / по названию / по статусу.
- **Поиск** по названию.
- **Фото ресурса** с телефона (сжимается и хранится в браузере).
- **Офлайн** (PWA) — можно «установить» на главный экран.
- **Резервная копия**: экспорт/импорт данных в JSON (меню «⋯»).

Все данные хранятся локально в браузере устройства (`localStorage`) — без сервера и регистрации.

## ☢️ S.T.A.L.K.E.R. 2 — «Выгодный хабар»
Помогает решить, что нести торговцу, а что бросить, по соотношению **цена/вес**.

- **Без спойлеров**: стартового каталога нет — все найденные предметы добавляешь вручную (название, цена в ₽, вес в кг, количество, категория).
- **Выгодность (₽/кг)** у каждого предмета на видном месте; цветовая метка показывает выгодное / среднее / «копейки».
- **Группы по категориям**: еда, пистолет, автомат, дробовик, патроны, броня, другое, артефакт, граната, медикаменты, антирад (пиво/водка/антирад — всё, что снимает радиацию).
- **Быстрое изменение количества** прямо в списке, без открытия карточки: степпер `[−] ×N [+]` (тап = ∓1, удержание = быстрый разгон для стопок патронов), тап по числу — ввод дельты «−потратил / +нашёл», а на нуле кнопка «−» превращается в «убрать». Позиция с нулём тускнеет, но остаётся шаблоном на следующую вылазку.
- **«Что нести»**: задаёшь свободную грузоподъёмность (кг) — приложение жадно по выгодности подбирает оптимальный набор (можно частью стопки) и помечает «Нести» / «Оставить», показывает суммарную ценность и вес.
- **Сортировка** по выгодности / цене / весу / названию, **поиск**, **экспорт/импорт** в JSON.

Данные STALKER хранятся отдельно от Subnautica (свой ключ `localStorage`).

## Запуск локально
Просто открой `index.html` в браузере. Для проверки PWA/Service Worker лучше через локальный сервер:
```bash
npx serve .
# или
python -m http.server 8080
```

## Деплой на Netlify (бесплатно)

### Вариант А — перетащить папку (самый быстрый)
1. Зайди на https://app.netlify.com/drop
2. Перетащи туда **папку проекта** целиком.
3. Готово — получишь ссылку вида `https://имя.netlify.app`. Открой её на телефоне.

### Вариант Б — из Git-репозитория (авто-обновление при пуше)
1. Запушь репозиторий на GitHub.
2. В Netlify: **Add new site → Import an existing project → GitHub**, выбери репозиторий.
3. Настройки сборки: **Build command** — пусто, **Publish directory** — `.` (уже задано в `netlify.toml`).
4. Deploy.

### Установка на телефон
Открой сайт в браузере → меню → «Добавить на главный экран» / «Установить приложение».

## Структура
| Файл | Назначение |
|------|------------|
| `index.html` | лаунчер — экран выбора игры |
| `launcher.js` | логика лаунчера (подсветка последней игры, запоминание выбора) |
| `subnautica.html` | приложение Subnautica 2 (разметка) |
| `app.js` | логика Subnautica 2: состояния, рендер, хранилище, импорт/экспорт |
| `seed.js` | стартовый каталог ресурсов Subnautica 2 |
| `stalker.html` | приложение S.T.A.L.K.E.R. 2 «Выгодный хабар» (разметка) |
| `stalker.js` | логика S.T.A.L.K.E.R. 2: выгодность ₽/кг, оптимизатор «что нести», категории, импорт/экспорт |
| `styles.css` | стили; темы игр через класс на `<body>` (`theme-launcher`/`theme-subnautica`/`theme-stalker`), мобильный first |
| `sw.js` | service worker (офлайн-кэш) |
| `manifest.webmanifest` | манифест PWA |
| `icon.svg` | иконка приложения |
| `netlify.toml` | конфиг деплоя |

> Каталог основан на известных материалах Subnautica; данные по Subnautica 2 (ранний доступ) могут быть неточны — всё редактируется прямо в приложении.
