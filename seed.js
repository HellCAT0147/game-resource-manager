// Стартовый каталог собираемых ресурсов Subnautica 2.
// Источник данных: cubiq.ru — гайд по ресурсам Subnautica 2 (ранний доступ).
// Иконки инвентаря: wikily.gg (скачаны локально в папку icons/).
// Здесь — то, что добывают на вылазке (минералы/руды, органика, ресурсы из обломков).
// img — игровая иконка (если есть), icon — эмодзи-запас, если иконки нет.
// status: 'out' (нет) | 'low' (мало) | 'mid' (средне) | 'ok' (достаточно)
const ICON = f => 'icons/' + f + '.webp';
window.SEED_RESOURCES = [
  // — Минералы и руды —
  { name: 'Титан',                       icon: '⚙️', img: ICON('T_Resource_Titanium_Icon') },
  { name: 'Медь',                        icon: '🟤', img: ICON('T_Resource_Copper_Icon') },
  { name: 'Кварц',                       icon: '🔷', img: ICON('T_Resource_Quartz_Icon') },
  { name: 'Соль',                        icon: '🧂', img: ICON('T_Resource_Salt_Icon') },
  { name: 'Серебро',                     icon: '🪙', img: ICON('T_Resource_Silver_Icon') },
  { name: 'Свинец',                      icon: '🔘', img: ICON('T_Resource_Lead_Icon') },
  { name: 'Золото',                      icon: '🥇', img: ICON('T_Resource_Gold_Icon') },
  { name: 'Сера',                        icon: '🟨', img: ICON('T_Resource_Sulfur_Icon') },
  { name: 'Литий',                       icon: '🔋', img: ICON('T_Resource_Lithium_02a_Icon') },
  { name: 'Атакамит',                    icon: '🟩', img: ICON('T_Resource_Atacamite_01a_Icon') },
  { name: 'Целестин',                    icon: '🔵', img: ICON('T_Resource_Celestine_01a_Icon') },
  { name: 'Проводящий кристалл',         icon: '💠', img: ICON('T_Resource_ConduitCrystal_Item_Temp_Icon') },
  { name: 'Троилит',                     icon: '🌑', img: ICON('T_Resource_Troilite_01a_Icon') },
  // — Растительные, коралловые и биологические —
  { name: 'Рейон',                       icon: '🟣', img: ICON('T_AcidAnemone_01a_Fruit_Icon') },
  { name: 'Мешочек с лечебной слизью',   icon: '💗', img: ICON('T_AcidAnemone_MedigelSac_Icon') },
  { name: 'Волокнистая мякоть',          icon: '🌿', img: ICON('T_FibrousPulp_Icon') },
  { name: 'Гнилушка светоносная',        icon: '🟠', img: ICON('T_LuciferRotsacBulb_Icon') },
  { name: 'Коралловая стружка',          icon: '🪸', img: ICON('T_CoralShavings_Icon') },
  { name: 'Циста некролеи',              icon: '🔮', img: null },
  { name: 'Аксумская колония бактерий',  icon: '🦠', img: ICON('T_Resource_AxumBioprintCulture_01a_Icon') },
  { name: 'Биологическая эмаль',         icon: '🦷', img: null },
  { name: 'Гнилушка-черимойя',           icon: '🍈', img: null },
  { name: 'Помёт краба',                 icon: '🦀', img: ICON('T_Resource_CrabFeces_Icon') },
  { name: 'Кладка яиц глубококрыла',     icon: '🥚', img: ICON('T_DeepwingEggTemp_Icon') },
  { name: 'Пента',                       icon: '🌱', img: ICON('T_Pent_Fruit_Icon') },
  // — Ресурсы из обломков —
  { name: 'Металлолом',                  icon: '🔧', img: ICON('T_MetalSalvage_Icon') },
  // — Еда и вода —
  { name: 'Вода',                        icon: '💧', img: ICON('T_WaterBottle_Icon') },
  { name: 'Рыба',                        icon: '🐟', img: ICON('T_Halfmoon_01a_Icon') },
];
