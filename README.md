<div align="center">

<img src="docs/app.png" width="84" alt="WarpScout">
<h1>WarpScout для macOS</h1>
<p>Нативный клиент для поиска рабочих серверов Cloudflare® WARP® на Apple Silicon и Intel.</p>
<p>
  <a href="https://github.com/HattabbI4/warpscout-gui-macos/releases/latest"><img src="https://img.shields.io/github/v/release/HattabbI4/warpscout-gui-macos?style=flat-square" alt="Release"></a>
  <a href="https://github.com/HattabbI4/warpscout-gui-macos/releases"><img src="https://img.shields.io/github/downloads/HattabbI4/warpscout-gui-macos/total?style=flat-square" alt="Downloads"></a>
  <a href="https://github.com/HattabbI4/warpscout-gui-macos/actions/workflows/ci.yaml"><img src="https://img.shields.io/github/actions/workflow/status/HattabbI4/warpscout-gui-macos/ci.yaml?style=flat-square&amp;label=CI" alt="CI"></a>
  <a href="#установка"><img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat-square" alt="macOS 26+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT"></a>
</p>
<p><strong>Русский</strong> · <a href="README_EN.md">English</a></p>

</div>

## Установка

1. Скачайте ZIP для своего Mac: **[Apple Silicon](https://github.com/HattabbI4/warpscout-gui-macos/releases/latest/download/WarpScout-macOS-arm64.zip)** или **[Intel](https://github.com/HattabbI4/warpscout-gui-macos/releases/latest/download/WarpScout-macOS-x86_64.zip)**. Требуется macOS 26 или новее. Тип процессора указан в меню  → «Об этом Mac».
2. Распакуйте ZIP, перенесите **WarpScout.app** в «Программы» и откройте его оттуда.
3. Если macOS не может проверить разработчика, откройте **Первый запуск — Start Here.html** рядом с приложением. Там есть ссылка на нужный раздел системных настроек и [инструкция Apple](https://support.apple.com/ru-ru/102445). Сборка имеет локальную подпись ad-hoc и не прошла нотарификацию Apple.

При первой установке выберите архив для своего Mac. При последующих обновлениях WarpScout выбирает архитектуру автоматически.

При первом запуске приложение автоматически скачает ядро для вашего процессора из [последнего стабильного релиза warpscout](https://github.com/vernette/warpscout/releases/latest), проверит размер, SHA-256 и версию и установит его в `~/Library/Application Support/WarpScout/warpscout`. Для первой установки нужен интернет. При сбое откройте «Настройки» и нажмите «Загрузить ядро» или выберите локальный исполняемый файл. При следующем запуске используется установленная копия. При первом поиске ядро зарегистрирует устройство WARP. В стандартном режиме включён фильтр DME. Если поиск пуст, а вам подходят московские узлы, выключите «Исключить узел» и повторите поиск. Для версии ядра 0.17.0 см. [результаты проверки безопасности](docs/release-readiness.md).

## Возможности

- **Сканер.** AmneziaWG, AmneziaWG 3.1, WireGuard, MASQUE (QUIC) и MASQUE H2 (TCP). Можно исключить узлы, измерить задержку и потери в туннеле, проверить подсети целиком и замерить скорость.
- **Расширенный режим.** Введите аргументы `warpscout scan`, следите за прогрессом и логом. Для AWG 3.1 доступны padding и параметры рукопожатия.
- **Серверы.** Результаты появляются во время поиска. Скопируйте адрес нажатием, экспортируйте профиль `.conf` или `.json` либо запустите локальный SOCKS5 на `127.0.0.1:1080`. Работу прокси можно контролировать из строки меню.
- **Настройки.** Выбор и обновление ядра, регистрация или пересоздание ключа устройства, русский и английский интерфейс. Оболочка проверяет подпись Ed25519 при установке обновления и при откате.

## Скриншоты

| Сканер | Расширенный сканер |
| :---: | :---: |
| [![Сканер](docs/screenshots/scanner-ru.png)](docs/screenshots/scanner-ru.png) | [![Расширенный сканер](docs/screenshots/advanced-ru.png)](docs/screenshots/advanced-ru.png) |

| Рабочие серверы | Настройки |
| :---: | :---: |
| [![Рабочие серверы](docs/screenshots/servers-ru.png)](docs/screenshots/servers-ru.png) | [![Настройки](docs/screenshots/settings-ru.png)](docs/screenshots/settings-ru.png) |

На снимках — демонстрационные адреса и результаты.

## Сборка и тесты

Для сборки нужны macOS 26+ и Xcode или Command Line Tools с macOS SDK 26+. Для тестов релизных скриптов нужны Python 3 и OpenSSL 3 или новее в `PATH`. Сборка создаёт отдельные архивы arm64 и x86_64 и не требует скачивания ядра.

```sh
git clone https://github.com/HattabbI4/warpscout-gui-macos.git
cd warpscout-gui-macos
./scripts/build.sh
open dist/WarpScout.app
```

```sh
./scripts/test.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
```

Тесты используют временную копию исходников и одноразовый ключ подписи. Для проверки окна приложения нужен графический сеанс. Дополнительный запуск `WARPSCOUT_LIVE_TEST=1 ./scripts/test.sh` регистрирует отдельное устройство у Cloudflare и проверяет пять протоколов в вашей сети. Файл тестового аккаунта удаляется по завершении.

## Данные и обратная связь

Аккаунт и последний результат находятся в `~/Library/Application Support/WarpScout/`. Файл аккаунта и экспортированные профили содержат закрытые ключи. К сообщению об ошибке достаточно приложить версии оболочки, ядра, macOS и шаги воспроизведения на тестовых данных. [Issues](https://github.com/HattabbI4/warpscout-gui-macos/issues) · [Закрытое сообщение об уязвимости](SECURITY.md) · [Как выпустить релиз](docs/releases.md)

## Лицензия и авторы

Автор — **HattabbI4**. Код оболочки распространяется по [MIT](LICENSE). Интерфейс адаптирован из [WarpScout GUI для Windows](https://github.com/HattabbI4/warpscout-gui), для сканирования используется [vernette/warpscout](https://github.com/vernette/warpscout). У ядра [отдельная лицензия](https://github.com/vernette/warpscout/blob/master/LICENSE).

WarpScout — независимый проект. Cloudflare и WARP — товарные знаки Cloudflare, Inc.
