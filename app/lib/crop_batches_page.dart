import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const cropKinds = <String, String>{
  'vegetable': 'Овощные', 'flower': 'Цветочные', 'seedling': 'Рассада',
  'greens': 'Зелень', 'berry': 'Ягодные', 'other': 'Другие',
};
const batchStates = <String, String>{
  'planned': 'Запланирована', 'growing': 'Растёт',
  'harvesting': 'Сбор урожая', 'finished': 'Завершена', 'cancelled': 'Отменена',
};
const productKinds = <String, String>{
  'chemical_fertilizer': 'Химическое удобрение',
  'biological_fertilizer': 'Биологическое удобрение',
  'chemical_pesticide': 'Химическое средство защиты',
  'biological_protection': 'Биологическая защита', 'other': 'Другое',
};

String s(dynamic v) => v?.toString() ?? '';
String dateText(dynamic value) {
  final raw = s(value);
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? (raw.isEmpty ? '—' : raw) :
    '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}';
}
void msg(BuildContext context, String value) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}
String lookup(List<Map<String, dynamic>> list, dynamic id) {
  for (final row in list) {
    if (s(row['id']) == s(id)) return s(row['name']);
  }
  return '';
}

class CropBatchesPage extends StatelessWidget {
  const CropBatchesPage({required this.organizationId, required this.canManage, super.key});
  final String organizationId;
  final bool canManage;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Культуры и партии'),
        bottom: const TabBar(isScrollable: true, tabs: [
          Tab(icon: Icon(Icons.grass_outlined), text: 'Культуры и сорта'),
          Tab(icon: Icon(Icons.spa_outlined), text: 'Партии'),
          Tab(icon: Icon(Icons.science_outlined), text: 'Препараты'),
        ]),
      ),
      body: TabBarView(children: [
        _Crops(org: organizationId, manage: canManage),
        _Batches(org: organizationId, manage: canManage),
        _Products(org: organizationId, manage: canManage),
      ]),
    ),
  );
}

class _Crops extends StatefulWidget {
  const _Crops({required this.org, required this.manage});
  final String org;
  final bool manage;
  @override
  State<_Crops> createState() => _CropsState();
}
class _CropsState extends State<_Crops> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() { super.initState(); future = load(); }

  Future<List<Map<String, dynamic>>> load() async {
    final db = Supabase.instance.client;
    final crops = await db.from('crops').select('id,name,category,notes')
      .eq('organization_id', widget.org).eq('active', true).order('name');
    final varieties = await db.from('crop_varieties').select('id,crop_id,name,supplier')
      .eq('organization_id', widget.org).order('name');
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in varieties) {
      final v = Map<String, dynamic>.from(item);
      grouped.putIfAbsent(s(v['crop_id']), () => []).add(v);
    }
    return crops.map((item) {
      final c = Map<String, dynamic>.from(item);
      c['varieties'] = grouped[s(c['id'])] ?? [];
      return c;
    }).toList();
  }
  Future<void> refresh() async { setState(() => future = load()); await future; }

  Future<void> addCrop() async {
    final draft = await showDialog<Map<String, String>>(context: context, builder: (_) => const _CropForm());
    if (draft == null || !mounted) return;
    try {
      await Supabase.instance.client.from('crops').insert({
        'organization_id': widget.org, 'name': draft['name'], 'category': draft['category'],
      });
      if (mounted) { setState(() => future = load()); msg(context, 'Культура добавлена.'); }
    } on PostgrestException catch (e) {
      if (mounted) msg(context, 'Ошибка: ${e.message}');
    } catch (_) { if (mounted) msg(context, 'Не удалось сохранить. Проверь соединение.'); }
  }
  Future<void> addVariety(String cropId, String cropName) async {
    final draft = await showDialog<Map<String, String>>(context: context,
      builder: (_) => _VarietyForm(cropName: cropName));
    if (draft == null || !mounted) return;
    try {
      await Supabase.instance.client.from('crop_varieties').insert({
        'organization_id': widget.org, 'crop_id': cropId,
        'name': draft['name'], 'supplier': draft['supplier'],
      });
      if (mounted) { setState(() => future = load()); msg(context, 'Сорт добавлен.'); }
    } on PostgrestException catch (e) {
      if (mounted) msg(context, 'Ошибка: ${e.message}');
    } catch (_) { if (mounted) msg(context, 'Не удалось сохранить сорт.'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: widget.manage ? FloatingActionButton.extended(
      onPressed: addCrop, icon: const Icon(Icons.add), label: const Text('Добавить культуру'),
    ) : null,
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) { return const Center(child: CircularProgressIndicator()); }
        if (snap.hasError) { return _Retry(message: 'Не удалось загрузить культуры: ${snap.error}',
          retry: () => setState(() => future = load())); }
        final rows = snap.data ?? [];
        if (rows.isEmpty) return RefreshIndicator(onRefresh: refresh, child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(24),
          children: const [SizedBox(height: 70), Icon(Icons.grass_outlined, size: 56),
            SizedBox(height: 12), Text('Список культур пуст', textAlign: TextAlign.center),
            SizedBox(height: 8), Text('Добавь культуру, затем укажи её сорта.', textAlign: TextAlign.center)],
        ));
        return RefreshIndicator(onRefresh: refresh, child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: rows.map((c) => Card(child: ExpansionTile(
            leading: const Icon(Icons.eco_outlined), title: Text(s(c['name'])),
            subtitle: Text(cropKinds[s(c['category'])] ?? 'Другая культура'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final v in (c['varieties'] as List<Map<String, dynamic>>))
                ListTile(dense: true, contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sell_outlined), title: Text(s(v['name'])),
                  subtitle: s(v['supplier']).isEmpty ? null : Text('Поставщик: ${s(v['supplier'])}')),
              if ((c['varieties'] as List).isEmpty)
                const Align(alignment: Alignment.centerLeft, child: Text('Сорта не добавлены.')),
              if (widget.manage) Align(alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => addVariety(s(c['id']), s(c['name'])),
                  icon: const Icon(Icons.add), label: const Text('Добавить сорт'),
                )),
            ],
          ))).toList(),
        ));
      },
    ),
  );
}

class _CropForm extends StatefulWidget {
  const _CropForm();
  @override
  State<_CropForm> createState() => _CropFormState();
}
class _CropFormState extends State<_CropForm> {
  final name = TextEditingController();
  String category = 'vegetable';
  @override
  void dispose() { name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая культура'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, maxLength: 120,
        decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(initialValue: category,
        decoration: const InputDecoration(labelText: 'Категория', border: OutlineInputBorder()),
        items: cropKinds.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) setState(() => category = v); }),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () {
        if (name.text.trim().isNotEmpty) Navigator.pop(context, {'name': name.text.trim(), 'category': category});
      }, child: const Text('Сохранить')),
    ],
  );
}
class _VarietyForm extends StatefulWidget {
  const _VarietyForm({required this.cropName});
  final String cropName;
  @override
  State<_VarietyForm> createState() => _VarietyFormState();
}
class _VarietyFormState extends State<_VarietyForm> {
  final name = TextEditingController();
  final supplier = TextEditingController();
  @override
  void dispose() { name.dispose(); supplier.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Новый сорт: ${widget.cropName}'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Название сорта')),
      TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Поставщик семян')),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () {
        if (name.text.trim().isNotEmpty) { Navigator.pop(context, {
          'name': name.text.trim(), 'supplier': supplier.text.trim(),
        }); }
      }, child: const Text('Сохранить')),
    ],
  );
}

class _BatchData {
  const _BatchData(this.crops, this.varieties, this.greenhouses, this.zones, this.batches);
  final List<Map<String, dynamic>> crops, varieties, greenhouses, zones, batches;
}
class _Batches extends StatefulWidget {
  const _Batches({required this.org, required this.manage});
  final String org;
  final bool manage;
  @override
  State<_Batches> createState() => _BatchesState();
}
class _BatchesState extends State<_Batches> {
  late Future<_BatchData> future;
  @override
  void initState() { super.initState(); future = load(); }
  Future<_BatchData> load() async {
    final db = Supabase.instance.client;
    final r = await Future.wait([
      db.from('crops').select('id,name').eq('organization_id', widget.org).eq('active', true).order('name'),
      db.from('crop_varieties').select('id,crop_id,name').eq('organization_id', widget.org).order('name'),
      db.from('greenhouses').select('id,name').eq('organization_id', widget.org).eq('active', true).order('name'),
      db.from('greenhouse_zones').select('id,greenhouse_id,name').eq('organization_id', widget.org).eq('active', true).order('name'),
      db.from('batches').select('id,batch_number,greenhouse_id,zone_id,crop_id,variety_id,sowing_date,planting_date,planned_harvest_date,quantity_planted,quantity_unit,status,notes').eq('organization_id', widget.org).order('created_at', ascending: false),
    ]);
    List<Map<String, dynamic>> map(dynamic rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList();
    return _BatchData(map(r[0]), map(r[1]), map(r[2]), map(r[3]), map(r[4]));
  }
  Future<void> refresh() async { setState(() => future = load()); await future; }

  Future<void> add(_BatchData data) async {
    if (data.crops.isEmpty || data.greenhouses.isEmpty) {
      msg(context, 'Сначала добавь культуру и теплицу.'); return;
    }
    final draft = await showDialog<Map<String, dynamic>>(
      context: context, builder: (_) => _BatchForm(data: data));
    if (draft == null || !mounted) return;
    try {
      await Supabase.instance.client.from('batches').insert({
        'organization_id': widget.org, ...draft,
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });
      if (mounted) { setState(() => future = load()); msg(context, 'Партия создана.'); }
    } on PostgrestException catch (e) {
      if (mounted) msg(context, 'Не удалось создать партию: ${e.message}');
    } catch (_) { if (mounted) msg(context, 'Не удалось создать партию.'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: widget.manage ? FloatingActionButton.extended(
      onPressed: () async { final d = await future; if (mounted) await add(d); },
      icon: const Icon(Icons.add), label: const Text('Новая партия'),
    ) : null,
    body: FutureBuilder<_BatchData>(future: future, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) { return const Center(child: CircularProgressIndicator()); }
      if (snap.hasError) { return _Retry(message: 'Не удалось загрузить партии: ${snap.error}',
        retry: () => setState(() => future = load())); }
      final d = snap.data!;
      if (d.batches.isEmpty) return RefreshIndicator(onRefresh: refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(24),
          children: const [SizedBox(height: 70), Icon(Icons.spa_outlined, size: 56),
            SizedBox(height: 12), Text('Партий пока нет', textAlign: TextAlign.center),
            SizedBox(height: 8), Text('Создай партию после добавления культуры и теплицы.', textAlign: TextAlign.center)],
        ));
      return RefreshIndicator(onRefresh: refresh, child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: d.batches.map((b) {
          final crop = lookup(d.crops, b['crop_id']);
          final greenhouse = lookup(d.greenhouses, b['greenhouse_id']);
          final variety = lookup(d.varieties, b['variety_id']);
          final zone = lookup(d.zones, b['zone_id']);
          return Card(child: ExpansionTile(
            leading: const Icon(Icons.qr_code_2_outlined),
            title: Text('Партия ${s(b['batch_number'])}'),
            subtitle: Text('$crop • ${batchStates[s(b['status'])] ?? s(b['status'])}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              _Info('Сорт', variety.isEmpty ? '—' : variety),
              _Info('Теплица', greenhouse.isEmpty ? '—' : greenhouse),
              _Info('Зона', zone.isEmpty ? '—' : zone),
              _Info('Посев', dateText(b['sowing_date'])),
              _Info('Высадка', dateText(b['planting_date'])),
              _Info('Плановый сбор', dateText(b['planned_harvest_date'])),
              _Info('Количество', b['quantity_planted'] == null ? '—' : '${s(b['quantity_planted'])} ${s(b['quantity_unit'])}'),
              if (s(b['notes']).isNotEmpty) _Info('Примечание', s(b['notes'])),
            ],
          ));
        }).toList(),
      ));
    }),
  );
}
class _BatchForm extends StatefulWidget {
  const _BatchForm({required this.data});
  final _BatchData data;
  @override
  State<_BatchForm> createState() => _BatchFormState();
}
class _BatchFormState extends State<_BatchForm> {
  final number = TextEditingController(), qty = TextEditingController(), notes = TextEditingController();
  String? cropId, greenhouseId;
  String varietyId = '', zoneId = '', unit = 'pcs';
  DateTime? sowing, planting, harvest;
  @override
  void initState() {
    super.initState();
    if (widget.data.crops.isNotEmpty) cropId = s(widget.data.crops.first['id']);
    if (widget.data.greenhouses.isNotEmpty) greenhouseId = s(widget.data.greenhouses.first['id']);
  }
  @override
  void dispose() { number.dispose(); qty.dispose(); notes.dispose(); super.dispose(); }
  List<Map<String, dynamic>> get varieties => widget.data.varieties.where((v) => s(v['crop_id']) == cropId).toList();
  List<Map<String, dynamic>> get zones => widget.data.zones.where((z) => s(z['greenhouse_id']) == greenhouseId).toList();
  Future<void> pick(String key) async {
    final current = key == 's' ? sowing : key == 'p' ? planting : harvest;
    final value = await showDatePicker(context: context, initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (value != null) setState(() { if (key == 's') sowing = value; if (key == 'p') planting = value; if (key == 'h') harvest = value; });
  }
  String iso(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);
  void save() {
    if (number.text.trim().isEmpty || cropId == null || greenhouseId == null) return;
    final q = qty.text.trim().replaceAll(',', '.');
    final n = q.isEmpty ? null : double.tryParse(q);
    if (q.isNotEmpty && (n == null || n < 0)) return;
    Navigator.pop(context, {
      'batch_number': number.text.trim(), 'crop_id': cropId, 'greenhouse_id': greenhouseId,
      'variety_id': varietyId.isEmpty ? null : varietyId, 'zone_id': zoneId.isEmpty ? null : zoneId,
      'sowing_date': sowing == null ? null : iso(sowing),
      'planting_date': planting == null ? null : iso(planting),
      'planned_harvest_date': harvest == null ? null : iso(harvest),
      'quantity_planted': n, 'quantity_unit': unit, 'status': 'planned',
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
    });
  }
  Widget dateButton(String label, DateTime? value, String key) => OutlinedButton(
    onPressed: () => pick(key),
    child: Text('$label: ${value == null ? '—' : dateText(value.toIso8601String())}'),
  );
  @override
  Widget build(BuildContext context) {
    final vs = varieties, zs = zones;
    if (!vs.any((v) => s(v['id']) == varietyId)) varietyId = '';
    if (!zs.any((z) => s(z['id']) == zoneId)) zoneId = '';
    return AlertDialog(
      title: const Text('Новая партия'),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: number, decoration: const InputDecoration(labelText: 'Номер партии *')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: cropId, decoration: const InputDecoration(labelText: 'Культура *'),
          items: widget.data.crops.map((e) => DropdownMenuItem(value: s(e['id']), child: Text(s(e['name'])))).toList(),
          onChanged: (v) => setState(() { cropId = v; varietyId = ''; })),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: varietyId, decoration: const InputDecoration(labelText: 'Сорт'),
          items: [const DropdownMenuItem(value: '', child: Text('Не указан')),
            ...vs.map((e) => DropdownMenuItem(value: s(e['id']), child: Text(s(e['name']))))],
          onChanged: (v) => setState(() => varietyId = v ?? '')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: greenhouseId, decoration: const InputDecoration(labelText: 'Теплица *'),
          items: widget.data.greenhouses.map((e) => DropdownMenuItem(value: s(e['id']), child: Text(s(e['name'])))).toList(),
          onChanged: (v) => setState(() { greenhouseId = v; zoneId = ''; })),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: zoneId, decoration: const InputDecoration(labelText: 'Зона'),
          items: [const DropdownMenuItem(value: '', child: Text('Без зоны')),
            ...zs.map((e) => DropdownMenuItem(value: s(e['id']), child: Text(s(e['name']))))],
          onChanged: (v) => setState(() => zoneId = v ?? '')),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          dateButton('Посев', sowing, 's'), dateButton('Высадка', planting, 'p'), dateButton('Сбор', harvest, 'h'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Количество'))),
          const SizedBox(width: 8),
          DropdownButton<String>(value: unit, items: const [
            DropdownMenuItem(value: 'pcs', child: Text('шт')),
            DropdownMenuItem(value: 'kg', child: Text('кг')),
            DropdownMenuItem(value: 'g', child: Text('г')),
            DropdownMenuItem(value: 'l', child: Text('л')),
            DropdownMenuItem(value: 'm2', child: Text('м²')),
          ], onChanged: (v) { if (v != null) setState(() => unit = v); }),
        ]),
        TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Примечание')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: save, child: const Text('Создать')),
      ],
    );
  }
}

class _Products extends StatefulWidget {
  const _Products({required this.org, required this.manage});
  final String org;
  final bool manage;
  @override
  State<_Products> createState() => _ProductsState();
}
class _ProductsState extends State<_Products> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() { super.initState(); future = load(); }
  Future<List<Map<String, dynamic>>> load() async {
    final rows = await Supabase.instance.client.from('agricultural_products')
      .select('id,name,category,manufacturer,active_ingredient,registration_number,registration_valid_until,safety_instructions')
      .eq('organization_id', widget.org).order('name');
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }
  Future<void> add() async {
    final draft = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _ProductForm());
    if (draft == null || !mounted) return;
    try {
      await Supabase.instance.client.from('agricultural_products').insert({'organization_id': widget.org, ...draft});
      if (mounted) { setState(() => future = load()); msg(context, 'Запись добавлена в каталог.'); }
    } on PostgrestException catch (e) { if (mounted) msg(context, 'Ошибка: ${e.message}'); }
    catch (_) { if (mounted) msg(context, 'Не удалось сохранить запись.'); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: widget.manage ? FloatingActionButton.extended(
      onPressed: add, icon: const Icon(Icons.add), label: const Text('Добавить средство'),
    ) : null,
    body: FutureBuilder<List<Map<String, dynamic>>>(future: future, builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) { return _Retry(message: 'Не удалось загрузить каталог: ${snap.error}',
        retry: () => setState(() => future = load())); }
      final rows = snap.data ?? [];
      if (rows.isEmpty) return const Center(child: Padding(
        padding: EdgeInsets.all(24), child: Text('Каталог пуст. Здесь хранятся сведения о препаратах и удобрениях.'),
      ));
      return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        const Card(child: Padding(padding: EdgeInsets.all(12), child: Text(
          'Справочник хозяйства не подтверждает регистрацию средства и не заменяет действующую официальную инструкцию РФ. Дозировки и сроки безопасности здесь не рассчитываются.',
        ))),
        for (final p in rows) Card(child: ExpansionTile(
          leading: const Icon(Icons.science_outlined), title: Text(s(p['name'])),
          subtitle: Text(productKinds[s(p['category'])] ?? 'Другое'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            _Info('Производитель', s(p['manufacturer']).isEmpty ? '—' : s(p['manufacturer'])),
            _Info('Действующее вещество', s(p['active_ingredient']).isEmpty ? '—' : s(p['active_ingredient'])),
            _Info('Регистрационный номер', s(p['registration_number']).isEmpty ? '—' : s(p['registration_number'])),
            _Info('Регистрация до', dateText(p['registration_valid_until'])),
            if (s(p['safety_instructions']).isNotEmpty) _Info('Примечание', s(p['safety_instructions'])),
          ],
        )),
      ]);
    }),
  );
}
class _ProductForm extends StatefulWidget {
  const _ProductForm();
  @override
  State<_ProductForm> createState() => _ProductFormState();
}
class _ProductFormState extends State<_ProductForm> {
  final name = TextEditingController(), manufacturer = TextEditingController(),
    ingredient = TextEditingController(), registration = TextEditingController(),
    validUntil = TextEditingController(), note = TextEditingController();
  String category = 'chemical_fertilizer';
  @override
  void dispose() {
    name.dispose(); manufacturer.dispose(); ingredient.dispose(); registration.dispose();
    validUntil.dispose(); note.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новое средство'),
    content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Название *')),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Тип средства'),
        items: productKinds.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) setState(() => category = v); }),
      TextField(controller: manufacturer, decoration: const InputDecoration(labelText: 'Производитель')),
      TextField(controller: ingredient, decoration: const InputDecoration(labelText: 'Действующее вещество')),
      TextField(controller: registration, decoration: const InputDecoration(labelText: 'Регистрационный номер РФ')),
      TextField(controller: validUntil, decoration: const InputDecoration(labelText: 'Регистрация до (ГГГГ-ММ-ДД)')),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Примечание / источник инструкции')),
      const SizedBox(height: 8),
      const Text('Не указывай неподтверждённые нормы, дозировки или сроки ожидания.', style: TextStyle(fontSize: 12)),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () {
        final valid = validUntil.text.trim();
        if (name.text.trim().isEmpty || (valid.isNotEmpty && DateTime.tryParse(valid) == null)) return;
        Navigator.pop(context, {
          'name': name.text.trim(), 'category': category,
          'manufacturer': manufacturer.text.trim().isEmpty ? null : manufacturer.text.trim(),
          'active_ingredient': ingredient.text.trim().isEmpty ? null : ingredient.text.trim(),
          'registration_country': registration.text.trim().isEmpty ? null : 'RU',
          'registration_number': registration.text.trim().isEmpty ? null : registration.text.trim(),
          'registration_valid_until': valid.isEmpty ? null : valid,
          'safety_instructions': note.text.trim().isEmpty ? null : note.text.trim(),
        });
      }, child: const Text('Сохранить')),
    ],
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 128, child: Text(label, style: const TextStyle(color: Colors.black54))),
      Expanded(child: Text(value)),
    ]),
  );
}
class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 42), const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center), const SizedBox(height: 12),
      FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
    ]),
  ));
}
