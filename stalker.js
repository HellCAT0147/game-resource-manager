'use strict';

/* ============================================================
   S.T.A.L.K.E.R. 2 — «Выгодный хабар»
   Помогает по цене и весу решить, что нести торговцу, а что бросить.
   Никаких стартовых данных (без спойлеров): всё добавляется вручную.
   Главная метрика — выгодность = цена / вес (крб за кг).
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
  // крб за кг. Невесомое (вес ≤ 0) считаем «бесконечно выгодным».
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
    qty: Math.max(1, Math.round(num(r.qty, 1))),
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

// Жадный набор под грузоподъёмность: берём самое выгодное по крб/кг,
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
  // value (по умолчанию): по выгодности крб/кг
  return list.sort((a, b) => density(b) - density(a) || byName(a, b));
}

function groupHeadHTML(cat, count, value, weight) {
  return `
    <li class="group-head">
      <span class="group-title">${cat.icon} ${cat.label}</span>
      <span class="group-sum">${count} · 🪙 ${fmt(value)} · ⚖️ ${fmt(weight)} кг</span>
    </li>`;
}

function cardHTML(it, tier, takeUnits) {
  const dens = density(it);
  const meta = `🪙 ${fmt(it.price)} · ⚖️ ${fmt(it.weight)} кг` + (it.qty > 1 ? ` · ×${it.qty}` : '');

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

  return `
    <li class="card item-card" data-id="${it.id}" data-tier="${tier}"${takeAttr}>
      <div class="item-dens" data-act="edit"><b>${fmt(dens)}</b><span>крб/кг</span></div>
      <div class="card-body" data-act="edit">
        <div class="card-name">${escapeHTML(it.name)}<span class="edit-hint">✎</span></div>
        <div class="item-meta">${meta}</div>
      </div>
      ${takeBadge}
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
    ? `Всего: <b>${items.length}</b> поз · 🪙 ${fmt(totalValue)} · ⚖️ ${fmt(totalWeight)} кг`
    : '';

  renderCarrySummary(carry);
}

function renderCarrySummary(carry) {
  const box = el('carry-summary');
  if (!carry) { box.hidden = true; return; }
  box.hidden = false;
  const leftWeight = Math.max(0, budget - carry.totalWeight);
  box.innerHTML =
    `Нести: <b>${carry.totalUnits}</b> шт · 🪙 <b>${fmt(carry.totalValue)}</b> · ` +
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
    el('f-density').textContent = `Выгодность: ${fmt(price / weight)} крб/кг`;
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
  const qty = Math.max(1, Math.round(num(el('f-qty').value, 1)));
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

/* ============ Клик по карточке ============ */
function onListClick(e) {
  const card = e.target.closest('.card');
  if (!card) return;
  const it = items.find(x => x.id === card.dataset.id);
  if (it) openEditor(it);
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

  // Закрытие модалок по фону
  el('modal').addEventListener('click', e => { if (e.target === el('modal')) closeEditor(); });
  el('menu').addEventListener('click', e => { if (e.target === el('menu')) closeMenu(); });

  // Меню
  el('menu-btn').addEventListener('click', () => el('menu').hidden = false);
  el('menu-close').addEventListener('click', closeMenu);
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
