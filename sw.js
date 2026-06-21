// Service worker — кэш оболочки приложения для офлайн-работы.
const CACHE = 's2-resources-v8';
const ASSETS = [
  './',
  './index.html',
  './subnautica.html',
  './stalker.html',
  './styles.css',
  './launcher.js',
  './app.js',
  './seed.js',
  './stalker.js',
  './manifest.webmanifest',
  './icon.svg',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Network-first для своих файлов: онлайн — всегда свежее (и обновляем кэш),
// офлайн — отдаём из кэша. Так новые деплои подхватываются сразу.
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  if (new URL(e.request.url).origin !== self.location.origin) return; // сторонние не трогаем
  e.respondWith(
    fetch(e.request).then(resp => {
      if (resp && resp.status === 200 && resp.type === 'basic') {
        const copy = resp.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy));
      }
      return resp;
    }).catch(() => caches.match(e.request))
  );
});
