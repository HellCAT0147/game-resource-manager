'use strict';

/* ============================================================
   S.T.A.L.K.E.R. 2 — «Выгодный хабар»
   Помогает по цене и весу решить, что нести торговцу, а что бросить.
   Никаких стартовых данных (без спойлеров): всё добавляется вручную.
   Главная метрика — выгодность = цена / вес (₽ за кг).
   Список разделён на группы по категориям.
   Данные и грузоподъёмность хранятся в localStorage; есть импорт/экспорт.
   ============================================================ */

/* ============ Категории (порядок = порядок групп в списке) ============ */
const CATEGORIES = [
  { id: 'food',     label: 'Еда',         icon: '🥫' },
  { id: 'pistol',   label: 'Пистолет',    icon: '🔫' },
  { id: 'rifle',    label: 'Автомат',     icon: '🪖' },
  { id: 'shotgun',  label: 'Дробовик',    icon: '💥' },
  { id: 'ammo',     label: 'Патроны',     icon: '🧨' },
  { id: 'armor',    label: 'Броня',       icon: '🛡️' },
  { id: 'other',    label: 'Другое',      icon: '📦' },
  { id: 'artifact', label: 'Артефакт',    icon: '🔮' },
  { id: 'grenade',  label: 'Граната',     icon: '💣' },
  { id: 'meds',     label: 'Медикаменты', icon: '💊' },
  { id: 'antirad',  label: 'Антирад',     icon: '☢️' },
];
const CAT_BY_ID = Object.fromEntries(CATEGORIES.map(c => [c.id, c]));
const DEFAULT_CAT = 'other';

/* ============ Хранилище ============ */
const STORAGE_KEY = 'stalker2-resource-tracker:v1';

/* ============ Состояние ============ */
let items = [];
let budget = 0;                 // грузоподъёмность, кг (0 = не задано)
let sortMode = 'value';         // value | price | weight | name
let editingId = null;

/* ============ Утилиты ============ */
const el = id => document.getElementById(id);

function uid() {
  return 'i' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

function density(it) {
  // ₽ за кг. Невесомое (вес ≤ 0) считаем «бесконечно выгодным».
  return it.weight > 0 ? it.price / it.weight : Infinity;
}

function num(v, fallback = 0) {
  const n = parseFloat(String(v).replace(',', '.'));
  return Number.isFinite(n) ? n : fallback;
}

function fmt(n) {
  if (!Number.isFinite(n)) return '∞';
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function escapeHTML(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/* ============ Загрузка / сохранение ============ */
function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const data = JSON.parse(raw);
      items = normalizeItems(Array.isArray(data) ? data : data.items);
      budget = num(Array.isArray(data) ? 0 : data.budget, 0);
    }
  } catch (e) { console.warn('Ошибка чтения хранилища', e); }
}

function normalizeItems(arr) {
  if (!Array.isArray(arr)) return [];
  return arr.map(r => ({
    id: r.id || uid(),
    name: String(r.name || 'Без названия'),
    price: Math.max(0, num(r.price, 0)),
    weight: Math.max(0, num(r.weight, 0)),
    qty: Math.max(0, Math.round(num(r.qty, 1))), // 0 = кончилось (позиция остаётся шаблоном)
    category: CAT_BY_ID[r.category] ? r.category : DEFAULT_CAT,
  }));
}

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ version: 1, budget, items }));
  } catch (e) {
    alert('Не удалось сохранить — возможно, переполнено хранилище браузера.');
    console.error(e);
  }
}

/* ============ Расчёты ============ */
// Тир выгодности (цветовая метка) относительно всего хабара:
// нижняя треть — «копейки» (low), середина — mid, верх — выгодное (good).
function densityTiers() {
  const sorted = [...items].sort((a, b) => density(a) - density(b)); // по возрастанию
  const n = sorted.length;
  const tier = new Map();
  sorted.forEach((it, i) => {
    const frac = n <= 1 ? 1 : i / (n - 1);   // 0 = самое невыгодное, 1 = самое выгодное
    tier.set(it.id, frac >= 0.66 ? 'good' : frac >= 0.33 ? 'mid' : 'low');
  });
  return tier;
}

// Жадный набор под грузоподъёмность: берём самое выгодное по ₽/кг,
// частичными стопками, пока не кончится свободный вес. Сквозной по всем категориям.
function computeCarry() {
  if (!(budget > 0)) return null;
  const ranked = [...items].sort((a, b) => density(b) - density(a)); // выгодные первыми
  let remaining = budget;
  let totalValue = 0, totalWeight = 0, totalUnits = 0;
  const take = new Map();
  for (const it of ranked) {
    let units;
    if (it.weight <= 0) units = it.qty;                          // невесомое — берём всё
    else units = Math.min(it.qty, Math.floor(remaining / it.weight + 1e-9));
    if (units > 0) {
      take.set(it.id, units);
      totalValue += units * it.price;
      totalWeight += units * it.weight;
      totalUnits += units;
      remaining -= units * it.weight;
    }
  }
  return { take, totalValue, totalWeight, totalUnits };
}

/* ============ Рендер ============ */
function matchesSearch(it, q) {
  return !q || it.name.toLowerCase().includes(q);
}

function sortItems(list) {
  const byName = (a, b) => a.name.localeCompare(b.name, 'ru');
  if (sortMode === 'name') return list.sort(byName);
  if (sortMode === 'price') return list.sort((a, b) => b.price * b.qty - a.price * a.qty || byName(a, b));
  if (sortMode === 'weight') return list.sort((a, b) => b.weight * b.qty - a.weight * a.qty || byName(a, b));
  // value (по умолчанию): по выгодности ₽/кг
  return list.sort((a, b) => density(b) - density(a) || byName(a, b));
}

function groupHeadHTML(cat, count, value, weight) {
  return `
    <li class="group-head">
      <span class="group-title">${cat.icon} ${cat.label}</span>
      <span class="group-sum">${count} · ₽ ${fmt(value)} · ⚖️ ${fmt(weight)} кг</span>
    </li>`;
}

function cardHTML(it, tier, takeUnits) {
  const dens = density(it);
  const meta = `₽ ${fmt(it.price)} · ⚖️ ${fmt(it.weight)} кг`; // кол-во теперь живёт в степпере справа

  let takeBadge = '', takeAttr = '';
  if (takeUnits !== null) {
    if (takeUnits <= 0) {
      takeAttr = ' data-take="none"';
      takeBadge = `<span class="take-badge none">Оставить</span>`;
    } else if (takeUnits >= it.qty) {
      takeAttr = ' data-take="full"';
      takeBadge = `<span class="take-badge full">Нести${it.qty > 1 ? ' ×' + it.qty : ''}</span>`;
    } else {
      takeAttr = ' data-take="part"';
      takeBadge = `<span class="take-badge part">Нести ${takeUnits}/${it.qty}</span>`;
    }
  }

  const cls = 'card item-card' + (it.qty === 0 ? ' is-empty' : '');
  // На нуле кнопка «−» превращается в «убрать» — чтобы кончившийся расходник убирался без модалки.
  const downBtn = it.qty === 0
    ? `<button class="qty-btn remove" data-act="remove" type="button" aria-label="Убрать из списка">✕</button>`
    : `<button class="qty-btn" data-act="dec" type="button" aria-label="Убавить один">−</button>`;

  return `
    <li class="${cls}" data-id="${it.id}" data-tier="${tier}"${takeAttr}>
      <div class="item-dens" data-act="edit"><b>${fmt(dens)}</b><span>₽/кг</span></div>
      <div class="card-body" data-act="edit">
        <div class="card-name">${escapeHTML(it.name)}<span class="edit-hint">✎</span></div>
        <div class="item-meta">${meta}</div>
        ${takeBadge}
      </div>
      <div class="qty-ctl" data-act="qty">
        <button class="qty-btn" data-act="inc" type="button" aria-label="Прибавить один">+</button>
        <b class="qty-val" data-act="delta" title="Ввести число">×${it.qty}</b>
        ${downBtn}
      </div>
    </li>`;
}

function render() {
  const q = el('search').value.trim().toLowerCase();
  const carry = computeCarry();
  const tiers = densityTiers();
  const filtered = items.filter(it => matchesSearch(it, q));

  let html = '';
  for (const cat of CATEGORIES) {
    const group = sortItems(filtered.filter(it => it.category === cat.id));
    if (!group.length) continue;
    const gValue = group.reduce((s, it) => s + it.price * it.qty, 0);
    const gWeight = group.reduce((s, it) => s + it.weight * it.qty, 0);
    html += groupHeadHTML(cat, group.length, gValue, gWeight);
    html += group.map(it =>
      cardHTML(it, tiers.get(it.id) || 'mid', carry ? (carry.take.get(it.id) || 0) : null)
    ).join('');
  }
  el('list').innerHTML = html;

  // Пустые состояния
  const hasItems = items.length > 0;
  el('empty').hidden = hasItems;
  el('empty-search').hidden = !(hasItems && filtered.length === 0);

  // Сводка по всему хабару
  const totalValue = items.reduce((s, it) => s + it.price * it.qty, 0);
  const totalWeight = items.reduce((s, it) => s + it.weight * it.qty, 0);
  el('stats').innerHTML = hasItems
    ? `Всего: <b>${items.length}</b> поз · ₽ ${fmt(totalValue)} · ⚖️ ${fmt(totalWeight)} кг`
    : '';

  renderCarrySummary(carry);
}

function renderCarrySummary(carry) {
  const box = el('carry-summary');
  if (!carry) { box.hidden = true; return; }
  box.hidden = false;
  const leftWeight = Math.max(0, budget - carry.totalWeight);
  box.innerHTML =
    `Нести: <b>${carry.totalUnits}</b> шт · ₽ <b>${fmt(carry.totalValue)}</b> · ` +
    `⚖️ ${fmt(carry.totalWeight)} / ${fmt(budget)} кг` +
    (leftWeight > 0.05 ? ` <span class="muted">(свободно ${fmt(leftWeight)})</span>` : '');
}

/* ============ Редактор ============ */
function buildCategoryPicker() {
  el('f-category').innerHTML = CATEGORIES.map(c =>
    `<button type="button" data-c="${c.id}"><span>${c.icon}</span>${c.label}</button>`
  ).join('');
}

function setPickerCategory(id) {
  document.querySelectorAll('#f-category button').forEach(b =>
    b.classList.toggle('active', b.dataset.c === id));
}

function currentPickerCategory() {
  const a = document.querySelector('#f-category button.active');
  return a ? a.dataset.c : DEFAULT_CAT;
}

function updateCatHint(cat) {
  const box = el('f-cathint');
  if (cat === 'ammo') {
    box.hidden = false;
    box.textContent = 'Патроны в S.T.A.L.K.E.R. 2 считаются поштучно: цену и вес указывай за 1 патрон, а в «Кол-во» — число патронов.';
  } else {
    box.hidden = true;
    box.textContent = '';
  }
}

function liveDensity() {
  const price = Math.max(0, num(el('f-price').value, 0));
  const weight = Math.max(0, num(el('f-weight').value, 0));
  if (weight > 0) {
    el('f-density').textContent = `Выгодность: ${fmt(price / weight)} ₽/кг`;
  } else {
    el('f-density').textContent = price > 0 ? 'Укажи вес больше 0' : '';
  }
}

function openEditor(it) {
  editingId = it ? it.id : null;
  el('modal-title').textContent = it ? 'Редактировать' : 'Новый предмет';
  el('f-name').value = it ? it.name : '';
  el('f-price').value = it ? it.price : '';
  el('f-weight').value = it ? it.weight : '';
  el('f-qty').value = it ? it.qty : 1;
  const cat = it ? it.category : DEFAULT_CAT;
  setPickerCategory(cat);
  updateCatHint(cat);
  el('delete-btn').hidden = !it;
  liveDensity();
  el('modal').hidden = false;
  if (!it) setTimeout(() => el('f-name').focus(), 50);
}

function closeEditor() {
  el('modal').hidden = true;
  editingId = null;
}

function saveEditor() {
  const name = el('f-name').value.trim();
  if (!name) { el('f-name').focus(); return; }
  const price = Math.max(0, num(el('f-price').value, 0));
  const weight = Math.max(0, num(el('f-weight').value, 0));
  if (!(weight > 0)) { alert('Укажи вес больше 0 — без веса не посчитать выгодность.'); el('f-weight').focus(); return; }
  const qty = Math.max(0, Math.round(num(el('f-qty').value, 1)));
  const category = currentPickerCategory();

  if (editingId) {
    const it = items.find(x => x.id === editingId);
    Object.assign(it, { name, price, weight, qty, category });
  } else {
    items.push({ id: uid(), name, price, weight, qty, category });
  }
  save();
  render();
  closeEditor();
}

function deleteCurrent() {
  if (!editingId) return;
  if (!confirm('Удалить предмет из списка?')) return;
  items = items.filter(it => it.id !== editingId);
  save();
  render();
  closeEditor();
}

/* ============ Взаимодействие с карточкой ============ */
// Тап по имени/цене/выгодности — редактор; степпер −/×N/+ меняет количество на месте.
function onListClick(e) {
  const card = e.target.closest('.item-card');
  if (!card) return;
  const id = card.dataset.id;
  const act = e.target.closest('[data-act]')?.dataset.act || null;

  if (act === 'inc' || act === 'dec' || act === 'qty') return; // степпер — через pointer / буфер промаха
  if (act === 'remove') { removeItem(id); return; }
  if (act === 'delta')  { openDeltaModal(id); return; }

  const it = items.find(x => x.id === id);
  if (it) openEditor(it);
}

function removeItem(id) {
  const it = items.find(x => x.id === id);
  if (!it) return;
  if (!confirm(`Убрать «${it.name}» из списка?`)) return;
  items = items.filter(x => x.id !== id);
  save();
  render();
}

/* ---- Инлайн-изменение количества (степпер + автоповтор на удержании) ---- */
function haptic() { try { navigator.vibrate?.(8); } catch (_) {} }

// Меняет qty и обновляет ТОЛЬКО число на карточке (дёшево, без пересборки списка).
// Полный render() с пересчётом сумм/выгодности/сортировки — отложенно, по окончании серии (scheduleCommit).
function changeQty(id, delta, card) {
  const it = items.find(x => x.id === id);
  if (!it) return;
  const next = Math.max(0, it.qty + delta);
  if (next === it.qty) return;
  it.qty = next;
  const valEl = card && card.querySelector('.qty-val');
  if (valEl) valEl.textContent = '×' + it.qty;
  if (card) card.classList.toggle('is-empty', it.qty === 0);
  haptic();
}

// Отложенная запись+перерисовка: список не «прыгает» под пальцем во время серии,
// а после паузы приходит в корректный вид (суммы, сортировка, «убрать» на нуле).
let commitTimer = null;
function scheduleCommit() {
  clearTimeout(commitTimer);
  commitTimer = setTimeout(commit, 300);
}
function commit() {
  clearTimeout(commitTimer);
  commitTimer = null;
  save();
  render();
}
function flushCommit() { if (commitTimer) commit(); } // страховка при сворачивании PWA

let hold = null;
function startHold(e, btn) {
  const card = btn.closest('.item-card');
  if (!card) return;
  const dir = btn.dataset.act === 'inc' ? 1 : -1;
  changeQty(card.dataset.id, dir, card);            // первый шаг сразу
  hold = { id: card.dataset.id, dir, card, x: e.clientX, y: e.clientY, step: 1, ticks: 0 };
  hold.timer = setTimeout(() => {                    // затем автоповтор с ускорением
    hold.interval = setInterval(() => {
      hold.ticks++;
      hold.step = hold.ticks > 12 ? 10 : hold.ticks > 5 ? 5 : 1;
      changeQty(hold.id, hold.dir * hold.step, hold.card);
    }, 90);
  }, 350);
}
function moveHold(e) {                                // сдвиг пальца = это скролл, глушим автоповтор
  if (hold && (Math.abs(e.clientX - hold.x) > 12 || Math.abs(e.clientY - hold.y) > 12)) endHold();
}
function endHold() {
  if (!hold) return;
  clearTimeout(hold.timer);
  clearInterval(hold.interval);
  hold = null;
  scheduleCommit();
}
function onListPointerDown(e) {
  const btn = e.target.closest('[data-act="inc"],[data-act="dec"]');
  if (!btn) return;
  e.preventDefault();
  startHold(e, btn);
}

/* ---- Мини-ввод дельты (тап по числу): «−47 потратил / +12 нашёл» без полного редактора ---- */
let deltaId = null;
function openDeltaModal(id) {
  const it = items.find(x => x.id === id);
  if (!it) return;
  deltaId = id;
  el('delta-name').textContent = it.name;
  el('delta-input').value = '';
  el('modal-delta').hidden = false;
  setTimeout(() => el('delta-input').focus(), 50);
}
function closeDeltaModal() { el('modal-delta').hidden = true; deltaId = null; }
function applyDelta(sign) {
  const it = items.find(x => x.id === deltaId);
  if (it) {
    const v = Math.max(0, Math.round(num(el('delta-input').value, 0)));
    if (v > 0) {
      it.qty = Math.max(0, it.qty + sign * v);
      save();
      render();
    }
  }
  closeDeltaModal();
}

/* ============ Грузоподъёмность ============ */
function onBudgetInput() {
  budget = Math.max(0, num(el('budget').value, 0));
  save();
  render();
}

/* ============ Меню / импорт-экспорт ============ */
function exportData() {
  const blob = new Blob([JSON.stringify({ version: 1, budget, items }, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'stalker2-habar-backup.json';
  a.click();
  URL.revokeObjectURL(url);
}

function importData(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      items = normalizeItems(Array.isArray(data) ? data : data.items);
      budget = num(Array.isArray(data) ? budget : data.budget, budget);
      el('budget').value = budget || '';
      save();
      render();
      closeMenu();
      alert('Импортировано: ' + items.length + ' предметов.');
    } catch (e) {
      alert('Не удалось прочитать файл резервной копии.');
    }
  };
  reader.readAsText(file);
}

// Слияние из игрового дампа/скринов: обновляет по имени, добавляет новое, ничего не затирает.
function mergeImportData(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      const rawItems = Array.isArray(data) ? data : (data.items || []);
      if (!rawItems.length) { alert('В файле нет предметов для синка.'); return; }
      const byName = new Map(items.map(it => [it.name.trim().toLowerCase(), it]));
      let added = 0, updated = 0;
      for (const r of rawItems) {
        const name = String(r.name || '').trim();
        if (!name) continue;
        const price = Math.max(0, num(r.price, 0));
        const weight = Math.max(0, num(r.weight, 0));
        const qty = Math.max(0, Math.round(num(r.qty, 1)));
        const cat = CAT_BY_ID[r.category] ? r.category : null;
        const ex = byName.get(name.toLowerCase());
        if (ex) {
          ex.price = price; ex.weight = weight; ex.qty = qty;
          if (cat) ex.category = cat;
          updated++;
        } else {
          const it = { id: uid(), name, price, weight, qty, category: cat || DEFAULT_CAT };
          items.push(it);
          byName.set(name.toLowerCase(), it);
          added++;
        }
      }
      if (!Array.isArray(data) && data.budget != null) {
        budget = Math.max(0, num(data.budget, budget));
        el('budget').value = budget || '';
      }
      save();
      render();
      closeMenu();
      alert(`Синхронизировано из игры: добавлено ${added}, обновлено ${updated}.`);
    } catch (e) {
      alert('Не удалось прочитать файл синка.');
      console.error(e);
    }
  };
  reader.readAsText(file);
}

function wipeAll() {
  if (!confirm('Очистить весь список предметов? Это необратимо.')) return;
  items = [];
  save();
  render();
  closeMenu();
}

function closeMenu() { el('menu').hidden = true; }

/* ============ Привязка событий ============ */
function bind() {
  el('search').addEventListener('input', render);
  el('sort').addEventListener('change', () => { sortMode = el('sort').value; render(); });
  el('budget').addEventListener('input', onBudgetInput);

  el('list').addEventListener('click', onListClick);
  el('list').addEventListener('pointerdown', onListPointerDown);
  el('list').addEventListener('pointermove', moveHold);
  window.addEventListener('pointerup', endHold);
  window.addEventListener('pointercancel', endHold);
  el('fab-add').addEventListener('click', () => openEditor(null));

  // Редактор
  el('save-btn').addEventListener('click', saveEditor);
  el('cancel-btn').addEventListener('click', closeEditor);
  el('delete-btn').addEventListener('click', deleteCurrent);
  el('f-category').addEventListener('click', e => {
    const b = e.target.closest('button');
    if (b) { setPickerCategory(b.dataset.c); updateCatHint(b.dataset.c); }
  });
  el('f-price').addEventListener('input', liveDensity);
  el('f-weight').addEventListener('input', liveDensity);

  // Мини-ввод дельты
  el('delta-cancel').addEventListener('click', closeDeltaModal);
  el('delta-minus').addEventListener('click', () => applyDelta(-1));
  el('delta-plus').addEventListener('click', () => applyDelta(1));
  el('modal-delta').addEventListener('click', e => { if (e.target === el('modal-delta')) closeDeltaModal(); });

  // Не потерять отложенную запись при сворачивании/закрытии (PWA)
  document.addEventListener('visibilitychange', () => { if (document.hidden) flushCommit(); });
  window.addEventListener('pagehide', flushCommit);

  // Закрытие модалок по фону
  el('modal').addEventListener('click', e => { if (e.target === el('modal')) closeEditor(); });
  el('menu').addEventListener('click', e => { if (e.target === el('menu')) closeMenu(); });

  // Меню
  el('menu-btn').addEventListener('click', () => el('menu').hidden = false);
  el('menu-close').addEventListener('click', closeMenu);
  el('sync-btn').addEventListener('click', () => el('sync-file').click());
  el('sync-file').addEventListener('change', e => { if (e.target.files[0]) mergeImportData(e.target.files[0]); });
  el('export-btn').addEventListener('click', exportData);
  el('import-btn').addEventListener('click', () => el('import-file').click());
  el('import-file').addEventListener('change', e => { if (e.target.files[0]) importData(e.target.files[0]); });
  el('wipe-btn').addEventListener('click', wipeAll);
}

/* ============ Старт ============ */
buildCategoryPicker();
load();
el('budget').value = budget || '';
el('sort').value = sortMode;
bind();
render();
