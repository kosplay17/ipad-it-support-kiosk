# IT Support Kiosk (iPad)

Приложение-киоск для iPad: показывает страницу
`https://wiki.yandex.ru/sd-portal/it-support/it-support-office/`, пускает только на разрешённые домены
(`yandex.ru` с поддоменами, `auth.cloud.yandex.com`, `sso.ya.ru`, `lamoda.ru`, `lamoda.tech`), имеет кнопку
«Домой», через 30 секунд бездействия возвращается на главную и автоматически входит под сервисной
учётной записью, включая код 2FA.

Настройки (адреса, таймаут, PIN администратора) — в `ITSupportKiosk/KioskConfig.swift`.

## 1. Сборка

1. Установите Xcode из App Store и XcodeGen: `brew install xcodegen`.
2. В папке проекта выполните `xcodegen generate` и откройте `ITSupportKiosk.xcodeproj`.
3. Target `ITSupportKiosk` → Signing & Capabilities → выберите Team, при необходимости смените Bundle Identifier.
4. Смените `adminPIN` в `KioskConfig.swift`.

## 2. Установка на iPad

| Способ | Срок жизни приложения | Когда подходит |
|---|---|---|
| Xcode + бесплатный Apple ID | 7 дней | только для проверки |
| Apple Developer Program (Development / Ad Hoc) | 1 год | 1–100 iPad, UDID регистрируется в аккаунте |
| Корпоративный аккаунт (Enterprise / Apple Business Manager) + MDM | пока действует сертификат | парк устройств, рекомендуемый вариант |

Установка через Xcode: подключите iPad кабелем, на iPad включите Настройки → Конфиденциальность и
безопасность → Режим разработчика, выберите iPad в Xcode и нажмите Run.

Установка .ipa без Xcode: Product → Archive → Distribute App → Ad Hoc (или Enterprise), затем
перетащите .ipa на iPad в Apple Configurator 2 либо загрузите в MDM.

## 3. Блокировка iPad в приложении

Само приложение не может запретить выход из себя — это делает iPadOS:

- **Гид-доступ** (без MDM): Настройки → Универсальный доступ → Гид-доступ → включить, задать код.
  Откройте приложение и трижды нажмите боковую/Home-кнопку → «Начать».
- **Single App Mode** (надёжнее, переживает перезагрузку): iPad переводится в supervised-режим через
  Apple Configurator 2 (с полным стиранием) или MDM. Затем в Configurator: Actions → Advanced →
  Start Single App Mode → выбрать приложение. В MDM — профиль App Lock / Single App Mode.
  Если MDM разрешит приложению Autonomous Single App Mode, приложение само включит блокировку при запуске.

Также в Настройки → Экран и яркость → Автоблокировка → «Никогда» (приложение и так не даёт экрану гаснуть).

## 4. Первичная настройка на iPad

1. Удерживайте кнопку «Домой» 5 секунд → введите PIN.
2. «Задать логин и пароль» → почта и пароль сервисной учётной записи.
3. «Задать секрет 2FA (TOTP)» → ключ Base32 из настройки приложения-аутентификатора.
4. Всё хранится в Keychain устройства, в коде и репозитории этих данных нет.

Вместо ввода на iPad данные можно передать с Mac. Приложение при запуске перенесёт их в Keychain
и удалит файл (любое поле можно опустить):

```bash
echo '{"login":"…","password":"…","totpSecret":"…"}' > /tmp/kiosk-credentials.json
xcrun devicectl device copy to --device <UDID> --domain-type appDataContainer \
  --domain-identifier ru.itsupport.office.kiosk \
  --source /tmp/kiosk-credentials.json --destination Documents/kiosk-credentials.json
rm /tmp/kiosk-credentials.json
```

## Как работает автовход

Цепочка: вики → `auth.cloud.yandex.ru` («Войти с помощью Yandex») → Яндекс ID (почта) →
ADFS `sso.lamoda.ru` (логин, пароль, «Оставаться в системе») → код TOTP → вики.
Сессия сохраняется на устройстве, поэтому автовход срабатывает только когда она истекла.
На страницах входа возврат по бездействию отключён.

- Не больше 6 отправок пароля и кода за 5 минут, при ошибке на форме ADFS повтора нет — чтобы не заблокировать учётку.
- Капчу скрипт не проходит.
- Если формы поменяются или появится новый домен, смотрите журнал отладочной сборки
  (`xcrun devicectl device process launch --console …`): переходы пишутся как `Allowed:` / `Blocked:`,
  содержимое страниц — как `Page:`. Новые страницы входа добавляются в `authHosts`.
