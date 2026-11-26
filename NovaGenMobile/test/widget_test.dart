import 'package:flutter_test/flutter_test.dart';
import 'package:novagen_mobile/main.dart';

void main() {
  testWidgets('NovaGenMobileApp renders cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const NovaGenMobileApp());
    expect(find.text('NOVAGEN MOBILE PRO'), findsOneWidget);
  });
}
