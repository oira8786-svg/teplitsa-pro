# Применение новых серверных операций ФаёзАгро

В тестовом проекте Supabase открой SQL Editor и выполни файлы строго по порядку:

1. `supabase/migrations/202611110005_agronomy_operation_rpc.sql`
2. `supabase/migrations/202611120001_inventory_movement_rpc.sql`
3. `supabase/migrations/202611120002_harvest_sales_payment_rpc.sql`
4. `supabase/migrations/202611120003_finance_tasks_payroll_rpc.sql`

Для каждого файла: открой файл в GitHub, скопируй весь SQL, вставь в SQL Editor Supabase и нажми Run. Дождись успешного результата, затем переходи к следующему файлу.

Все четыре файла создают или заменяют функции; они не удаляют таблицы и существующие записи. Повторное выполнение этих SQL-файлов допустимо. Не запускай их в production-базе до отдельной проверки доступа, локализации данных и резервного копирования.

После применения:
- агрономический журнал сможет сохранять операции через `create_agronomy_operation`;
- склад сможет проводить поступления, расходы и списания через `post_inventory_movement`;
- урожай, продажи и оплаты будут проводиться через `record_harvest_lot`, `post_sale`, `record_sale_payment`;
- расходы, задачи и зарплата будут записываться через `record_expense`, `create_task`, `update_task_status`, `create_payroll_accrual`, `record_payroll_payment`.

Клиентская прямая запись в финансовые и складские журналы остаётся закрытой. Не выдавай права на прямой INSERT/UPDATE/DELETE в обход этих RPC.