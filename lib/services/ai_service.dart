import 'dart:convert';
import 'dart:typed_data';

import '../config/api_config.dart';
import '../models/site_task.dart';
import 'auth_service.dart';

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// Estimates task progress from site photos.
class AiService {
  AiService._();

  static String _prompt({
    required String taskName,
    required String taskDescription,
    required double previousProgress,
    required String projectName,
    required int imageCount,
  }) =>
      '''
You are an experienced solar-plant construction site engineer reviewing site photos.
Project: ${projectName.isEmpty ? 'solar power project' : projectName}
Task being reported: "$taskName"
Task scope: $taskDescription
Progress already recorded for this task: ${previousProgress.round()}%
Photos attached: $imageCount

Judge ONLY what is visible. Do not invent details.
"progress_percent" is the estimated overall completion (0-100) of THIS TASK for the whole site, based on the visible work
compared with the task scope and the already recorded progress. Be realistic and conservative: only go above the
recorded progress if the photos show additional completed work, and use 100 only if the task is clearly finished.
If the photos do not show this task, keep the recorded progress, set a low confidence and say so in the summary.

Counts, sizes, materials and quantities must NOT appear inside "summary", "observations", "recommendations"
or any image "description". Those sentences stay qualitative. Every measurable thing goes in "quantities" instead,
as its own object, so each value can be edited on its own.
Combine what is visible across all photos. Do not count the same physical object twice if it appears in more than one photo.
Use "" when a value is not visible. Never guess a number, size, material or quantity.

"quantities" rules:
- "item": short name of the component or material (example: "module mounting pile")
- "number": how many discrete pieces are visible, digits only, or ""
- "size": section or dimensions actually visible (example: "80x40 mm" or "2.5 m"), or ""
- "material": material if it can be identified (example: "galvanized steel"), or ""
- "quantity": the reportable amount, digits only. When the item is counted in pieces this equals "number". When it is measured (length, area, weight) this is that measurement and "number" is the piece count if both are visible. "" if not visible.
- "unit": one of nos, m, m2, m3, kg, set, or ""
Return one object per distinct item. Return an empty list when nothing measurable is visible.

Write a THOROUGH site report, not a short note. Be specific about what is visible in the photos: the stage of work,
the condition and finish of what has been built, who is working, the equipment in use and the state of the work area.
The same rule applies to every new text field below: keep sentences qualitative, put measurable values only in "quantities".

HAZARDS AND SAFETY: examine every photo carefully and report EVERY hazard or unsafe condition you can see, even minor ones.
Look for, among other things: missing or incorrect PPE (helmet, hi-vis vest, safety shoes, gloves, harness, eye or ear protection);
work at height without edge protection or fall arrest; open, unprotected or poorly shored excavations and trenches;
loose, unstable or badly stacked materials; trip hazards and untidy work areas; exposed cables, live electrical equipment
or temporary wiring; unsafe lifting or machinery operation (people close to moving plant, no signaller, overloaded
equipment); missing barricades, signs or access control; fire risks and stored fuel; unsafe ladders or scaffolds;
poor ground, water logging or slope instability; and any workmanship or structural defect that could become a safety risk.
Each hazard needs a clear description, a category, a severity, where it is in the photo and a specific corrective action.
Severity guide: LOW = minor, fix during normal work; MEDIUM = could cause injury, fix today; HIGH = serious injury likely,
stop the affected work until fixed; CRITICAL = immediate danger to life, stop work now.
If there is genuinely no hazard, return an empty "hazards" list and say so in "ppe_status" and "housekeeping".

Return ONE JSON object with exactly these keys:
{
  "progress_percent": number 0-100,
  "summary": "a clear overview of 4-6 plain sentences: what is visible, the stage of the work, how far it has progressed, its quality and the main safety points, with no counts, sizes, materials or quantities",
  "observations": ["factual observations about the work (max 8), with no counts, sizes, materials or quantities"],
  "work_completed": ["what is already finished and visible (max 8)"],
  "work_in_progress": ["what is being worked on right now (max 6)"],
  "work_remaining": ["what still has to be done to finish this task (max 8)"],
  "quality_observations": ["workmanship, alignment, finish, defects or good practice (max 8)"],
  "hazards": [
    {
      "hazard": "clear description of the hazard or unsafe condition",
      "category": "PPE | Work at height | Excavation | Electrical | Machinery and lifting | Housekeeping | Materials storage | Fire | Traffic and access | Structural | Environmental | Other",
      "severity": "LOW | MEDIUM | HIGH | CRITICAL",
      "location": "where in the photo (for example: left foreground, beside the excavator)",
      "action": "specific corrective action to remove or control it"
    }
  ],
  "ppe_status": "2-3 sentences on PPE compliance of the people visible",
  "housekeeping": "1-2 sentences on tidiness, material storage and access routes",
  "environment": "1-2 sentences on weather, ground and lighting that affect the work or safety",
  "immediate_actions": ["actions to take TODAY to remove hazards, most urgent first (max 5)"],
  "safety_findings": ["one short sentence per hazard above, empty list if none"],
  "safety_severity": "NONE | LOW | MEDIUM | HIGH | CRITICAL",
  "people_total": integer,
  "people_with_ppe": integer,
  "equipment": ["machines / vehicles / tools visible"],
  "risk_level": "LOW | MEDIUM | HIGH",
  "confidence": integer 0-100,
  "image_quality": "A | B | C | D",
  "recommendations": ["up to 5 concrete next actions for the site team, with no counts, sizes, materials or quantities"],
  "quantities": [
    {
      "item": "short name",
      "number": "digits or empty",
      "size": "dimensions or empty",
      "material": "material or empty",
      "quantity": "digits or empty",
      "unit": "nos | m | m2 | m3 | kg | set | empty"
    }
  ],
  "images": [
    {
      "index": 1,
      "description": "one sentence on what THIS photo shows",
      "observations": ["short facts visible in this photo"],
      "safety_findings": ["safety concerns visible in this photo, empty if none"],
      "risk_level": "LOW | MEDIUM | HIGH",
      "visible_progress_percent": number 0-100 (how complete the work looks in this photo)
    }
  ]
}
"images" must contain exactly one entry per attached photo, in the order the photos were attached (index starts at 1).
''';

  static const Map<String, dynamic> _responseSchema = {
    'type': 'OBJECT',
    'properties': {
      'progress_percent': {'type': 'NUMBER'},
      'summary': {'type': 'STRING'},
      'observations': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'work_completed': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'work_in_progress': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'work_remaining': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'quality_observations': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'hazards': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'hazard': {'type': 'STRING'},
            'category': {'type': 'STRING'},
            'severity': {'type': 'STRING'},
            'location': {'type': 'STRING'},
            'action': {'type': 'STRING'},
          },
          'required': ['hazard', 'category', 'severity', 'location', 'action'],
        },
      },
      'ppe_status': {'type': 'STRING'},
      'housekeeping': {'type': 'STRING'},
      'environment': {'type': 'STRING'},
      'immediate_actions': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'safety_findings': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'safety_severity': {'type': 'STRING'},
      'people_total': {'type': 'INTEGER'},
      'people_with_ppe': {'type': 'INTEGER'},
      'equipment': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'risk_level': {'type': 'STRING'},
      'confidence': {'type': 'INTEGER'},
      'image_quality': {'type': 'STRING'},
      'recommendations': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'quantities': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'item': {'type': 'STRING'},
            'number': {'type': 'STRING'},
            'size': {'type': 'STRING'},
            'material': {'type': 'STRING'},
            'quantity': {'type': 'STRING'},
            'unit': {'type': 'STRING'},
          },
          'required': ['item', 'number', 'size', 'material', 'quantity', 'unit'],
        },
      },
      'images': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'index': {'type': 'INTEGER'},
            'description': {'type': 'STRING'},
            'observations': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'safety_findings': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'risk_level': {'type': 'STRING'},
            'visible_progress_percent': {'type': 'NUMBER'},
          },
          'required': [
            'index',
            'description',
            'observations',
            'safety_findings',
            'risk_level',
            'visible_progress_percent',
          ],
        },
      },
    },
    'required': [
      'progress_percent',
      'summary',
      'observations',
      'work_completed',
      'work_in_progress',
      'work_remaining',
      'quality_observations',
      'hazards',
      'ppe_status',
      'housekeeping',
      'environment',
      'immediate_actions',
      'safety_findings',
      'safety_severity',
      'people_total',
      'people_with_ppe',
      'equipment',
      'risk_level',
      'confidence',
      'image_quality',
      'recommendations',
      'quantities',
      'images',
    ],
  };

  static Future<TaskAnalysis> analyzeTask({
    required AuthService auth,
    required List<Uint8List> images,
    required SiteTask task,
    String projectName = '',
  }) async {
    if (images.isEmpty) {
      throw const AiException('Add at least one photo to analyse.');
    }

    final parts = <Map<String, dynamic>>[
      {
        'text': _prompt(
          taskName: task.name,
          taskDescription: task.description,
          previousProgress: task.progress,
          projectName: projectName,
          imageCount: images.length,
        ),
      },
      for (final b in images)
        {
          'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(b)},
        },
    ];
    final body = <String, dynamic>{
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 8192, // room for the long report (the server caps it at 8192)
        'responseMimeType': 'application/json',
        'responseSchema': _responseSchema,
      },
    };
    if (jsonEncode(body).length > AiConfig.maxBodyBytes) {
      throw const AiException('The photos are too large to send. Use fewer or smaller photos.');
    }

    // Goes to our backend, which adds the secret key. Same login as the rest of the app.
    final res = await auth.authenticatedPost(AiConfig.endpoint, body, timeout: AiConfig.timeout);
    if (res == null) {
      throw const AiException(
          'Could not reach the analysis service, or it took too long. Check your internet and try again.');
    }

    if (res.statusCode != 200) {
      String detail = '';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        detail = (j['error'] ?? j['detail'] ?? '').toString();
      } catch (_) {}
      switch (res.statusCode) {
        case 401:
          throw const AiException('Your login has expired. Please log in again.');
        case 413:
          throw const AiException('The photos are too large. Use fewer or smaller photos.');
        case 429:
          throw AiException(detail.isNotEmpty
              ? detail
              : 'You have reached the analysis limit for now. Please try again later.');
        case 500:
          throw const AiException('Analysis is not available right now. Please contact your administrator.');
        case 502:
          throw const AiException('The analysis service is unavailable. Please try again in a minute.');
        case 504:
          throw const AiException('The analysis took too long. Please try again.');
        default:
          throw AiException(detail.isNotEmpty ? detail : 'Analysis failed (${res.statusCode}).');
      }
    }

    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
      final cleaned =
          text.replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$'), '').trim();
      final parsed = jsonDecode(cleaned);
      if (parsed is! Map<String, dynamic>) throw const FormatException();
      return TaskAnalysis.fromAi(parsed);
    } catch (_) {
      throw const AiException('The analysis result was unreadable. Please retake the photos.');
    }
  }
}
