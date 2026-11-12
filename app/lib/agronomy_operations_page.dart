// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _operationNames = <String, String>{
  'watering': 'Полив',
  'fertilizing': 'Внесение удобрения',
  'feeding': 'Подкормка',
  'chemical_treatment': 'Химическая обработка',
  'biological_treatment': 'Биологическая обработка',
  'inspection': 'Осмотр',
  'transplanting': 'Пересадка',
  'pricking_out': 'Пикировка',
  'other': 'Другая работа',
};

const _quantityUnits = <String, String>{
  'pcs': 'шт.',
  'g': 'г',
  'kg': 'кг',
  'ml': 'мл',
  'l': 'л',
};

const _volumeUnits = <String, String>{
  'ml': 'мл',
  'l': 'л',
  'm3': 'м³',
};

String _value(dynamic value) => value?.toString() ?? '';

String _localDate(dynamic value) {
  final parsed = DateTime.tryParse(_value(value));
  if (parsed == null) return '—';
  final local = parsed.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class AgronomyOperationsPage extends StatefulWidget {
  const AgronomyOperationsPage({
    required this.organizationId,
    required this.canManage,
    this.protectionOnly = false,
    super.key,
  });

  final String organizationId;
  final bool canManage;
  final bool protectionOnly;

  @override
  State<AgronomyOperationsPage> createState() => _AgronomyOperationsPageState();
}

class _AgronomyOperationsPageState extends State<AgronomyOperationsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('agronomy_operations')
        .select('id,operation_type,performed_at,quantity,quantity_unit,water_volume,water_volume_unit,result,notes,batches(batch_number,crops(name),greenhouses(name),greenhouse_zones(name)),agricultural_products(name),treatment_safety(verification_status,harvest_wait_until,reentry_allowed_from)')
        .eq('organization_id', widget.organizationId)
        .order('performed_at', ascending: false)
        .limit(200);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  bool _isVisible(Map<String, dynamic> row) {
    if (!widget.protectionOnly) return true;
    final type = _value(row['operation_type']);
    return type == 'chemical_treatment' || type == 'biological_treatment';
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _OperationFormDialog(
        organizationId: widget.organizationId,
        protectionOnly: widget.protectionOnly,
      ),
    );
    if (created == true && mounted) {
      setState(() => _future = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.protectionOnly ? 'Защита растений' : 'Полив и агроработы'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Записать'),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text('Не удалось загрузить журнал: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          final rows = (snapshot.data ?? []).where(_isVisible).toList();
          if (rows.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 70),
                const Icon(Icons.event_note_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  widget.protectionOnly ? 'Обработок пока нет' : 'Записей пока нет',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Добавленные поливы, подкормки и другие работы будут отображаться здесь.',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => _future = next);
              await next;
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: rows.length,
              itemBuilder: (context, index) => _OperationCard(row: rows[index]),
            ),
          );
        },
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final type = _value(row['operation_type']);
    final batch = row['batches'] is Map ? row['batches'] as Map : const {};
    final crop = batch['crops'] is Map ? batch['crops'] as Map : const {};
    final greenhouse = batch['greenhouses'] is Map ? batch['greenhouses'] as Map : const {};
    final zone = batch['greenhouse_zones'] is Map ? batch['greenhouse_zones'] as Map : const {};
    final product = row['agricultural_products'] is Map
        ? row['agricultural_products'] as Map
        : const {};
    final safetyRaw = row['treatment_safety'];
    final safety = safetyRaw is List && safetyRaw.isNotEmpty
        ? safetyRaw.first as Map
        : safetyRaw is Map
            ? safetyRaw
            : null;
    final location = [
      _value(greenhouse['name']),
      _value(zone['name']),
    ].where((part) => part.isNotEmpty).join(' • ');
    final amount = row['quantity'] == null
        ? null
        : '${_value(row['quantity'])} ${_value(row['quantity_unit'])}';
    final water = row['water_volume'] == null
        ? null
        : 'Вода: ${_value(row['water_volume'])} ${_value(row['water_volume_unit'])}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _operationNames[type] ?? 'Агрономическая работа',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(_localDate(row['performed_at']), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text('${_value(crop['name']).isEmpty ? 'Культура' : _value(crop['name'])} • Партия ${_value(batch['batch_number'])}'),
            if (location.isNotEmpty) Text(location, style: Theme.of(context).textTheme.bodySmall),
            if (_value(product['name']).isNotEmpty) Text('Препарат: ${_value(product['name'])}'),
            if (amount != null) Text('Количество: $amount'),
            if (water != null) Text(water),
            if (_value(row['result']).isNotEmpty) Text('Результат: ${_value(row['result'])}'),
            if (_value(row['notes']).isNotEmpty) Text(_value(row['notes'])),
            if (safety != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Безопасность не подтверждена. Срок ожидания до сбора и повторного входа нужно проверить по официальной инструкции.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Text('Статус проверки: ${_value(safety['verification_status'])}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _OperationFormDialog extends StatefulWidget {
  const _OperationFormDialog({
    required this.organizationId,
    required this.protectionOnly,
  });

  final String organizationId;
  final bool protectionOnly;

  @override
  State<_OperationFormDialog> createState() => _OperationFormDialogState();
}

class _OperationFormDialogState extends State<_OperationFormDialog> {
  final _quantity = TextEditingController();
  final _waterVolume = TextEditingController();
  final _result = TextEditingController();
  final _notes = TextEditingController();
  late String _type;
  String? _batchId;
  String? _productId;
  String _quantityUnit = 'l';
  String _waterUnit = 'l';
  bool _busy = false;
  String? _error;
  late Future<void> _references;
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _products = [];

  bool get _needsProduct => const {
    'fertilizing', 'feeding', 'chemical_treatment', 'biological_treatment',
  }.contains(_type);

  String? get _requiredProductCategory => switch (_type) {
    'fertilizing' || 'feeding' => null,
    'chemical_treatment' => 'chemical_pesticide',
    'biological_treatment' => 'biological_protection',
    _ => null,
  };

  List<Map<String, dynamic>> get _availableProducts {
    if (_type == 'fertilizing' || _type == 'feeding') {
      return _products.where((p) => const {
        'chemical_fertilizer', 'biological_fertilizer',
      }.contains(_value(p['category']))).toList();
    }
    final category = _requiredProductCategory;
    if (category == null) return _products;
    return _products.where((p) => _value(p['category']) == category).toList();
  }

  @override
  void initState() {
    super.initState();
    _type = widget.protectionOnly ? 'chemical_treatment' : 'watering';
    _references = _loadReferences();
  }

  Future<void> _loadReferences() async {
    final db = Supabase.instance.client;
    final batches = await db.from('batches')
        .select('id,batch_number,crops(name)')
        .eq('organization_id', widget.organizationId)
        .neq('status', 'cancelled')
        .order('batch_number');
    final products = await db.from('agricultural_products')
        .select('id,name,category')
        .eq('organization_id', widget.organizationId)
        .order('name');
    if (!mounted) return;
    setState(() {
      _batches = batches.map((r) => Map<String, dynamic>.from(r)).toList();
      _products = products.map((r) => Map<String, dynamic>.from(r)).toList();
      if (_batches.isNotEmpty) _batchId = _value(_batches.first['id']);
      _syncProduct();
    });
  }

  void _syncProduct() {
    final available = _availableProducts;
    if (!available.any((p) => _value(p['id']) == _productId)) {
      _productId = available.isEmpty ? null : _value(available.first['id']);
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _waterVolume.dispose();
    _result.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_batchId == null) {
      setState(() => _error = 'Сначала создай партию растений.');
      return;
    }
    if (_needsProduct && _productId == null) {
      setState(() => _error = 'Для этой операции нужен подходящий препарат из справочника.');
      return;
    }
    final quantity = _quantity.text.trim().isEmpty ? null : double.tryParse(_quantity.text.replaceAll(',', '.'));
    final water = _waterVolume.text.trim().isEmpty ? null : double.tryParse(_waterVolume.text.replaceAll(',', '.'));
    if ((_quantity.text.trim().isNotEmpty && (quantity == null || quantity <= 0)) ||
        (_waterVolume.text.trim().isNotEmpty && (water == null || water <= 0))) {
      setState(() => _error = 'Проверь количество: нужно положительное число.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('create_agronomy_operation', params: {
        'p_organization_id': widget.organizationId,
        'p_batch_id': _batchId,
        'p_operation_type': _type,
        'p_performed_at': DateTime.now().toUtc().toIso8601String(),
        'p_product_id': _needsProduct ? _productId : null,
        'p_quantity': quantity,
        'p_quantity_unit': quantity == null ? null : _quantityUnit,
        'p_water_volume': water,
        'p_water_volume_unit': water == null ? null : _waterUnit,
        'p_result': _result.text.trim().isEmpty ? null : _result.text.trim(),
        'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сохранить запись. Проверь соединение.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая запись журнала'),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<void>(
          future: _references,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Text('Не удалось загрузить партии и препараты: ${snapshot.error}');
            }
            if (_batches.isEmpty) return const Text('Сначала создай хотя бы одну партию растений.');
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Тип работы'),
                    items: _operationNames.entries
                        .where((e) => !widget.protectionOnly || e.key == 'chemical_treatment' || e.key == 'biological_treatment')
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: _busy ? null : (value) => setState(() {
                      _type = value ?? 'watering';
                      _syncProduct();
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _batchId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Партия растений'),
                    items: _batches.map((b) {
                      final crop = b['crops'] is Map ? _value((b['crops'] as Map)['name']) : '';
                      return DropdownMenuItem(
                        value: _value(b['id']),
                        child: Text('${_value(b['batch_number'])} • $crop', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: _busy ? null : (value) => setState(() => _batchId = value),
                  ),
                  if (_needsProduct) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _productId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Препарат / удобрение'),
                      items: _availableProducts.map((p) => DropdownMenuItem(
                        value: _value(p['id']),
                        child: Text(_value(p['name']), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: _busy ? null : (value) => setState(() => _productId = value),
                    ),
                    if (_availableProducts.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Добавь подходящий препарат в разделе «Культуры и партии» → «Препараты».'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _quantity,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Количество (необязательно)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<String>(
                          initialValue: _quantityUnit,
                          decoration: const InputDecoration(labelText: 'Ед.'),
                          items: _quantityUnits.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                          onChanged: _busy ? null : (v) => setState(() => _quantityUnit = v ?? 'l'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _waterVolume,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Объём воды (необязательно)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<String>(
                          initialValue: _waterUnit,
                          decoration: const InputDecoration(labelText: 'Ед.'),
                          items: _volumeUnits.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                          onChanged: _busy ? null : (v) => setState(() => _waterUnit = v ?? 'l'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _result,
                    decoration: const InputDecoration(labelText: 'Результат / наблюдение'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Примечание'),
                    maxLines: 2,
                  ),
                  if (widget.protectionOnly || _type == 'chemical_treatment' || _type == 'biological_treatment')
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'После записи обработка получит статус «требует проверки». Сроки ожидания до сбора и повторного входа не рассчитываются автоматически — их нужно сверить с действующей официальной инструкцией.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy || _references is Future<void> && _batches.isEmpty ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
