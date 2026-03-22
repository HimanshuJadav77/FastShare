import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wifi_ftp/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: FastShareApp(),
      ),
    );

    // Verify that the app starts and shows the title.
    expect(find.text('SHARE'), findsOneWidget);
  });
}
