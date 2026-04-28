import 'package:flutter_test/flutter_test.dart';

import 'package:control/main.dart';

void main() {
  testWidgets('App renders navigation bar', (WidgetTester tester) async {
    await tester.pumpWidget(const HikariStickApp());

    // Verify navigation destinations exist
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('颜色库'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
