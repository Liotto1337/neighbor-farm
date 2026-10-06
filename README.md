# Neighbor Farm

Уютная ферма с асинхронным кооперативом. Godot 4.3, GDScript, портрет 720x1280, цель — Yandex Games (Web + Android).

## Запуск
1. Откройте `project.godot` в Godot 4.3 и нажмите F5.
2. Отладочные клавиши: **F10** — перемотать время на +60 с, **F9** — выдать монеты и опыт.
3. Сохранение: `user://save.json`. Удалите файл, чтобы начать заново.

## Экспорт
Web / Android (рендерер GL Compatibility). В пресете экспорта добавьте `data/*.json` в «Фильтры для экспорта не-ресурсных файлов».

## Структура
- `autoload/` — Signals, GameState, SaveManager, TimeService, Economy, NeighborAI, IAP (заглушка), AdManager (заглушка), UiFx (анимации интерфейса), Audio (эмбиент, птицы, звуки; глушит звук при сворачивании и рекламе)
- `data/` — весь баланс в JSON. Размер поля по уровням — `config.json` → `field_sizes` (4×4 на старте, 10×10 на 15 уровне), тайминги анимаций — `config.json` → `anim`
- `scenes/` — Main + 5 вкладок, компоненты (Tile, Modal, ContractRow)
- `audio/` — звуки и эмбиент, сгенерированы `tools/make_audio.py` (`python3 tools/make_audio.py`; с модулями `numpy` + `soundfile` эмбиент пишется в OGG). Громкости — `config.json` → `audio`. Переключатели музыки и звуков — внизу вкладки «Магазин».
