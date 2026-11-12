import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _recordsDb = Supabase.instance.client;
List<Map<String, dynamic>> _recordRows(dynamic value) =>
    (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

class CustomersPage extends StatefulWidget {
  const CustomersPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _recordsDb.from('customers').select('id,name,phone,email,address,tax_id')
      .eq('organization_id', widget.organizationId).order('name');
    return _recordRows(rows);
  }
  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _create() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(), phone = TextEditingController(),
      email = TextEditingController(), address = TextEditingController(), tax = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Новый покупатель'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Имя / организация *'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи имя покупателя' : null),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Телефон')),
        TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Электронная почта')),
        TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Адрес')),
        TextFormField(controller: tax, decoration: const InputDecoration(labelText: 'ИНН (необязательно)')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Сохранить')),
      ],
    ));
    if (ok != true) { name.dispose(); phone.dispose(); email.dispose(); address.dispose(); tax.dispose(); return; }
    try {
      await _recordsDb.from('customers').insert({
        'organization_id': widget.organizationId, 'name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'email': email.text.trim().isEmpty ? null : email.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'tax_id': tax.text.trim().isEmpty ? null : tax.text.trim(),
      });
      await _refresh();
      if (mounted) _notice('Покупатель добавлен');
    } catch (e) { if (mounted) _notice('Не удалось добавить покупателя: $e', error: true); }
    finally { name.dispose(); phone.dispose(); email.dispose(); address.dispose(); tax.dispose(); }
  }

  void _notice(String value, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _RecordLoadError(error: snap.error.toString(), retry: _refresh);
    final rows = snap.data ?? [];
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.person_add_alt_1), label: const Text('Добавить покупателя')))),
      Expanded(child: rows.isEmpty ? const Center(child: Text('Покупателей пока нет'))
        : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: rows.length, itemBuilder: (context, i) {
            final e = rows[i];
            return Card(child: ListTile(leading: const Icon(Icons.person_outline),
              title: Text(e['name'].toString()),
              subtitle: Text([e['phone'], e['email'], e['address']].where((v) => v != null && v.toString().isNotEmpty).join(' • '))));
          }))),
    ]);
  });
}

const _expenseCategories = <String, String>{
  'seeds': 'Семена', 'fertilizers': 'Удобрения', 'plant_protection': 'Защита растений',
  'utilities': 'Коммунальные услуги', 'rent': 'Аренда', 'transport': 'Транспорт',
  'repairs': 'Ремонт', 'payroll': 'Зарплата', 'packaging': 'Упаковка', 'other': 'Прочее',
};

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _recordsDb.from('expenses').select('id,expense_date,category,description,amount,currency,document_number')
      .eq('organization_id', widget.organizationId).order('expense_date', ascending: false).limit(200);
    return _recordRows(rows);
  }
  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _create() async {
    final form = GlobalKey<FormState>();
    final description = TextEditingController(), amount = TextEditingController(), document = TextEditingController(), notes = TextEditingController();
    String category = 'other';
    final ok = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: const Text('Новый расход'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Категория'),
          items: _expenseCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setDialog(() => category = v ?? category)),
        const SizedBox(height: 10),
        TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Описание *'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи описание' : null),
        const SizedBox(height: 10),
        TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Сумма, ₽ *'),
          validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) < 0 ? 'Укажи сумму не меньше нуля' : null),
        const SizedBox(height: 10),
        TextFormField(controller: document, decoration: const InputDecoration(labelText: 'Номер документа')),
        const SizedBox(height: 10),
        TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Примечание')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Записать расход')),
      ],
    )));
    if (ok != true) { description.dispose(); amount.dispose(); document.dispose(); notes.dispose(); return; }
    try {
      await _recordsDb.rpc('record_expense', params: {
        'p_organization_id': widget.organizationId,
        'p_expense_date': DateTime.now().toIso8601String().substring(0, 10),
        'p_category': category, 'p_description': description.text.trim(),
        'p_amount': double.parse(amount.text.replaceAll(',', '.')),
        'p_document_number': document.text.trim().isEmpty ? null : document.text.trim(),
        'p_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
      await _refresh();
      if (mounted) _notice('Расход записан');
    } catch (e) { if (mounted) _notice('Не удалось записать расход: $e', error: true); }
    finally { description.dispose(); amount.dispose(); document.dispose(); notes.dispose(); }
  }

  void _notice(String value, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _RecordLoadError(error: snap.error.toString(), retry: _refresh);
    final rows = snap.data ?? [];
    final total = rows.fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Учтённые расходы'), trailing: Text('${total.toStringAsFixed(2)} ₽', style: Theme.of(context).textTheme.titleMedium))),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Добавить расход'))),
      ])),
      Expanded(child: rows.isEmpty ? const Center(child: Text('Расходов пока нет'))
        : RefreshIndicator(onRefresh: _refresh, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: rows.length, itemBuilder: (context, i) {
            final e = rows[i];
            return Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined),
              title: Text(e['description'].toString()),
              subtitle: Text('${_expenseCategories[e['category']] ?? e['category']} • ${e['expense_date']}'),
              trailing: Text('${(e['amount'] as num).toStringAsFixed(2)} ₽', style: const TextStyle(fontWeight: FontWeight.w700))));
          }))),
    ]);
  });
}

class _RecordLoadError extends StatelessWidget {
  const _RecordLoadError({required this.error, required this.retry});
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
