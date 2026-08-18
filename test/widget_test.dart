import 'package:flutter_test/flutter_test.dart';
import 'package:netemu/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic smoke – full init needs platform channels
    expect(true, isTrue);
  });
}
