# Flutter-клиент

Начальный UI-каркас с подготовленным клиентом Supabase. Авторизация, запросы к таблицам, офлайн-БД и синхронизация ещё не реализованы.

## Настройка подключения к тестовому Supabase

Установите зависимости из папки `app`:

```bash
flutter pub get
```

Запускайте приложение, передавая параметры сборки локально. Не добавляйте реальные значения ключей в Git:

**Windows PowerShell:**

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

**macOS / Linux:**

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

Замените значения на Project URL и Publishable key из своего Supabase Dashboard. Publishable key предназначен для клиентского приложения; безопасность данных обеспечивается RLS и корректными правами в базе. Никогда не передавайте в приложение `service_role` или Secret key.

Без параметров Supabase приложение запускается в демонстрационном режиме и показывает, что конфигурация не задана.

## Проверки и запуск

```bash
flutter analyze
flutter test
flutter run
```

Для Android/iOS используйте соответствующий настроенный эмулятор или устройство. Для desktop-платформ предварительно включите поддержку платформы в Flutter SDK.

## Ограничения текущего этапа

Инициализация SDK не означает, что база уже подключена к рабочим данным: миграции SQL ещё не применены и не проверены, RLS не прошёл интеграционные тесты, интерфейс авторизации и запросы к таблицам ещё не созданы. Используйте только тестовые данные.
