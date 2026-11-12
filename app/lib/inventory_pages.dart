import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _db = Supabase.instance.client;

List<Map<String, dynamic>> _rows(dynamic value) =>
    (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

const _itemCategories = <String, String>{
  'fertilizer': 'Удобрения',
  'plant_protection': 'Защита растений',
  'seeds': 'Семена',
  'substrate': 'Субстраты',
  'packaging': 'Упаковка',
  'fuel': 'Топливо',
  'spare_parts': 'Запчасти',
  'equipment': 'Оборудование',
  'other': 'Прочее',
};

const _units = <String, String>{
  'pcs': 'шт.',
  'g': 'г',
  'kg': 'кг',
  't': 'т',
  'ml': 'мл',
  'l': 'л',
  'm3': 'м³',
};

class InventoryItemsPage extends StatefulWidget {
  const InventoryItemsPage({required this.organizationId, super.key});
  final String organizationId;

  @override
  State<InventoryItemsPage> createState() => _InventoryItemsPageState();
}

class _InventoryItemsPageState extends State<InventoryItemsPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final results = await Future.wait([
      _db.from('inventory_items').select('id,name,category,base_unit,minimum_stock,sku,active')
          .eq('organization_id', widget.organizationId).eq('active', true).order('name'),
      _db.from('warehouses').select('id,name,active')
          .eq('organization_id', widget.organizationId).eq('active', true).order('name'),
      _db.from('inventory_movements').select('item_id,movement_type,quantity,warehouse_id')
          .eq('organization_id', widget.organizationId),
    ]);
    return results;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _createWarehouse() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый склад'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название склада'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи название' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
          }, child: const Text('Создать')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await _db.from('warehouses').insert({'organization_id': widget.organizationId, 'name': name});
      await _refresh();
      if (mounted) _message('Склад создан');
    } catch (e) {
      if (mounted) _message('Не удалось создать склад: $e', error: true);
    }
  }

  Future<void> _createItem() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final sku = TextEditingController();
    final minimum = TextEditingController(text: '0');
    String category = 'other';
    String unit = 'pcs';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Новая складская позиция'),
        content: SingleChildScrollView(child: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Название *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи название' : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Категория'),
              items: _itemCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setDialog(() => category = v ?? category),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: unit,
              decoration: const InputDecoration(labelText: 'Базовая единица'),
              items: _units.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setDialog(() => unit = v ?? unit),
            ),
            const SizedBox(height: 10),
            TextFormField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Минимальный остаток'),
              validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) < 0 ? 'Укажи число не меньше нуля' : null),
            const SizedBox(height: 10),
            TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'Артикул (необязательно)')),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          }, child: const Text('Сохранить')),
        ],
      )),
    );
    if (ok != true) {
      name.dispose(); sku.dispose(); minimum.dispose();
      return;
    }
    try {
      await _db.from('inventory_items').insert({
        'organization_id': widget.organizationId,
        'name': name.text.trim(),
        'category': category,
        'base_unit': unit,
        'minimum_stock': double.parse(minimum.text.replaceAll(',', '.')),
        'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
      });
      await _refresh();
      if (mounted) _message('Позиция добавлена');
    } catch (e) {
      if (mounted) _message('Не удалось добавить позицию: $e', error: true);
    } finally {
      name.dispose(); sku.dispose(); minimum.dispose();
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  double _balance(List<Map<String, dynamic>> movements, String itemId) {
    var total = 0.0;
    for (final m in movements.where((e) => e['item_id'] == itemId)) {
      final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
      final type = m['movement_type'];
      if (['receipt', 'adjustment_in', 'transfer_in'].contains(type)) total += qty;
      if (['issue', 'writeoff', 'adjustment_out', 'transfer_out', 'production_use', 'sale'].contains(type)) total -= qty;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _LoadError(message: snapshot.error.toString(), onRetry: _refresh);
      final items = _rows(snapshot.data![0]);
      final warehouses = _rows(snapshot.data![1]);
      final movements = _rows(snapshot.data![2]);
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _createItem, icon: const Icon(Icons.add), label: const Text('Добавить позицию')),
              OutlinedButton.icon(onPressed: _createWarehouse, icon: const Icon(Icons.warehouse_outlined), label: const Text('Новый склад')),
            ]),
            const SizedBox(height: 12),
            Card(child: ListTile(
              leading: const Icon(Icons.warehouse_outlined),
              title: Text('Складские площадки: ${warehouses.length}'),
              subtitle: Text(warehouses.isEmpty ? 'Сначала создай склад для учёта движений' : warehouses.map((e) => e['name'].toString()).join(' • ')),
            )),
            const SizedBox(height: 8),
            if (items.isEmpty) const Padding(
              padding: EdgeInsets.all(28),
              child: Column(children: [Icon(Icons.inventory_2_outlined, size: 48), SizedBox(height: 12),
                Text('Складских позиций пока нет', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Добавь позицию и затем регистрируй поступления.', textAlign: TextAlign.center)]),
            ),
            for (final item in items) Card(child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(item['name'].toString()),
              subtitle: Text('${_itemCategories[item['category']] ?? item['category']} • минимум: ${item['minimum_stock']} ${_units[item['base_unit']] ?? item['base_unit']}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_balance(movements, item['id'].toString()).toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium),
                Text(_units[item['base_unit']] ?? item['base_unit'], style: Theme.of(context).textTheme.labelSmall),
              ]),
            )),
          ],
        ),
      );
    },
  );
}

class InventoryMovementsPage extends StatefulWidget {
  const InventoryMovementsPage({required this.organizationId, super.key});
  final String organizationId;

  @override
  State<InventoryMovementsPage> createState() => _InventoryMovementsPageState();
}

class _InventoryMovementsPageState extends State<InventoryMovementsPage> {
  late Future<List<dynamic>> _future;
  bool _saving = false;

  @override
  void initState() { super.initState(); _future = _load(); }

  Future<List<dynamic>> _load() async {
    final results = await Future.wait([
      _db.from('inventory_movements').select('id,item_id,warehouse_id,movement_type,quantity,unit,occurred_at,document_number,notes')
        .eq('organization_id', widget.organizationId).order('occurred_at', ascending: false).limit(200),
      _db.from('inventory_items').select('id,name,base_unit').eq('organization_id', widget.organizationId).eq('active', true).order('name'),
      _db.from('warehouses').select('id,name').eq('organization_id', widget.organizationId).eq('active', true).order('name'),
    ]);
    return results;
  }

  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _newMovement(List<Map<String, dynamic>> items, List<Map<String, dynamic>> warehouses) async {
    if (items.isEmpty || warehouses.isEmpty) {
      _message('Сначала добавь склад и хотя бы одну складскую позицию.', error: true);
      return;
    }
    final formKey = GlobalKey<FormState>();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    final document = TextEditingController();
    final notes = TextEditingController();
    String itemId = items.first['id'].toString();
    String warehouseId = warehouses.first['id'].toString();
    String type = 'receipt';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Новое движение склада'),
        content: SingleChildScrollView(child: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: type, decoration: const InputDecoration(labelText: 'Операция'),
              items: const [
                DropdownMenuItem(value: 'receipt', child: Text('Поступление')),
                DropdownMenuItem(value: 'issue', child: Text('Выдача / расход')),
                DropdownMenuItem(value: 'writeoff', child: Text('Списание')),
                DropdownMenuItem(value: 'adjustment_in', child: Text('Корректировка: плюс')),
                DropdownMenuItem(value: 'adjustment_out', child: Text('Корректировка: минус')),
                DropdownMenuItem(value: 'production_use', child: Text('Использовано в производстве')),
              ],
              onChanged: (v) => setDialog(() => type = v ?? type),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: itemId, decoration: const InputDecoration(labelText: 'Позиция'),
              items: items.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setDialog(() => itemId = v ?? itemId),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: warehouseId, decoration: const InputDecoration(labelText: 'Склад'),
              items: warehouses.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['name'].toString(), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setDialog(() => warehouseId = v ?? warehouseId),
            ),
            const SizedBox(height: 10),
            TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Количество (${_units[items.firstWhere((e) => e['id'].toString() == itemId)['base_unit']] ?? items.firstWhere((e) => e['id'].toString() == itemId)['base_unit']})'),
              validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Укажи количество больше нуля' : null),
            const SizedBox(height: 10),
            TextFormField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Цена за единицу, ₽ (необязательно)'),
              validator: (v) => v == null || v.trim().isEmpty || (double.tryParse(v.replaceAll(',', '.')) ?? -1) >= 0 ? null : 'Некорректная цена'),
            const SizedBox(height: 10),
            TextFormField(controller: document, decoration: const InputDecoration(labelText: 'Номер документа')),
            const SizedBox(height: 10),
            TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Примечание')),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          }, child: const Text('Провести')),
        ],
      )),
    );
    if (ok != true) { quantity.dispose(); cost.dispose(); document.dispose(); notes.dispose(); return; }
    setState(() => _saving = true);
    try {
      final selected = items.firstWhere((e) => e['id'].toString() == itemId);
      await _db.rpc('post_inventory_movement', params: {
        'p_organization_id': widget.organizationId,
        'p_warehouse_id': warehouseId,
        'p_item_id': itemId,
        'p_movement_type': type,
        'p_quantity': double.parse(quantity.text.replaceAll(',', '.')),
        'p_unit': selected['base_unit'],
        'p_unit_cost': cost.text.trim().isEmpty ? null : double.parse(cost.text.replaceAll(',', '.')),
        'p_document_number': document.text.trim().isEmpty ? null : document.text.trim(),
        'p_occurred_at': DateTime.now().toUtc().toIso8601String(),
        'p_related_batch_id': null,
        'p_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
      await _refresh();
      if (mounted) _message('Движение проведено, остаток обновлён');
    } catch (e) {
      if (mounted) _message('Не удалось провести движение: $e', error: true);
    } finally {
      quantity.dispose(); cost.dispose(); document.dispose(); notes.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _LoadError(message: snapshot.error.toString(), onRetry: _refresh);
      final movements = _rows(snapshot.data![0]);
      final items = _rows(snapshot.data![1]);
      final warehouses = _rows(snapshot.data![2]);
      final itemNames = {for (final e in items) e['id'].toString(): e['name'].toString()};
      final warehouseNames = {for (final e in warehouses) e['id'].toString(): e['name'].toString()};
      return Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _newMovement(items, warehouses),
            icon: const Icon(Icons.add), label: const Text('Зарегистрировать движение'),
          ))),
        Expanded(child: movements.isEmpty
          ? const Center(child: Text('Движений пока нет'))
          : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: movements.length,
              itemBuilder: (context, index) {
                final m = movements[index];
                final incoming = ['receipt', 'adjustment_in', 'transfer_in'].contains(m['movement_type']);
                final date = DateTime.tryParse(m['occurred_at']?.toString() ?? '')?.toLocal();
                final typeNames = {
                  'receipt': 'Поступление', 'issue': 'Выдача / расход', 'writeoff': 'Списание',
                  'adjustment_in': 'Корректировка +', 'adjustment_out': 'Корректировка −',
                  'production_use': 'Использовано в производстве',
                };
                return Card(child: ListTile(
                  leading: Icon(incoming ? Icons.south_west : Icons.north_east, color: incoming ? Colors.green : Colors.deepOrange),
                  title: Text(itemNames[m['item_id']] ?? 'Складская позиция'),
                  subtitle: Text('${typeNames[m['movement_type']] ?? m['movement_type']} • ${warehouseNames[m['warehouse_id']] ?? 'Склад'}${date == null ? '' : ' • ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}'}'),
                  trailing: Text('${incoming ? '+' : '−'}${m['quantity']} ${_units[m['unit']] ?? m['unit']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ));
              },
            )),
        ),
      ]);
    },
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 40),
      const SizedBox(height: 12),
      Text('Не удалось загрузить склад: $message', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
    ]),
  ));
}
