'use strict';

/* ============ Константы ============ */
const STORAGE_KEY = 's2-resource-tracker:v1';
const STATUSES = [
  { id: 'out', label: 'Нет',        order: 0 },
  { id: 'low', label: 'Мало',       order: 1 },
  { id: 'mid', label: 'Средне',     order: 2 },
  { id: 'ok',  label: 'Достаточно', order: 3 },
];
const STATUS_ORDER = Object.fromEntries(STATUSES.map(s => [s.id, s.order]));

/* ============ Состояние ============ */
let resources = [];
let activeTab = 'trip';
const sortByTab = { trip: 'urgency', catalog: 'name' }; // у каждой вкладки своя сортировка
let editingId = null;        // id редактируемого ресурса (null = новый)
let pendingImage = undefined; // undefined = не трогали, null = убрать, string = новая base64

/* ============ Хранилище ============ */
function uid() {
  return 'r' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      resources = JSON.parse(raw);
      syncSeed();   // подмешать новые ресурсы и иконки из обновлённого каталога
      return;
    }
  } catch (e) { console.warn('Ошибка чтения хранилища', e); }
  seedCatalog();
}

// Догоняет сохранённый каталог до актуального seed.js, не трогая статусы и
// пользовательские правки: добавляет новые ресурсы по имени и подставляет
// иконки тем, у кого их ещё не было. Удалённые вручную ресурсы вернутся.
function syncSeed() {
  const seed = window.SEED_RESOURCES || [];
  const byName = new Map(resources.map(r => [r.name, r]));
  let changed = false;
  for (const s of seed) {
    const existing = byName.get(s.name);
    if (!existing) {
      resources.push({ id: uid(), name: s.name, icon: s.icon || '📦', img: s.img || null, image: null, status: 'ok' });
      changed = true;
    } else if (existing.img == null && s.img) {
      existing.img = s.img;   // подлечить иконку, если её не было
      changed = true;
    }
  }
  if (changed) save();
}

function seedCatalog() {
  resources = (window.SEED_RESOURCES || []).map(r => ({
    id: uid(),
    name: r.name,
    icon: r.icon || '📦',
    img: r.img || null,    // игровая иконка из комплекта
    image: null,           // фото, загруженное пользователем
    status: 'ok',
  }));
  save();
}

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(resources));
  } catch (e) {
    alert('Не удалось сохранить — возможно, переполнено хранилище браузера (слишком много фото).');
    console.error(e);
  }
}

/* ============ Рендер ============ */
const el = id => document.getElementById(id);

function statusOf(id) { return STATUSES.find(s => s.id === id) || STATUSES[3]; }

function matchesSearch(r, q) {
  return !q || r.name.toLowerCase().includes(q);
}

function sortResources(list, mode) {
  const byName = (a, b) => a.name.localeCompare(b.name, 'ru');
  if (mode === 'name') return list.sort(byName);
  if (mode === 'status-desc') return list.sort((a, b) => STATUS_ORDER[b.status] - STATUS_ORDER[a.status] || byName(a, b));
  // urgency (по умолчанию): out -> low -> mid -> ok
  return list.sort((a, b) => STATUS_ORDER[a.status] - STATUS_ORDER[b.status] || byName(a, b));
}

function iconHTML(r) {
  const src = r.image || r.img;   // фото пользователя важнее игровой иконки
  return src ? `<img src="${src}" alt="" />` : (r.icon || '📦');
}

function cardHTML(r) {
  const seg = STATUSES.map(s =>
    `<button data-s="${s.id}" class="${r.status === s.id ? 'active' : ''}" aria-label="${s.label}">${s.label}</button>`
  ).join('');
  return `
    <li class="card" data-id="${r.id}" data-status="${r.status}">
      <div class="card-icon" data-act="edit">${iconHTML(r)}</div>
      <div class="card-body">
        <div class="card-name" data-act="edit">${escapeHTML(r.name)}<span class="edit-hint">✎</span></div>
        <div class="seg">${seg}</div>
      </div>
    </li>`;
}

function escapeHTML(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function render() {
  const q = el('search').value.trim().toLowerCase();
  const tripItems = sortResources(resources.filter(r => r.status !== 'ok' && matchesSearch(r, q)), sortByTab.trip);
  const catalogItems = sortResources(resources.filter(r => matchesSearch(r, q)), sortByTab.catalog);

  // Счётчик вылазки (всегда полный, без учёта поиска)
  const tripTotal = resources.filter(r => r.status !== 'ok').length;
  const badge = el('trip-count');
  badge.textContent = tripTotal;
  badge.dataset.empty = tripTotal === 0;

  el('view-trip').hidden = activeTab !== 'trip';
  el('view-catalog').hidden = activeTab !== 'catalog';

  el('trip-list').innerHTML = tripItems.map(cardHTML).join('');
  el('catalog-list').innerHTML = catalogItems.map(cardHTML).join('');
  el('trip-empty').hidden = !(activeTab === 'trip' && tripItems.length === 0);
}

/* ============ Действия с карточками ============ */
function onListClick(e) {
  const card = e.target.closest('.card');
  if (!card) return;
  const r = resources.find(x => x.id === card.dataset.id);
  if (!r) return;

  const segBtn = e.target.closest('.seg button');
  if (segBtn) {
    r.status = segBtn.dataset.s;
    save();
    render();
    return;
  }
  if (e.target.closest('[data-act="edit"]')) {
    openEditor(r);
  }
}

/* ============ Редактор ============ */
function buildStatusPicker() {
  el('f-status').innerHTML = STATUSES.map(s =>
    `<button type="button" data-s="${s.id}">${s.label}</button>`
  ).join('');
}

function setPickerStatus(status) {
  document.querySelectorAll('#f-status button').forEach(b =>
    b.classList.toggle('active', b.dataset.s === status));
}

function currentPickerStatus() {
  const active = document.querySelector('#f-status button.active');
  return active ? active.dataset.s : 'out';
}

function openEditor(r) {
  editingId = r ? r.id : null;
  pendingImage = undefined;
  el('modal-title').textContent = r ? 'Редактировать' : 'Новый ресурс';
  el('f-name').value = r ? r.name : '';
  el('f-icon').value = r ? r.icon : '';
  setPickerStatus(r ? r.status : 'out');
  updateImagePreview(r ? (r.image || r.img) : null, r ? r.icon : '');
  el('delete-btn').hidden = !r;
  el('modal').hidden = false;
  if (!r) setTimeout(() => el('f-name').focus(), 50);
}

function closeEditor() {
  el('modal').hidden = true;
  editingId = null;
  el('f-image').value = '';
}

function updateImagePreview(image, icon) {
  const box = el('img-preview');
  if (image) {
    box.innerHTML = `<img src="${image}" alt="" />`;
    el('clear-image').hidden = false;
  } else {
    box.textContent = icon || el('f-icon').value || '📦';
    el('clear-image').hidden = true;
  }
}

function effectiveImage(r) {
  if (pendingImage === undefined) return r ? r.image : null;
  return pendingImage; // null или base64
}

function saveEditor() {
  const name = el('f-name').value.trim();
  if (!name) { el('f-name').focus(); return; }
  const icon = el('f-icon').value.trim() || '📦';
  const status = currentPickerStatus();

  if (editingId) {
    const r = resources.find(x => x.id === editingId);
    r.name = name;
    r.icon = icon;
    r.status = status;
    if (pendingImage !== undefined) r.image = pendingImage;
  } else {
    resources.push({
      id: uid(), name, icon, status,
      image: pendingImage === undefined ? null : pendingImage,
    });
  }
  save();
  render();
  closeEditor();
}

function deleteCurrent() {
  if (!editingId) return;
  if (!confirm('Удалить ресурс из каталога?')) return;
  resources = resources.filter(r => r.id !== editingId);
  save();
  render();
  closeEditor();
}

/* ============ Загрузка и сжатие изображения ============ */
function handleImageFile(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => compressImage(reader.result, 256, dataUrl => {
    pendingImage = dataUrl;
    updateImagePreview(dataUrl, '');
  });
  reader.readAsDataURL(file);
}

function compressImage(src, maxSize, cb) {
  const img = new Image();
  img.onload = () => {
    let { width, height } = img;
    const scale = Math.min(1, maxSize / Math.max(width, height));
    width = Math.round(width * scale);
    height = Math.round(height * scale);
    const canvas = document.createElement('canvas');
    canvas.width = width; canvas.height = height;
    canvas.getContext('2d').drawImage(img, 0, 0, width, height);
    cb(canvas.toDataURL('image/jpeg', 0.8));
  };
  img.onerror = () => cb(src);
  img.src = src;
}

/* ============ Меню / импорт-экспорт ============ */
function exportData() {
  const blob = new Blob([JSON.stringify(resources, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 's2-resources-backup.json';
  a.click();
  URL.revokeObjectURL(url);
}

function importData(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      if (!Array.isArray(data)) throw new Error('bad format');
      resources = data.map(r => ({
        id: r.id || uid(),
        name: String(r.name || 'Без названия'),
        icon: r.icon || '📦',
        img: r.img || null,
        image: r.image || null,
        status: STATUS_ORDER[r.status] !== undefined ? r.status : 'ok',
      }));
      save();
      render();
      closeMenu();
      alert('Импортировано: ' + resources.length + ' ресурсов.');
    } catch (e) {
      alert('Не удалось прочитать файл резервной копии.');
    }
  };
  reader.readAsText(file);
}

function resetAllToOk() {
  if (!confirm('Сбросить состояние всех ресурсов в «Достаточно»? Список вылазки очистится.')) return;
  resources.forEach(r => r.status = 'ok');
  save();
  render();
  closeMenu();
}

function wipeToFactory() {
  if (!confirm('Удалить все изменения и вернуть заводской каталог? Это необратимо.')) return;
  localStorage.removeItem(STORAGE_KEY);
  seedCatalog();
  render();
  closeMenu();
}

function closeMenu() { el('menu').hidden = true; }

/* ============ Привязка событий ============ */
function bind() {
  document.querySelectorAll('.tab').forEach(t =>
    t.addEventListener('click', () => {
      activeTab = t.dataset.tab;
      document.querySelectorAll('.tab').forEach(x => x.classList.toggle('is-active', x === t));
      el('sort').value = sortByTab[activeTab]; // показать сортировку активной вкладки
      render();
    }));

  el('search').addEventListener('input', render);
  el('sort').addEventListener('change', () => {
    sortByTab[activeTab] = el('sort').value; // запомнить выбор именно для этой вкладки
    render();
  });
  el('sort').value = sortByTab[activeTab];

  el('trip-list').addEventListener('click', onListClick);
  el('catalog-list').addEventListener('click', onListClick);

  el('fab-add').addEventListener('click', () => openEditor(null));

  // Редактор
  el('save-btn').addEventListener('click', saveEditor);
  el('cancel-btn').addEventListener('click', closeEditor);
  el('delete-btn').addEventListener('click', deleteCurrent);
  el('f-status').addEventListener('click', e => {
    const b = e.target.closest('button');
    if (b) setPickerStatus(b.dataset.s);
  });
  el('f-icon').addEventListener('input', () => {
    if (effectiveImage(resources.find(r => r.id === editingId)) == null) {
      updateImagePreview(null, el('f-icon').value);
    }
  });
  el('pick-image').addEventListener('click', () => el('f-image').click());
  el('f-image').addEventListener('change', e => handleImageFile(e.target.files[0]));
  el('clear-image').addEventListener('click', () => {
    pendingImage = null;
    updateImagePreview(null, el('f-icon').value);
  });

  // Закрытие модалок по клику на фон
  el('modal').addEventListener('click', e => { if (e.target === el('modal')) closeEditor(); });
  el('menu').addEventListener('click', e => { if (e.target === el('menu')) closeMenu(); });

  // Меню
  el('menu-btn').addEventListener('click', () => el('menu').hidden = false);
  el('menu-close').addEventListener('click', closeMenu);
  el('update-btn').addEventListener('click', forceUpdate);
  el('reset-all').addEventListener('click', resetAllToOk);
  el('export-btn').addEventListener('click', exportData);
  el('import-btn').addEventListener('click', () => el('import-file').click());
  el('import-file').addEventListener('change', e => { if (e.target.files[0]) importData(e.target.files[0]); });
  el('wipe-btn').addEventListener('click', wipeToFactory);
}

/* ============ Старт ============ */
buildStatusPicker();
load();
bind();
render();

// Регистрация service worker (офлайн).
// Если страница уже под управлением SW, при появлении новой версии
// (controllerchange) перезагружаемся один раз — чтобы подхватить свежий код.
if ('serviceWorker' in navigator) {
  let refreshing = false;
  if (navigator.serviceWorker.controller) {
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (refreshing) return;
      refreshing = true;
      location.reload();
    });
  }
  window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
}

// Ручной сброс: снять SW, очистить кэши и перезагрузиться (надёжно на мобиле).
async function forceUpdate() {
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map(r => r.unregister()));
    }
    if (window.caches) {
      const keys = await caches.keys();
      await Promise.all(keys.map(k => caches.delete(k)));
    }
  } catch (e) { /* игнор */ }
  location.reload();
}
