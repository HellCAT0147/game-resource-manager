'use strict';

/* Лаунчер: экран выбора игры.
   Каждый запуск показывает выбор, но последняя открытая игра подсвечивается
   и помечается «Продолжить» — открыть её можно в один тап. */

const LAST_GAME_KEY = 'game-launcher:last';

function getLastGame() {
  try { return localStorage.getItem(LAST_GAME_KEY); }
  catch (e) { return null; }
}

function rememberGame(game) {
  try { localStorage.setItem(LAST_GAME_KEY, game); }
  catch (e) { /* приватный режим / переполнение — не критично */ }
}

function highlightLastGame() {
  const last = getLastGame();
  if (!last) return;
  const card = document.querySelector(`.game-card[data-game="${last}"]`);
  if (card) {
    card.classList.add('is-last');
    // Последняя игра — первой в списке, чтобы открыть в один тап.
    const li = card.closest('li');
    const list = li && li.parentElement;
    if (list && li !== list.firstElementChild) list.prepend(li);
  }
}

function bindCards() {
  document.querySelectorAll('.game-card').forEach(card =>
    card.addEventListener('click', () => rememberGame(card.dataset.game))
  );
}

highlightLastGame();
bindCards();
