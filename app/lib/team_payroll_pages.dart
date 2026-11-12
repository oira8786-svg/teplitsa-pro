import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _teamDb = Supabase.instance.client;
List<Map<String, dynamic>> _teamRows(dynamic v) => (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

class TeamTasksPage extends StatefulWidget {
  const TeamTasksPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<TeamTasksPage> createState() => _TeamTasksPageState();
}

class _TeamTasksPageState extends State<TeamTasksPage> {
  late Future<List<dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<dynamic>> _load() async => Future.wait([
    _teamDb.from('employee_profiles').select('id,user_id,full_name,phone,job_title,employment_status')
      .eq('organization_id', widget.organizationId).order('full_name'),
    _teamDb.from('tasks').select('id,title,description,status,priority,due_at,assigned_employee_id,assigned_user_id')
      .eq('organization_id', widget.organizationId).order('created_at', ascending: false).limit(200),
    _teamDb.from('batches').select('id,batch_number').eq('organization_id', widget.organizationId)
      .inFilter('status', ['planned','growing','harvesting']).order('batch_number'),
  ]);
  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _addEmployee() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(), job = TextEditingController(), phone = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Новый сотрудник'),
      content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'ФИО *'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи ФИО' : null),
        TextFormField(controller: job, decoration: const InputDecoration(labelText: 'Должность')),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Телефон')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Добавить')),
      ],
    ));
    if (ok != true) { name.dispose(); job.dispose(); phone.dispose(); return; }
    try {
      await _teamDb.from('employee_profiles').insert({
        'organization_id': widget.organizationId, 'full_name': name.text.trim(),
        'job_title': job.text.trim().isEmpty ? null : job.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'employment_status': 'active',
      });
      await _refresh();
      if (mounted) _notice('Сотрудник добавлен');
    } catch (e) { if (mounted) _notice('Не удалось добавить сотрудника: $e', error: true); }
    finally { name.dispose(); job.dispose(); phone.dispose(); }
  }

  Future<void> _addTask(List<Map<String, dynamic>> employees, List<Map<String, dynamic>> batches) async {
    final form = GlobalKey<FormState>();
    final title = TextEditingController(), description = TextEditingController();
    String priority = 'normal';
    String? employeeId, batchId;
    final active = employees.where((e) => e['employment_status'] == 'active').toList();
    final ok = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: const Text('Новая задача'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Задача *'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажи задачу' : null),
        const SizedBox(height: 10),
        TextFormField(controller: description, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Описание')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: priority, decoration: const InputDecoration(labelText: 'Приоритет'),
          items: const [DropdownMenuItem(value: 'low', child: Text('Низкий')), DropdownMenuItem(value: 'normal', child: Text('Обычный')),
            DropdownMenuItem(value: 'high', child: Text('Высокий')), DropdownMenuItem(value: 'urgent', child: Text('Срочно'))],
          onChanged: (v) => setDialog(() => priority = v ?? priority)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(initialValue: employeeId, decoration: const InputDecoration(labelText: 'Ответственный'),
          items: [const DropdownMenuItem<String?>(value: null, child: Text('Не назначен')),
            ...active.map((e) => DropdownMenuItem<String?>(value: e['id'].toString(), child: Text(e['full_name'].toString(), overflow: TextOverflow.ellipsis)))],
          onChanged: (v) => setDialog(() => employeeId = v)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(initialValue: batchId, decoration: const InputDecoration(labelText: 'Партия (необязательно)'),
          items: [const DropdownMenuItem<String?>(value: null, child: Text('Без привязки')),
            ...batches.map((e) => DropdownMenuItem<String?>(value: e['id'].toString(), child: Text(e['batch_number'].toString())))],
          onChanged: (v) => setDialog(() => batchId = v)),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Создать задачу')),
      ],
    )));
    if (ok != true) { title.dispose(); description.dispose(); return; }
    try {
      final employee = employeeId == null ? null : active.firstWhere((e) => e['id'].toString() == employeeId);
      await _teamDb.rpc('create_task', params: {
        'p_organization_id': widget.organizationId,
        'p_title': title.text.trim(),
        'p_description': description.text.trim().isEmpty ? null : description.text.trim(),
        'p_greenhouse_id': null,
        'p_batch_id': batchId,
        'p_assigned_user_id': employee?['user_id'],
        'p_assigned_employee_id': employeeId,
        'p_priority': priority,
        'p_due_at': null,
      });
      await _refresh();
      if (mounted) _notice('Задача создана');
    } catch (e) { if (mounted) _notice('Не удалось создать задачу: $e', error: true); }
    finally { title.dispose(); description.dispose(); }
  }

  Future<void> _changeStatus(Map<String, dynamic> task, String status) async {
    try {
      await _teamDb.rpc('update_task_status', params: {
        'p_organization_id': widget.organizationId, 'p_task_id': task['id'],
        'p_status': status, 'p_completion_note': null,
      });
      await _refresh();
      if (mounted) _notice('Статус задачи обновлён');
    } catch (e) { if (mounted) _notice('Не удалось обновить задачу: $e', error: true); }
  }

  void _notice(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _TeamError(error: snap.error.toString(), retry: _refresh);
    final employees = _teamRows(snap.data![0]), tasks = _teamRows(snap.data![1]), batches = _teamRows(snap.data![2]);
    final employeeNames = {for (final e in employees) e['id'].toString(): e['full_name'].toString()};
    return RefreshIndicator(onRefresh: _refresh, child: ListView(physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _addEmployee, icon: const Icon(Icons.person_add_alt_1), label: const Text('Сотрудник')),
          OutlinedButton.icon(onPressed: () => _addTask(employees, batches), icon: const Icon(Icons.add_task), label: const Text('Новая задача')),
        ]),
        const SizedBox(height: 12),
        Text('Сотрудники • ${employees.length}', style: Theme.of(context).textTheme.titleLarge),
        if (employees.isEmpty) const ListTile(title: Text('Сотрудников пока нет')),
        for (final e in employees) Card(child: ListTile(leading: const Icon(Icons.person_outline),
          title: Text(e['full_name'].toString()), subtitle: Text('${e['job_title'] ?? 'Должность не указана'} • ${e['employment_status']}'))),
        const SizedBox(height: 16),
        Text('Задачи • ${tasks.length}', style: Theme.of(context).textTheme.titleLarge),
        if (tasks.isEmpty) const ListTile(title: Text('Задач пока нет')),
        for (final t in tasks) Card(child: ListTile(
          leading: Icon(t['status'] == 'done' ? Icons.task_alt : Icons.assignment_outlined),
          title: Text(t['title'].toString()),
          subtitle: Text('${t['status']} • ${t['priority']} • ${employeeNames[t['assigned_employee_id']] ?? 'Без ответственного'}'),
          trailing: PopupMenuButton<String>(tooltip: 'Изменить статус', onSelected: (v) => _changeStatus(t, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'open', child: Text('Открыта')),
              PopupMenuItem(value: 'in_progress', child: Text('В работе')),
              PopupMenuItem(value: 'done', child: Text('Выполнена')),
              PopupMenuItem(value: 'cancelled', child: Text('Отменена')),
            ]),
        )),
      ]));
  });
}

class PayrollPage extends StatefulWidget {
  const PayrollPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late Future<List<dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<dynamic>> _load() async => Future.wait([
    _teamDb.from('employee_profiles').select('id,full_name,employment_status')
      .eq('organization_id', widget.organizationId).order('full_name'),
    _teamDb.from('payroll_accruals').select('id,employee_id,period_start,period_end,accrual_type,amount,currency,description')
      .eq('organization_id', widget.organizationId).order('period_start', ascending: false).limit(200),
    _teamDb.from('payroll_payments').select('accrual_id,amount')
      .eq('organization_id', widget.organizationId),
  ]);
  Future<void> _refresh() async { final next = _load(); setState(() => _future = next); await next; }

  Future<void> _addAccrual(List<Map<String, dynamic>> employees) async {
    if (employees.isEmpty) { _notice('Сначала добавь сотрудника.', error: true); return; }
    final form = GlobalKey<FormState>();
    final amount = TextEditingController(), description = TextEditingController();
    String employeeId = employees.first['id'].toString(), type = 'salary';
    final now = DateTime.now(), first = DateTime(now.year, now.month, 1), last = DateTime(now.year, now.month + 1, 0);
    final ok = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: const Text('Начисление зарплаты'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: employeeId, decoration: const InputDecoration(labelText: 'Сотрудник'),
          items: employees.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['full_name'].toString()))).toList(),
          onChanged: (v) => setDialog(() => employeeId = v ?? employeeId)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Тип начисления'),
          items: const [DropdownMenuItem(value: 'salary', child: Text('Оклад')), DropdownMenuItem(value: 'hourly', child: Text('Почасовая оплата')),
            DropdownMenuItem(value: 'piecework', child: Text('Сдельная оплата')), DropdownMenuItem(value: 'bonus', child: Text('Премия')),
            DropdownMenuItem(value: 'allowance', child: Text('Надбавка')), DropdownMenuItem(value: 'deduction', child: Text('Удержание')),
            DropdownMenuItem(value: 'other', child: Text('Другое'))],
          onChanged: (v) => setDialog(() => type = v ?? type)),
        const SizedBox(height: 10),
        TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Сумма, ₽'),
          validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) < 0 ? 'Укажи сумму не меньше нуля' : null),
        const SizedBox(height: 10),
        TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Описание')),
        const SizedBox(height: 8),
        Text('Период: ${first.day.toString().padLeft(2,'0')}.${first.month.toString().padLeft(2,'0')}.${first.year} — ${last.day.toString().padLeft(2,'0')}.${last.month.toString().padLeft(2,'0')}.${last.year}'),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Начислить')),
      ],
    )));
    if (ok != true) { amount.dispose(); description.dispose(); return; }
    try {
      await _teamDb.rpc('create_payroll_accrual', params: {
        'p_organization_id': widget.organizationId, 'p_employee_id': employeeId,
        'p_period_start': first.toIso8601String().substring(0,10),
        'p_period_end': last.toIso8601String().substring(0,10),
        'p_accrual_type': type, 'p_amount': double.parse(amount.text.replaceAll(',', '.')),
        'p_description': description.text.trim().isEmpty ? null : description.text.trim(),
      });
      await _refresh();
      if (mounted) _notice('Начисление записано');
    } catch (e) { if (mounted) _notice('Не удалось записать начисление: $e', error: true); }
    finally { amount.dispose(); description.dispose(); }
  }

  Future<void> _pay(Map<String, dynamic> accrual, double due) async {
    final amount = TextEditingController(text: due.toStringAsFixed(2));
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Выплата зарплаты'),
      content: Form(key: form, child: TextFormField(controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Сумма, ₽'),
        validator: (v) { final n = double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0; return n <= 0 || n > due ? 'Сумма должна быть от 0 до ${due.toStringAsFixed(2)}' : null; })),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Записать выплату')),
      ],
    ));
    if (ok != true) { amount.dispose(); return; }
    try {
      await _teamDb.rpc('record_payroll_payment', params: {
        'p_organization_id': widget.organizationId, 'p_accrual_id': accrual['id'],
        'p_amount': double.parse(amount.text.replaceAll(',', '.')),
        'p_paid_at': DateTime.now().toUtc().toIso8601String(), 'p_payment_reference': null,
      });
      await _refresh();
      if (mounted) _notice('Выплата записана');
    } catch (e) { if (mounted) _notice('Не удалось записать выплату: $e', error: true); }
    finally { amount.dispose(); }
  }

  void _notice(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: _future, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _TeamError(error: snap.error.toString(), retry: _refresh);
    final employees = _teamRows(snap.data![0]), accruals = _teamRows(snap.data![1]), payments = _teamRows(snap.data![2]);
    final names = {for (final e in employees) e['id'].toString(): e['full_name'].toString()};
    return RefreshIndicator(onRefresh: _refresh, child: ListView(physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12), children: [
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _addAccrual(employees),
          icon: const Icon(Icons.add), label: const Text('Начислить зарплату'))),
        const SizedBox(height: 12),
        if (accruals.isEmpty) const ListTile(title: Text('Начислений пока нет')),
        for (final a in accruals) Builder(builder: (context) {
          final paid = payments.where((p) => p['accrual_id'] == a['id']).fold<double>(0, (s,p) => s + (p['amount'] as num).toDouble());
          final total = (a['amount'] as num).toDouble();
          final due = (total - paid).clamp(0, double.infinity).toDouble();
          final isDeduction = a['accrual_type'] == 'deduction';
          return Card(child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(names[a['employee_id']] ?? 'Сотрудник'),
            subtitle: Text('${a['accrual_type']} • ${a['period_start']} — ${a['period_end']} • выплачено ${paid.toStringAsFixed(2)} ₽'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${total.toStringAsFixed(2)} ₽', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (!isDeduction && due > 0) TextButton(onPressed: () => _pay(a, due), child: const Text('Выплатить')),
            ]),
          ));
        }),
      ]));
  });
}

class _TeamError extends StatelessWidget {
  const _TeamError({required this.error, required this.retry});
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
