import 'package:flutter_test/flutter_test.dart';
import 'package:teplitsa_pro/main.dart';

void main() {
  testWidgets('dashboard appears in demo mode', (tester) async {
    await tester.pumpWidget(
      const TeplitsaProApp(supabaseConfigured: false),
    );

    expect(find.text('Панель управления'), findsOneWidget);
    expect(find.text('Разделы хозяйства'), findsOneWidget);
    expect(find.text('Теплицы и зоны'), findsOneWidget);
  });
}
