import 'harvest_sales_pages.dart';
import 'inventory_pages.dart';
// The following style-only lints are handled in a later formatting pass.
// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OperationsHubPage extends StatelessWidget {
  const OperationsHubPage({
    required this.organizationId,
    this.initialTabIndex = 0,
    super.key,
  });

  final String organizationId;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 9,
    initialIndex: initialTabIndex,
    child: Scaffold(
      appBar: AppBar(title: const Text('Рабочие разделы'),
        bottom: const TabBar(isScrollable: true, tabs: [
          Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Склад'),
          Tab(icon: Icon(Icons.swap_horiz_outlined), text: 'Движения'),
          Tab(icon: Icon(Icons.agriculture_outlined), text: 'Урожай'),
          Tab(icon: Icon(Icons.people_alt_outlined), text: 'Покупатели'),
          Tab(icon: Icon(Icons.point_of_sale_outlined), text: 'Продажи'),
          Tab(icon: Icon(Icons.payments_outlined), text: 'Платежи'),
          Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Расходы'),
          Tab(icon: Icon(Icons.groups_outlined), text: 'Команда'),
          Tab(icon: Icon(Icons.sticky_note_2_outlined), text: 'Заметки'),
        ])),
      body: TabBarView(children: [
        InventoryItemsPage(organizationId: organizationId),
        InventoryMovementsPage(organizationId: organizationId),
        HarvestPage(organizationId: organizationId),
        _RecordList(org: organizationId, table: 'customers', columns: 'name,phone,email,address', titleField: 'name'),
        SalesPage(organizationId: organizationId),
        _RecordList(org: organizationId, table: 'payments', columns: 'amount,currency,payment_method,paid_at,reference_number', titleField: 'reference_number'),
        _RecordList(org: organizationId, table: 'expenses', columns: 'expense_date,category,description,amount,currency,document_number', titleField: 'description'),
        _TeamList(org: organizationId),
        _NotesPage(org: organizationId),
      ]),
    ),
  );
}

class _RecordList extends StatefulWidget {
  const _RecordList({required this.org, required this.table, required this.columns, required this.titleField});
  final String org, table, columns, titleField;
  @override
  State<_RecordList> createState() => _RecordListState();
}
class _RecordListState extends State<_RecordList> {
  late Future<List<Map<String,dynamic>>> future;
  @override
  void initState() { super.initState(); future = load(); }
  Future<List<Map<String,dynamic>>> load() async {
    final rows = await Supabase.instance.client.from(widget.table).select(widget.columns)
      .eq('organization_id', widget.org).order('created_at', ascending: false);
    return rows.map((e) => Map<String,dynamic>.from(e)).toList();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(
    future: future,
    builder: (context,snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child:CircularProgressIndicator());
      if (snap.hasError) return Center(child:Padding(padding:const EdgeInsets.all(24),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.cloud_off_outlined,size:40),
          const SizedBox(height:12),
          Text('Не удалось загрузить раздел: ' + snap.error.toString(),textAlign:TextAlign.center),
          const SizedBox(height:12),
          FilledButton.icon(onPressed:()=>setState(()=>future=load()),icon:const Icon(Icons.refresh),label:const Text('Повторить')),
        ])));
      final rows=snap.data ?? [];
      if(rows.isEmpty) return RefreshIndicator(onRefresh:()async{setState(()=>future=load());await future;},
        child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(32),
          children:const [SizedBox(height:70),Icon(Icons.inbox_outlined,size:48),SizedBox(height:12),
            Text('Записей пока нет',textAlign:TextAlign.center)]));
      return RefreshIndicator(onRefresh:()async{setState(()=>future=load());await future;},
        child:ListView(padding:const EdgeInsets.all(12),children:[
          for(final row in rows) Card(child:ExpansionTile(
            title:Text((row[widget.titleField] ?? 'Запись').toString()),
            subtitle:Text(row.entries.where((e)=>e.value!=null).take(2).map((e)=>e.key + ': ' + e.value.toString()).join(' • ')),
            childrenPadding:const EdgeInsets.fromLTRB(16,0,16,12),
            children:[for(final entry in row.entries) if(entry.value!=null)
              Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,
                children:[SizedBox(width:130,child:Text(entry.key,style:const TextStyle(color:Colors.black54))),
                  Expanded(child:Text(entry.value.toString()))]))],
          )),
        ]));
    },
  );
}

class _TeamList extends StatefulWidget {
  const _TeamList({required this.org});
  final String org;
  @override
  State<_TeamList> createState()=>_TeamListState();
}
class _TeamListState extends State<_TeamList> {
  late Future<List<List<Map<String,dynamic>>>> future;
  @override
  void initState(){super.initState();future=load();}
  Future<List<List<Map<String,dynamic>>>> load() async {
    final db=Supabase.instance.client;
    final a=await db.from('employee_profiles').select('full_name,job_title,employment_status')
      .eq('organization_id',widget.org).order('full_name');
    final b=await db.from('tasks').select('title,description,status,priority,due_at')
      .eq('organization_id',widget.org).order('created_at',ascending:false);
    return [a.map((e)=>Map<String,dynamic>.from(e)).toList(),b.map((e)=>Map<String,dynamic>.from(e)).toList()];
  }
  @override
  Widget build(BuildContext context)=>FutureBuilder<List<List<Map<String,dynamic>>>>(
    future:future,builder:(context,snap){
      if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
      if(snap.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),
        child:Text('Не удалось загрузить команду и задачи: '+snap.error.toString(),textAlign:TextAlign.center)));
      final data=snap.data!;
      return RefreshIndicator(onRefresh:()async{setState(()=>future=load());await future;},
        child:ListView(padding:const EdgeInsets.all(12),children:[
          Text('Сотрудники',style:Theme.of(context).textTheme.titleLarge),
          if(data[0].isEmpty) const ListTile(title:Text('Сотрудников пока нет')),
          for(final e in data[0]) Card(child:ListTile(leading:const Icon(Icons.person_outline),
            title:Text(e['full_name']?.toString()??'Без имени'),
            subtitle:Text((e['job_title']??'Должность не указана').toString()+' • '+(e['employment_status']??'').toString()))),
          const SizedBox(height:12),Text('Задачи',style:Theme.of(context).textTheme.titleLarge),
          if(data[1].isEmpty) const ListTile(title:Text('Задач пока нет')),
          for(final t in data[1]) Card(child:ListTile(leading:const Icon(Icons.task_alt_outlined),
            title:Text(t['title']?.toString()??'Задача'),
            subtitle:Text((t['status']??'').toString()+' • '+(t['priority']??'').toString()))),
          const SizedBox(height:12),
          const Text('Безопасный режим просмотра. Запись включим после добавления проверенных серверных операций.',
            style:TextStyle(color:Colors.black54)),
        ]));
    });
}


class _NotesPage extends StatefulWidget {
  const _NotesPage({required this.org});
  final String org;

  @override
  State<_NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<_NotesPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('notes_and_attachments')
        .select('id,title,body,created_at,uploaded_by')
        .eq('organization_id', widget.org)
        .order('created_at', ascending: false);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    final title = _title.text.trim();
    if (body.isEmpty && title.isEmpty) {
      setState(() => _error = 'Заполни заголовок или текст заметки.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('notes_and_attachments').insert({
        'organization_id': widget.org,
        'title': title.isEmpty ? null : title,
        'body': body.isEmpty ? null : body,
        'uploaded_by': user?.id,
      });
      _title.clear();
      _body.clear();
      if (mounted) {
        setState(() => _future = _load());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заметка сохранена')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось сохранить заметку: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Новая заметка', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Заголовок',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _body,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Текст заметки',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Сохранить заметку'),
                ),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Не удалось загрузить заметки: ${snapshot.error}'));
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(child: Text('Заметок пока нет'));
            }
            return RefreshIndicator(
              onRefresh: () async {
                final next = _load();
                setState(() => _future = next);
                await next;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final date = DateTime.tryParse(row['created_at']?.toString() ?? '');
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.sticky_note_2_outlined),
                      title: Text((row['title'] ?? 'Без заголовка').toString()),
                      subtitle: Text([
                        if (row['body'] != null) row['body'].toString(),
                        if (date != null) date.toLocal().toString().substring(0, 16),
                      ].join('\\n')),
                      isThreeLine: row['body'] != null,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ],
  );
}
