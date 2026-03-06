import 'package:flutter_test/flutter_test.dart';
import 'package:outfi_app/main.dart';
import 'package:outfi_app/services/api_client.dart';

void main() {
  testWidgets('App renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      FyndaApp(apiClient: ApiClient()),
    );

    expect(find.text('Style. Curated.'), findsOneWidget);
  });
}
