# iTgLegacy

Читать на других языках: [English](README.md)

Клиент Telegram для старых устройств iOS: на TDLib внутри, с интерфейсом Telegram
для iOS образца 2013 года снаружи.

Это форк [bla1r1/iTgLegacy](https://github.com/bla1r1/iTgLegacy), который, в свою
очередь, происходит от работы Игоря В. Семенцова ([@igkuzm](https://github.com/igkuzm)).

## Чем этот форк отличается

Апстрим сделал клиент, который запускается на старом железе. Здесь к этому добавлена
вторая цель: интерфейс должен быть тем самым, который на этих устройствах и был.

- **Интерфейс 2013 года, снятый с оригинального исходника.** Раскладка, метрики,
  графика и поведение взяты из настоящего до-редизайнового Telegram для iOS. Заметки
  по разбору лежат в [`docs/original-study/`](docs/original-study/).
- **Современная функциональность внутри** — папки, реакции, истории, избранное,
  опросы, премиум, секретные чаты, стикеры, видеосообщения, звонки.
- **Эмодзи, которых нет в системе.** Символы, добавленные в Unicode после iOS 6,
  рисуются из встроенного атласа через CoreText: системный шрифт на 6.1.3
  заканчивается на Unicode 6.0.
- **iPad** — раздельная раскладка: список слева, переписка справа.

## Поддерживаемые устройства и архитектуры

Проект собирает как облегченные отдельные `.ipa` пакеты для каждой архитектуры, так и универсальный двойной бинарник:

- **armv7 (32-бит, ~8.8 МБ)**: Для устройств с iOS 6.0+ (iPhone 3GS, iPhone 4, iPhone 4S, iPhone 5, iPad 2/3/4, iPod Touch 4/5).
- **arm64 (64-бит, ~8.8 МБ)**: Для устройств с iOS 7.0 - 12.5.7 (iPhone 5s — iPhone X, iPad Air/Pro).
- **Универсальный (~16 МБ)**: Единый файл `iTgLegacy.ipa`, содержащий обе архитектуры.

## Настройка ключей Telegram API

Перед сборкой приложения для реального использования настройте ключи Telegram API:

1. Скопируйте шаблон [`include/tg_config.h.example`](include/tg_config.h.example) в `include/tg_config.h`:
   ```bash
   cp include/tg_config.h.example include/tg_config.h
   ```
2. Зарегистрируйте приложение на https://my.telegram.org (в разделе *API development tools*).
3. Вкажите свои `TG_API_ID` и `TG_API_HASH` в созданном файле `include/tg_config.h`:

```c
#define TG_API_ID   ВАШ_API_ID
#define TG_API_HASH "ВАШ_API_HASH"
```

> Примечание: файл `include/tg_config.h` добавлен в `.gitignore`, чтобы личные ключи никогда случайно не попали в репозиторий.

## Структура репозитория

```
iTgLegacy/
├── Makefile       # Главный файл сборки
├── README.md      # Документация (на английском)
├── README_RU.md   # Документация (на русском)
├── LICENSE        # Лицензия GPLv3
├── src/           # Исходные файлы Objective-C
├── tdlib/         # Telegram Database Library (git submodule)
├── include/       # Заголовочные файлы C и tg_config.h.example
├── images/        # Иконки и ресурсы приложения
├── scripts/       # Скрипты автоматизации сборки
└── build/         # Результаты сборки (git-ignored)
    ├── iTgLegacy-armv7.ipa # 32-битный IPA для iOS 6.0+ (8.8 МБ)
    ├── iTgLegacy-arm64.ipa # 64-битный IPA для iOS 7.0-12.5.7 (8.8 МБ)
    └── iTgLegacy.ipa       # Универсальный IPA файл (16 МБ)
```

## Требования для сборки

Для сборки iTgLegacy на macOS необходимо:

1. Установленный Xcode с поддержкой iOS SDK.
2. Зависимости для сборки:
   ```bash
   brew install cmake gperf openssl@1.1 ccache
   ```

## Сборка

Склонируйте репозиторий вместе с подмодулями и запустите `make`:

```bash
git clone --recursive https://github.com/a-havrysh/iTgLegacy.git
cd iTgLegacy
make
```

Или запустите скрипт сборки:

```bash
./scripts/build_ipa.sh
```

### Команды Makefile

- `make ipa` - Собрать все пакеты (`iTgLegacy-armv7.ipa`, `iTgLegacy-arm64.ipa` и универсальный `iTgLegacy.ipa`).
- `make ipa-armv7` - Собрать облегченный 32-битный `.ipa` (8.8 МБ для iOS 6.0+).
- `make ipa-arm64` - Собрать облегченный 64-битный `.ipa` (8.8 МБ для iOS 7.0 - 12.5.7).
- `make app` - Собрать только пакет `.app`.
- `make deps` - Подготовить статические библиотеки третьих сторон в `build/libs`.
- `make tdlib` - Скомпилировать TDLib для iOS.
- `make clean` - Удалить все промежуточные файлы из директории `build/`.

## Авторы и мейнтейнеры

- **Оригинальный автор и создатель**: Игорь В. Семенцов ([@igkuzm](https://github.com/igkuzm))
- **Апстрим**: [bla1r1/iTgLegacy](https://github.com/bla1r1/iTgLegacy)
- **Этот форк**: [a-havrysh/iTgLegacy](https://github.com/a-havrysh/iTgLegacy)

## Отказ от ответственности

Программа предоставляется в образовательных целях и для сохранения старого оборудования. Используйте на свой страх и риск.
