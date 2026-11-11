import 'package:flutter/material.dart';

void main() {
  runApp(const TeplitsaProApp());
}

class TeplitsaProApp extends StatelessWidget {
  const TeplitsaProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ТЕПЛИЦА PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF287A4B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const modules = <_ModuleInfo>[
    _ModuleInfo('Теплицы и зоны', Icons.warehouse_outlined),
    _ModuleInfo('Культуры и партии', Icons.grass_outlined),
    _ModuleInfo('Агрономический журнал', Icons.event_note_outlined),
    _ModuleInfo('Полив и подкормки', Icons.water_drop_outlined),
    _ModuleInfo('Защита растений', Icons.health_and_safety_outlined),
    _ModuleInfo('Склад', Icons.inventory_2_outlined),
    _ModuleInfo('Урожай и продажи', Icons.shopping_basket_outlined),
    _ModuleInfo('Финансы', Icons.account_balance_wallet_outlined),
    _ModuleInfo('Сотрудники и задачи', Icons.groups_outlined),
    _ModuleInfo('Отчёты', Icons.query_stats_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ТЕПЛИЦА PRO',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Профиль и настройки',
            onPressed: () {},
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 4
              : constraints.maxWidth >= 650
                  ? 3
                  : 2;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Панель управления',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text(
                        'Учёт теплиц, выращивания, ресурсов, урожая и финансов в одном месте.',
                      ),
                      const SizedBox(height: 12),
                      const Chip(
                        avatar: Icon(Icons.construction_outlined, size: 18),
                        label: Text('Начальная версия интерфейса'),
                      ),
                      const Text(
                        'Данные пока не подключены. Следующий этап — авторизация и связь с базой Supabase.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Разделы хозяйства',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: modules.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (context, index) {
                  final module = modules[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Раздел «${module.title}» будет подключён на следующем этапе.',
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(module.icon, size: 30),
                            Text(
                              module.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModuleInfo {
  const _ModuleInfo(this.title, this.icon);

  final String title;
  final IconData icon;
}
