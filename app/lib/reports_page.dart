import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  double _number(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  Future<Map<String, dynamic>> _load() async {
    final db = Supabase.instance.client;
    final rows = await Future.wait([
      db.from('greenhouses').select('id')
          .eq('organization_id', widget.organizationId).eq('active', true),
      db.from('batches').select('id')
          .eq('organization_id', widget.organizationId),
      db.from('harvest_lots').select('id,quantity,unit')
          .eq('organization_id', widget.organizationId),
      db.from('sales').select('id,status,sold_at')
          .eq('organization_id', widget.organizationId)
          .neq('status', 'cancelled'),
      db.from('sale_lines').select('quantity,unit_price,discount')
          .eq('organization_id', widget.organizationId),
      db.from('payments').select('amount')
          .eq('organization_id', widget.organizationId),
      db.from('expenses').select('amount')
          .eq('organization_id', widget.organizationId),
      db.from('inventory_items').select('id,name,base_unit,minimum_stock')
          .eq('organization_id', widget.organizationId).eq('active', true),
      db.from('inventory_movements').select('item_id,movement_type,quantity,unit')
          .eq('organization_id', widget.organizationId),
    ]);

    final harvestRows = (rows[2] as List).cast<Map<String, dynamic>>();
    final harvestByUnit = <String, double>{};
    for (final row in harvestRows) {
      final unit = row['unit']?.toString() ?? 'ед.';
      harvestByUnit[unit] = (harvestByUnit[unit] ?? 0) + _number(row['quantity']);
    }

    var revenue = 0.0;
    for (final row in (rows[4] as List)) {
      final lineTotal = _number(row['quantity']) * _number(row['unit_price']);
      revenue += (lineTotal - _number(row['discount']))
          .clamp(0, double.infinity).toDouble();
    }
    final paid = (rows[5] as List).fold<double>(
      0, (sum, row) => sum + _number(row['amount']));
    final expenses = (rows[6] as List).fold<double>(
      0, (sum, row) => sum + _number(row['amount']));

    final balances = <String, double>{};
    for (final row in (rows[8] as List)) {
      final type = row['movement_type']?.toString();
      final quantity = _number(row['quantity']);
      final sign = switch (type) {
        'receipt' || 'adjustment_in' || 'transfer_in' => 1.0,
        'issue' || 'writeoff' || 'adjustment_out' ||
        'transfer_out' || 'production_use' || 'sale' => -1.0,
        _ => 0.0,
      };
      final itemId = row['item_id']?.toString();
      if (itemId != null) {
        balances[itemId] = (balances[itemId] ?? 0) + sign * quantity;
      }
    }
    var lowStock = 0;
    for (final item in (rows[7] as List)) {
      final id = item['id']?.toString();
      if (id == null) continue;
      final balance = balances[id] ?? 0;
      final minimum = _number(item['minimum_stock']);
      if (balance <= minimum) lowStock++;
    }

    return {
      'greenhouses': (rows[0] as List).length,
      'batches': (rows[1] as List).length,
      'harvestLots': harvestRows.length,
      'harvestByUnit': harvestByUnit,
      'sales': (rows[3] as List).length,
      'revenue': revenue,
      'paid': paid,
      'receivable': (revenue - paid).clamp(0, double.infinity).toDouble(),
      'expenses': expenses,
      'inventory': (rows[7] as List).length,
      'lowStock': lowStock,
    };
  }

  String _money(dynamic value) =>
      '${_number(value).toStringAsFixed(2)} ₽';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Отчёты хозяйства'),
      actions: [
        IconButton(
          tooltip: 'Обновить',
          onPressed: () => setState(() => _future = _load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              const Text('Не удалось сформировать отчёт. Проверь доступ к данным и повтори загрузку.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => setState(() => _future = _load()),
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ]),
          ));
        }
        final d = snapshot.data!;
        final harvestByUnit = d['harvestByUnit'] as Map<String, double>;
        final cards = <(String, String, IconData)>[
          ('Теплицы', '${d['greenhouses']}', Icons.warehouse_outlined),
          ('Партии растений', '${d['batches']}', Icons.grass_outlined),
          ('Партии урожая', '${d['harvestLots']}', Icons.agriculture_outlined),
          ('Продажи', '${d['sales']}', Icons.point_of_sale_outlined),
          ('Выручка по документам', _money(d['revenue']), Icons.trending_up),
          ('Получено оплат', _money(d['paid']), Icons.payments_outlined),
          ('Долг покупателей', _money(d['receivable']), Icons.account_balance_wallet_outlined),
          ('Учтённые расходы', _money(d['expenses']), Icons.receipt_long_outlined),
          ('Позиции склада', '${d['inventory']}', Icons.inventory_2_outlined),
          ('Позиции на минимуме/ниже', '${d['lowStock']}', Icons.warning_amber_outlined),
        ];
        return RefreshIndicator(
          onRefresh: () async {
            final next = _load();
            setState(() => _future = next);
            await next;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFF087A3D),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const Icon(Icons.insights_outlined, color: Colors.white, size: 36),
                    const SizedBox(width: 14),
                    Expanded(child: Text(
                      'ФаёзАгро\nСводка по хозяйству',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: Colors.white),
                    )),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              for (final item in cards)
                Card(child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFD5EED8),
                    child: Icon(item.$3, color: const Color(0xFF087A3D)),
                  ),
                  title: Text(item.$1),
                  trailing: Text(item.$2,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                )),
              if (harvestByUnit.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text('Собрано по единицам измерения',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                for (final entry in harvestByUnit.entries)
                  Card(child: ListTile(
                    title: Text(entry.key),
                    trailing: Text(entry.value.toStringAsFixed(2)),
                  )),
              ],
              const SizedBox(height: 8),
              const Text(
                'Выручка рассчитана по строкам продаж, долг — как выручка минус зарегистрированные оплаты. '
                'Остатки склада учитывают движения с известным направлением. '
                'Это управленческая сводка, а не бухгалтерская или налоговая отчётность.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        );
      },
    ),
  );
}
