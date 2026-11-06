import 'package:cms_site_manager/widgets/journey_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with:  flutter test test/journey_loader_test.dart
void main() {
  testWidgets('starts at milestone 01 and moves through the route', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: JourneyLoader())));
    expect(find.text('Project Information'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3000)); // about half way
    await tester.pump(const Duration(milliseconds: 300)); // let the label change finish
    final shown = kJourneyMilestones.where((n) => tester.any(find.text(n))).toList();
    expect(shown.length, 1);
    expect(shown.first, isNot('Project Information'));

    // keeps looping without errors
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox()); // dispose the repeating animation
  });

  testWidgets('shows a finished, still route when animations are disabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: JourneyLoader()),
      ),
    ));
    expect(find.text('MMS Erection'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('MMS Erection'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('there are 12 milestones, as on the website timeline', () {
    expect(kJourneyMilestones.length, 12);
    expect(kJourneyMilestones.first, 'Project Information');
    expect(kJourneyMilestones.last, 'MMS Erection');
  });
}
