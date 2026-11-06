import 'package:cms_site_manager/widgets/construction_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with:  flutter test test/construction_backdrop_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both background pictures are bundled with the app', () async {
    for (final path in ['assets/images/construction_day.jpg', 'assets/images/construction_dusk.jpg']) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(50000), reason: path);
    }
  });

  testWidgets('shows its child on top of the picture', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ConstructionBackdrop(child: Text('hello')))));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
