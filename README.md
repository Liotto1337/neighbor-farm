# Neighbor Farm

Уютная ферма с асинхронным кооперативом. Godot 4.3, GDScript, портрет 720x1280, цель — Yandex Games (Web + Android).

## Запуск
1. Откройте `project.godot` в Godot 4.3 и нажмите F5.
2. Отладочные клавиши: **F10** — перемотать время на +60 с, **F9** — выдать монеты и опыт.
3. Сохранение: `user://save.json`. Удалите файл, чтобы начать заново.

## Экспорт
Web / Android (рендерер GL Compatibility). В пресете экспорта добавьте `data/*.json` в «Фильтры для экспорта не-ресурсных файлов».

## Структура
- `autoload/` — Signals, GameState, SaveManager, TimeService, Economy, NeighborAI, IAP (заглушка), AdManager (заглушка)
- `data/` — весь баланс в JSON
- `scenes/` — Main + 5 вкладок, компоненты (Tile, Modal, ContractRow)
