// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calendar_reminder_service.dart';

class AgronomyCalendarPage extends StatefulWidget {
  const AgronomyCalendarPage({required this.organizationId, super.key});
  final String organizationId;
  @override
  State<AgronomyCalendarPage> createState() => _AgronomyCalendarPageState();
}

class _AgronomyCalendarPageState extends State<AgronomyCalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<Map<String, dynamic>>> _future;
  static const _months = ['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь'];
  @override
  void initState() { super.initState(); _future = _load(); }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client.from('batches')
      .select('id,batch_number,sowing_date,planting_date,planned_harvest_date,status,crops(name),greenhouses(name),greenhouse_zones(name)')
      .eq('organization_id', widget.organizationId).not('status', 'eq', 'cancelled');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _changeMonth(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));
  String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  int _reminderId(_CalendarEvent event) {
    final key = widget.organizationId + '|' + event.date.toIso8601String() + '|' + event.title + '|' + event.details;
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _setReminder(_CalendarEvent event) async {
    final allowed = await CalendarReminderService.instance.requestPermissions();
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Разреши уведомления для ФаёзАгро в настройках телефона.')));
      return;
    }
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0), helpText: 'Во сколько напомнить?');
    if (picked == null || !mounted) return;
    final at = DateTime(event.date.year, event.date.month, event.date.day, picked.hour, picked.minute);
    try {
      await CalendarReminderService.instance.schedule(id: _reminderId(event), title: event.title, body: event.details, at: at);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Звуковое напоминание установлено на ' + _dateLabel(at) + ' в ' + picked.format(context))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось установить напоминание: ' + error.toString())));
    }
  }

  List<_CalendarEvent> _events(List<Map<String, dynamic>> batches) {
    final result = <_CalendarEvent>[];
    for (final batch in batches) {
      final cropValue = batch['crops'], greenhouseValue = batch['greenhouses'], zoneValue = batch['greenhouse_zones'];
      final crop = cropValue is Map ? (cropValue['name'] ?? 'Культура').toString() : 'Культура';
      final greenhouse = greenhouseValue is Map ? (greenhouseValue['name'] ?? '').toString() : '';
      final zone = zoneValue is Map ? (zoneValue['name'] ?? '').toString() : '';
      final place = [greenhouse, zone].where((v) => v.isNotEmpty).join(' • ');
      final number = (batch['batch_number'] ?? '').toString();
      final details = [crop, if (number.isNotEmpty) 'Партия $number', if (place.isNotEmpty) place].join(' • ');
      void add(String field, String title, IconData icon) {
        final raw = batch[field]?.toString();
        if (raw == null) {
          return;
        }
        final date = DateTime.tryParse(raw);
        if (date == null || date.year != _month.year || date.month != _month.month) return;
        result.add(_CalendarEvent(date: date, title: title, details: details, icon: icon));
      }
      add('sowing_date', 'Посев', Icons.spa_outlined);
      add('planting_date', 'Высадка / пересадка', Icons.yard_outlined);
      add('planned_harvest_date', 'Плановый сбор', Icons.agriculture_outlined);
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Календарь агротехнических работ')),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 40), const SizedBox(height: 12),
        Text('Не удалось загрузить календарь: ${snapshot.error}', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => setState(() => _future = _load()), icon: const Icon(Icons.refresh), label: const Text('Повторить')),
      ])));
      final events = _events(snapshot.data ?? []);
      return RefreshIndicator(onRefresh: () async { final next = _load(); setState(() => _future = next); await next; },
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Row(children: [
            IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('${_months[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge)),
            IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
          ]))),
          const SizedBox(height: 8),
          const Row(children: [
            _Legend(icon: Icons.spa_outlined, label: 'Посев'),
            _Legend(icon: Icons.yard_outlined, label: 'Высадка'),
            _Legend(icon: Icons.agriculture_outlined, label: 'Сбор'),
          ]),
          const SizedBox(height: 12),
          if (events.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Column(children: [
            Icon(Icons.event_available_outlined, size: 42), SizedBox(height: 10),
            Text('На этот месяц событий нет', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 6), Text('Даты появятся здесь из карточек партий растений.', textAlign: TextAlign.center),
          ])))
          else ...[
            Text('Запланировано: ${events.length}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final event in events) Card(child: ListTile(
              leading: CircleAvatar(child: Icon(event.icon)), title: Text(event.title), subtitle: Text(event.details),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_dateLabel(event.date), style: const TextStyle(fontWeight: FontWeight.w600)), IconButton(tooltip: 'Поставить звуковое напоминание', onPressed: () => _setReminder(event), icon: const Icon(Icons.alarm_add_outlined))]),
            )),
          ],
          const SizedBox(height: 12),
          const Text('Календарь пока показывает плановые даты из партий. Поливы, подкормки и обработки подключим после добавления безопасной серверной записи агрономических операций.', style: TextStyle(color: Colors.black54)),
        ]),
      );
    }),
  );
}

class _CalendarEvent {
  const _CalendarEvent({required this.date, required this.title, required this.details, required this.icon});
  final DateTime date;
  final String title, details;
  final IconData icon;
}
class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, size: 17), const SizedBox(width: 4), Flexible(child: Text(label, style: const TextStyle(fontSize: 11))),
  ]));
}
