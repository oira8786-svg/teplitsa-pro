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
        _RecordList(org: organizationId, table: 'inventory_items', columns: 'name,category,base_unit,minimum_stock,sku', titleField: 'name'),
        _RecordList(org: organizationId, table: 'inventory_movements', columns: 'movement_type,quantity,unit,occurred_at,document_number,notes', titleField: 'movement_type'),
        _RecordList(org: organizationId, table: 'harvest_lots', columns: 'lot_number,harvested_at,quantity,unit,grade,status,storage_location', titleField: 'lot_number'),
        _RecordList(org: organizationId, table: 'customers', columns: 'name,phone,email,address', titleField: 'name'),
        _RecordList(org: organizationId, table: 'sales', columns: 'sale_number,sold_at,status,currency,notes', titleField: 'sale_number'),
        _RecordList(org: organizationId, table: 'payments', columns: 'amount,currency,payment_method,paid_at,reference_number', titleField: 'reference_number'),
        _RecordList(org: organizationId, table: 'expenses', columns: 'expense_date,category,description,amount,currency,document_number', titleField: 'description'),
        _TeamList(org: organizationId),
        _RecordList(org: organizationId, table: 'notes_and_attachments', columns: 'title,body,created_at,storage_path', titleField: 'title'),
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
