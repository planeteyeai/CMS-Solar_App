import 'package:cms_site_manager/models/site_task.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with:  flutter test test/ai_analysis_test.dart
void main() {
  final base = <String, dynamic>{
    'progress_percent': 62,
    'summary': 'Overview',
    'observations': ['a'],
    'safety_findings': [],
    'safety_severity': 'LOW',
    'people_total': 3,
    'people_with_ppe': 2,
    'equipment': ['excavator'],
    'risk_level': 'LOW',
    'confidence': 80,
    'image_quality': 'B',
    'recommendations': ['r'],
    'quantities': [
      {'item': 'pile', 'number': '12', 'size': '80x40 mm', 'material': 'steel', 'quantity': '12', 'unit': 'nos'}
    ],
  };

  test('hazards are sorted most severe first and raise the overall risk', () {
    final a = TaskAnalysis.fromAi({
      ...base,
      'hazards': [
        {'hazard': 'No helmet', 'category': 'PPE', 'severity': 'MEDIUM', 'location': 'left', 'action': 'Wear helmet'},
        {'hazard': 'Open trench', 'category': 'Excavation', 'severity': 'HIGH', 'location': 'centre', 'action': 'Barricade'},
        {'hazard': '', 'severity': 'LOW'},
      ],
    });
    expect(a.hazards.length, 2); // empty one dropped
    expect(a.hazards.first.hazard, 'Open trench');
    expect(a.riskLevel, 'HIGH'); // AI said LOW, hazards imply HIGH
    expect(a.safetySeverity, 'HIGH');
    expect(a.safetyFindings, ['Open trench', 'No helmet']); // filled from hazards when the AI gave none
    expect(a.hasReport, isTrue);
  });

  test('quantities are still parsed (existing feature)', () {
    final a = TaskAnalysis.fromAi(base);
    expect(a.quantities.length, 1);
    expect(a.quantities.first.quantityLabel, '12 nos');
    expect(a.hasReport, isFalse); // older analyses have no detailed report
    expect(a.riskLevel, 'LOW');
  });

  test('toJson -> fromAi round trip keeps the report', () {
    final a = TaskAnalysis.fromAi({
      ...base,
      'work_completed': ['x'],
      'immediate_actions': ['Stop work'],
      'ppe_status': 'ok',
      'hazards': [
        {'hazard': 'Loose cables', 'category': 'Electrical', 'severity': 'CRITICAL', 'location': 'right', 'action': 'Isolate'}
      ],
    });
    final b = TaskAnalysis.fromAi(a.toJson());
    expect(b.hazards.single.severity, 'CRITICAL');
    expect(b.workCompleted, ['x']);
    expect(b.immediateActions, ['Stop work']);
    expect(b.riskLevel, 'HIGH');
    expect(b.quantities.length, 1);
  });
}
