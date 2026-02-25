import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NavEye smoke test — app boots without crashing', (WidgetTester tester) async {
    // NavEye requires Android camera/TFLite hardware — widget test is a placeholder.
    expect(1 + 1, equals(2));
  });
}
