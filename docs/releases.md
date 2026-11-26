# Publishing a macOS release / Публикация релиза

## Настроить репозиторий

1. Включите GitHub Actions в `HattabbI4/warpscout-gui-macos`. Создайте environment `release-signing`, ограничьте его тегами `v*` и настройте защиту тегов. Назначьте проверяющего для доступа к секрету подписи, если релизы выпускает команда. Включите **Private vulnerability reporting**, чтобы работала ссылка в SECURITY.md.
2. Добавьте в environment секрет `WARPSCOUT_SIGNING_KEY_B64`: это 32 байта существующего закрытого ключа Ed25519, закодированные в Base64. Скрипт подписи проверяет совпадение с `Resources/UpdatePublicKey`. Пример передачи ключа напрямую в GitHub CLI без вывода значения в терминал:

   ```sh
   base64 -i "$HOME/.config/warpscout-release/signing.key" | gh secret set WARPSCOUT_SIGNING_KEY_B64 --env release-signing --repo HattabbI4/warpscout-gui-macos
   ```

   Храните резервную копию ключа у издателя. В CI тесты создают собственную временную пару ключей.
3. Для опциональной генерации примечаний добавьте `LLM_API_KEY` или `GEMINI_API_KEY` и при необходимости переменные `LLM_BASE_URL` (HTTPS) и `LLM_MODEL`. Без этих настроек доступны текст тега и список коммитов. При включении LLM провайдер получает сообщения коммитов и фрагмент diff между тегами.

[Проверка первого кандидата / Initial candidate assessment](release-readiness.md)

## Выпустить версию

По [правилам выпуска](../AGENTS.md) обновите `CFBundleShortVersionString` и увеличьте `CFBundleVersion` в `Resources/Info.plist`. Когда проверенный коммит попадёт в основную ветку и пользователь попросит выпустить релиз, создайте и отправьте аннотированный тег.

```sh
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Чтобы задать примечания вручную, добавьте в тело аннотированного тега блоки `<!-- changelog:ru --> … <!-- /changelog:ru -->` и `<!-- changelog:en --> … <!-- /changelog:en -->`. Генератор предпочитает тело тега, затем опциональный LLM, затем список коммитов.

При отправке тега `v*` workflow Release вызывает CI на Apple Silicon и Intel, сверяет тег с Info.plist, собирает ZIP для каждой архитектуры, подписывает оба и передаёт готовые архивы на Apple Silicon и Intel. Каждый раннер устанавливает свой подписанный ZIP в пустой профиль, проверяет открытие окна и запуск ядра, скачанного приложением с GitHub. Затем создаёт черновик GitHub Release, загружает `WarpScout-macOS-arm64.zip`, `WarpScout-macOS-x86_64.zip` и соответствующие файлы `.sig` и публикует их вместе. При повторе допускается продолжить черновик. Опубликованный релиз защищён от перезаписи workflow.

Перед публикацией Actions проверяет подпись каждого нового ZIP публичным ключом из приложения той же архитектуры в предыдущем стабильном релизе. Для первого выпуска ключ берётся из текущей сборки. Ошибка доступа к истории релизов, скачивания предыдущего ZIP или проверки подписи останавливает выпуск. Разделы GitHub с новыми участниками и ссылкой на полный список изменений добавляются на этапе публикации.

## English

Enable GitHub Actions and private vulnerability reporting. Configure the `release-signing` environment for protected `v*` tags. Put the Base64-encoded raw Ed25519 private key in its `WARPSCOUT_SIGNING_KEY_B64` secret using the command above. The signing tool checks the key against the public key pinned in the source tree. Keep a private backup. CI uses disposable keys.

Update the version and build number in `Resources/Info.plist`. Tag the tested commit with the matching `vX.Y.Z` annotated tag and push that tag to trigger publication. Release notes come from the tag body, the optional LLM, or the commit list, in that order. The optional provider receives commit messages and a source diff excerpt. Configure `LLM_API_KEY` or `GEMINI_API_KEY`, and optionally `LLM_BASE_URL` and `LLM_MODEL`, to enable it.

Pushing a `v*` tag triggers Release, which runs CI on both architectures, verifies the version, builds and signs separate Apple Silicon and Intel ZIPs, installs each signed ZIP on its matching runner with an empty profile, checks the window and runs the core downloaded on first launch, then publishes the same archives and their signatures from a draft. A retry can resume a draft. An existing public release is never overwritten.

Follow the [tagging rules](../AGENTS.md) and keep the workflow draft marked as a stable release. Before publishing, Actions verifies each new ZIP signature with the public key from the previous stable app for that architecture. The first release uses the key tested in the current build. A release lookup, download or signature failure stops publication. The publish job adds GitHub's contributors and full changelog to the notes.

## Локальная проверка / Local release check

```sh
WARPSCOUT_SIGNING_KEY="$HOME/.config/warpscout-release/signing.key" ./scripts/build.sh
./scripts/test-distribution.sh
```

Для проверки реальной первой установки выполните `WARPSCOUT_TEST_FIRST_LAUNCH=1 ./scripts/test-distribution.sh`. Приложение, запущенное из проверяемого ZIP, скачает ядро в изолированный каталог. Обычный CI использует локальный тестовый файл. Обновление способа доставки не устраняет уязвимости версии ядра, выбранной upstream.

Use `WARPSCOUT_TEST_FIRST_LAUNCH=1 ./scripts/test-distribution.sh` to test a real first launch with GitHub access. The release app downloads the core into an isolated home. Default CI uses a local fixture.
