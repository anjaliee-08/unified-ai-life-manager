import 'package:flutter_test/flutter_test.dart';
import 'package:uailm/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UAILMApp());
  });
}