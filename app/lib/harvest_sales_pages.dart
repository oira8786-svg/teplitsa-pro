import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _db = Supabase.instance.client;

List<Map<String, dynamic>> _maps(dynamic value) =>
    (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

String _money(num value) => '${value.toStringAsFixed(2)} ₽';

class HarvestPage extends StatefulWidget {
  const HarvestPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<HarvestPage> createState() => _HarvestPageState();
}

class _HarvestPageState extends State<HarvestPage> {
  late Future<List<dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }

  Future<List<dynamic>> _load() async => Future.wait([
    _db.from('harvest_lots').select('id,batch_id,lot_number,harvested_at,quantity,unit,grade,status,storage_location')
      .eq('organization_id', widget.organizationId).order('harvested_at', ascending: false),
    _db.from('batches').select('id,batch_number').eq('organization_id', widget.organizationId)
      .inFilter('status', ['planned','growing','harvesting']).order('batch_number'),
  ]);

  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _newHarvest(List<Map<String, dynamic>> batches) async {
    if (batches.isEmpty) { _message('Сначала создай активную партию растений.', error: true); return; }
    final formKey = GlobalKey<FormState>();
    final quantity = TextEditingController();
    final grade = TextEditingController();
    final location = TextEditingController();
    String batchId = batches.first['id'].toString();
    String unit = 'kg';
    final ok = await showDialog<bool>(context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Новый сбор урожая'),
        content: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: batchId, decoration: const InputDecoration(labelText: 'Партия растений'),
            items: batches.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['batch_number'].toString()))).toList(),
            onChanged: (v) => setDialog(() => batchId = v ?? batchId)),
          const SizedBox(height: 10),
          TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Количество *'),
            validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Укажи количество больше нуля' : null),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: unit, decoration: const InputDecoration(labelText: 'Единица'),
            items: const [DropdownMenuItem(value: 'kg', child: Text('кг')), DropdownMenuItem(value: 'g', child: Text('г')),
              DropdownMenuItem(value: 'pcs', child: Text('шт.'))],
            onChanged: (v) => setDialog(() => unit = v ?? unit)),
          const SizedBox(height: 10),
          TextFormField(controller: grade, decoration: const InputDecoration(labelText: 'Сортность / качество')),
          const SizedBox(height: 10),
          TextFormField(controller: location, decoration: const InputDecoration(labelText: 'Место хранения')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Записать сбор')),
        ],
      )));
    if (ok != true) { quantity.dispose(); grade.dispose(); location.dispose(); return; }
    try {
      await _db.rpc('record_harvest_lot', params: {
        'p_organization_id': widget.organizationId,
        'p_batch_id': batchId,
        'p_lot_number': 'H-${DateTime.now().millisecondsSinceEpoch}',
        'p_harvested_at': DateTime.now().toUtc().toIso8601String(),
        'p_quantity': double.parse(quantity.text.replaceAll(',', '.')),
        'p_unit': unit,
        'p_grade': grade.text.trim().isEmpty ? null : grade.text.trim(),
        'p_quality_notes': null,
        'p_storage_location': location.text.trim().isEmpty ? null : location.text.trim(),
      });
      await _refresh();
      if (mounted) _message('Сбор урожая записан');
    } catch (e) { if (mounted) _message('Не удалось записать сбор: $e', error: true); }
    finally { quantity.dispose(); grade.dispose(); location.dispose(); }
  }

  void _message(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _HarvestError(error: snap.error.toString(), retry: _refresh);
    final lots = _maps(snap.data![0]);
    final batches = _maps(snap.data![1]);
    final batchNames = {for (final b in batches) b['id'].toString(): b['batch_number'].toString()};
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(onPressed: () => _newHarvest(batches), icon: const Icon(Icons.add), label: const Text('Записать сбор урожая')))),
      Expanded(child: lots.isEmpty ? const Center(child: Text('Сборов пока нет'))
        : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: lots.length, itemBuilder: (context, i) {
            final e = lots[i];
            final date = DateTime.tryParse(e['harvested_at'].toString())?.toLocal();
            return Card(child: ListTile(leading: const Icon(Icons.agriculture_outlined),
              title: Text(e['lot_number'].toString()),
              subtitle: Text('Партия: ${batchNames[e['batch_id']] ?? '—'} • ${e['status']} ${date == null ? '' : '• ${date.day.toString().padLeft(2,'0')}.${date.month.toString().padLeft(2,'0')}.${date.year}'}'),
              trailing: Text('${e['quantity']} ${e['unit']}', style: const TextStyle(fontWeight: FontWeight.w700))));
          }))),
    ]);
  });
}

class SalesPage extends StatefulWidget {
  const SalesPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  late Future<List<dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }

  Future<List<dynamic>> _load() async => Future.wait([
    _db.from('sales').select('id,sale_number,sold_at,status,customer_id,notes')
      .eq('organization_id', widget.organizationId).order('sold_at', ascending: false).limit(100),
    _db.from('sale_lines').select('sale_id,harvest_lot_id,quantity,unit,unit_price,discount')
      .eq('organization_id', widget.organizationId),
    _db.from('payments').select('sale_id,amount').eq('organization_id', widget.organizationId),
    _db.from('harvest_lots').select('id,lot_number,quantity,unit,status')
      .eq('organization_id', widget.organizationId).inFilter('status', ['available','partly_sold']),
    _db.from('customers').select('id,name').eq('organization_id', widget.organizationId).order('name'),
  ]);

  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _newSale(List<Map<String, dynamic>> lots, List<Map<String, dynamic>> customers) async {
    if (lots.isEmpty) { _message('Нет доступного урожая для продажи. Сначала зарегистрируй сбор.', error: true); return; }
    final formKey = GlobalKey<FormState>();
    final quantity = TextEditingController();
    final price = TextEditingController();
    final notes = TextEditingController();
    String lotId = lots.first['id'].toString();
    String? customerId;
    final ok = await showDialog<bool>(context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Новая продажа'),
        content: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: lotId, decoration: const InputDecoration(labelText: 'Партия урожая'),
            items: lots.map((e) => DropdownMenuItem(value: e['id'].toString(),
              child: Text('${e['lot_number']} • ${e['quantity']} ${e['unit']}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setDialog(() => lotId = v ?? lotId)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(initialValue: customerId, decoration: const InputDecoration(labelText: 'Покупатель (необязательно)'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('Без покупателя')),
              ...customers.map((e) => DropdownMenuItem<String?>(value: e['id'].toString(), child: Text(e['name'].toString(), overflow: TextOverflow.ellipsis)))],
            onChanged: (v) => setDialog(() => customerId = v)),
          const SizedBox(height: 10),
          TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Количество *'),
            validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Укажи количество больше нуля' : null),
          const SizedBox(height: 10),
          TextFormField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Цена за единицу, ₽ *'),
            validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) < 0 ? 'Укажи цену от нуля' : null),
          const SizedBox(height: 10),
          TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Примечание')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Провести продажу')),
        ],
      )));
    if (ok != true) { quantity.dispose(); price.dispose(); notes.dispose(); return; }
    try {
      final lot = lots.firstWhere((e) => e['id'].toString() == lotId);
      await _db.rpc('post_sale', params: {
        'p_organization_id': widget.organizationId,
        'p_sale_number': 'S-${DateTime.now().millisecondsSinceEpoch}',
        'p_lines': [{
          'harvest_lot_id': lotId,
          'quantity': double.parse(quantity.text.replaceAll(',', '.')),
          'unit': lot['unit'],
          'unit_price': double.parse(price.text.replaceAll(',', '.')),
          'discount': 0,
        }],
        'p_customer_id': customerId,
        'p_sold_at': DateTime.now().toUtc().toIso8601String(),
        'p_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
      await _refresh();
      if (mounted) _message('Продажа проведена');
    } catch (e) { if (mounted) _message('Не удалось провести продажу: $e', error: true); }
    finally { quantity.dispose(); price.dispose(); notes.dispose(); }
  }

  Future<void> _pay(Map<String, dynamic> sale, double outstanding) async {
    if (outstanding <= 0) return;
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    String method = 'cash';
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: Text('Оплата ${sale['sale_number']}'),
        content: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Сумма, ₽'),
            validator: (v) {
              final n = double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
              return n <= 0 || n > outstanding ? 'Сумма должна быть от 0 до ${outstanding.toStringAsFixed(2)}' : null;
            }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: method, decoration: const InputDecoration(labelText: 'Способ оплаты'),
            items: const [DropdownMenuItem(value: 'cash', child: Text('Наличные')),
              DropdownMenuItem(value: 'bank_transfer', child: Text('Перевод')),
              DropdownMenuItem(value: 'card', child: Text('Карта')),
              DropdownMenuItem(value: 'other', child: Text('Другое'))],
            onChanged: (v) => setDialog(() => method = v ?? method)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Записать оплату')),
        ],
      )));
    if (ok != true) { amount.dispose(); return; }
    try {
      await _db.rpc('record_sale_payment', params: {
        'p_organization_id': widget.organizationId,
        'p_sale_id': sale['id'],
        'p_amount': double.parse(amount.text.replaceAll(',', '.')),
        'p_payment_method': method,
        'p_paid_at': DateTime.now().toUtc().toIso8601String(),
        'p_reference_number': null,
        'p_notes': null,
      });
      await _refresh();
      if (mounted) _message('Оплата записана');
    } catch (e) { if (mounted) _message('Не удалось записать оплату: $e', error: true); }
    finally { amount.dispose(); }
  }

  void _message(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _HarvestError(error: snap.error.toString(), retry: _refresh);
    final sales = _maps(snap.data![0]);
    final lines = _maps(snap.data![1]);
    final payments = _maps(snap.data![2]);
    final lots = _maps(snap.data![3]);
    final customers = _maps(snap.data![4]);
    final lotNames = {for (final e in lots) e['id'].toString(): e['lot_number'].toString()};
    final customerNames = {for (final e in customers) e['id'].toString(): e['name'].toString()};
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(onPressed: () => _newSale(lots, customers), icon: const Icon(Icons.add), label: const Text('Новая продажа')))),
      Expanded(child: sales.isEmpty ? const Center(child: Text('Продаж пока нет'))
        : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: sales.length, itemBuilder: (context, i) {
            final sale = sales[i];
            final saleLines = lines.where((e) => e['sale_id'] == sale['id']).toList();
            final total = saleLines.fold<double>(0, (sum, e) => sum +
              ((e['quantity'] as num).toDouble() * (e['unit_price'] as num).toDouble()) - (e['discount'] as num).toDouble());
            final paid = payments.where((e) => e['sale_id'] == sale['id']).fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
            final due = (total - paid).clamp(0, double.infinity).toDouble();
            return Card(child: ExpansionTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: Text(sale['sale_number'].toString()),
              subtitle: Text('${sale['status']} • ${_money(total)} • оплачено ${_money(paid)}'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final line in saleLines) ListTile(dense: true,
                  title: Text(lotNames[line['harvest_lot_id']] ?? 'Партия урожая'),
                  subtitle: Text('${line['quantity']} ${line['unit']} × ${_money((line['unit_price'] as num).toDouble())}')),
                if (sale['customer_id'] != null) Align(alignment: Alignment.centerLeft,
                  child: Text('Покупатель: ${customerNames[sale['customer_id']] ?? '—'}')),
                if (due > 0) Align(alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: () => _pay(sale, due),
                    icon: const Icon(Icons.payments_outlined), label: Text('Принять оплату • ${_money(due)}'))),
              ],
            ));
          }))),
    ]);
  });
}

class _HarvestError extends StatelessWidget {
  const _HarvestError({required this.error, required this.retry});
  final String error;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 40), const SizedBox(height: 12),
      Text('Не удалось загрузить данные: $error', textAlign: TextAlign.center),
      const SizedBox(height: 12), FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
    ])));
}
