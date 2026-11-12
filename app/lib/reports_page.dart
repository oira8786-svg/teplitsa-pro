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
  void initState() { super.initState(); _future = _load(); }

  Future<Map<String, dynamic>> _load() async {
    final db = Supabase.instance.client;
    final rows = await Future.wait([
      db.from('greenhouses').select('id').eq('organization_id', widget.organizationId).eq('active', true),
      db.from('batches').select('id').eq('organization_id', widget.organizationId),
      db.from('harvest_lots').select('id,quantity').eq('organization_id', widget.organizationId),
      db.from('sales').select('id').eq('organization_id', widget.organizationId),
      db.from('expenses').select('amount').eq('organization_id', widget.organizationId),
      db.from('inventory_items').select('id').eq('organization_id', widget.organizationId).eq('active', true),
    ]);
    final expenses = (rows[4] as List).fold<double>(0, (sum, row) =>
      sum + (double.tryParse(row['amount']?.toString() ?? '') ?? 0));
    final harvest = (rows[2] as List).fold<double>(0, (sum, row) =>
      sum + (double.tryParse(row['quantity']?.toString() ?? '') ?? 0));
    return {
      'greenhouses': (rows[0] as List).length,
      'batches': (rows[1] as List).length,
      'harvestLots': (rows[2] as List).length,
      'harvestQuantity': harvest,
      'sales': (rows[3] as List).length,
      'expenses': expenses,
      'inventory': (rows[5] as List).length,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Отчёты хозяйства')),
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
              Text('Не удалось сформировать отчёт: ${snapshot.error}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => setState(() => _future = _load()),
                icon: const Icon(Icons.refresh), label: const Text('Повторить'),
              ),
            ]),
          ));
        }
        final d = snapshot.data!;
        final cards = <(String, String, IconData)>[
          ('Теплицы', '${d['greenhouses']}', Icons.warehouse_outlined),
          ('Партии растений', '${d['batches']}', Icons.grass_outlined),
          ('Партии урожая', '${d['harvestLots']}', Icons.agriculture_outlined),
          ('Собрано всего', '${(d['harvestQuantity'] as num).toStringAsFixed(2)}', Icons.scale_outlined),
          ('Продажи', '${d['sales']}', Icons.point_of_sale_outlined),
          ('Позиции склада', '${d['inventory']}', Icons.inventory_2_outlined),
          ('Учтённые расходы, ₽', '${(d['expenses'] as num).toStringAsFixed(2)}', Icons.receipt_long_outlined),
        ];
        return RefreshIndicator(
          onRefresh: () async { final next = _load(); setState(() => _future = next); await next; },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(color: const Color(0xFF087A3D), child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  const Icon(Icons.insights_outlined, color: Colors.white, size: 36),
                  const SizedBox(width: 14),
                  Expanded(child: Text(
                    'Сводка по хозяйству\nДанные из учётных разделов',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                  )),
                ]),
              )),
              const SizedBox(height: 14),
              for (final item in cards) Card(child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFD5EED8),
                  child: Icon(item.$3, color: const Color(0xFF087A3D)),
                ),
                title: Text(item.$1),
                trailing: Text(item.$2, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              )),
              const SizedBox(height: 8),
              const Text(
                'Сводка носит учётный характер. Прибыль, себестоимость и точные остатки требуют полного проведения складских и финансовых документов.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        );
      },
    ),
  );
}
