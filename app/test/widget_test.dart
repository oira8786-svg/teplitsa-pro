import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:teplitsa_pro/main.dart';

void main() {
  testWidgets('FaezAgro dashboard shows all main modules', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const TeplitsaProApp(supabaseConfigured: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('ФаёзАгро'), findsOneWidget);
    expect(find.text('Разделы хозяйства'), findsOneWidget);
    expect(find.text('Теплицы и зоны'), findsOneWidget);
    expect(find.text('Культуры и партии'), findsOneWidget);
    expect(find.text('Агрономический журнал'), findsOneWidget);
    expect(find.text('Календарь агротехнических работ'), findsOneWidget);
    expect(find.text('Защита растений'), findsOneWidget);
    expect(find.text('Склад'), findsOneWidget);
    expect(find.text('Урожай и продажи'), findsOneWidget);
    expect(find.text('Финансы'), findsOneWidget);
    expect(find.text('Сотрудники и задачи'), findsOneWidget);
    expect(find.text('Отчёты'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
