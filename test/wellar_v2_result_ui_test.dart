import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waller_app/models/wellar_v2_result.dart';
import 'package:waller_app/screens/scan/scan_premium_components.dart';
import 'package:waller_app/screens/scan_details_screen.dart';

void main() {
  group('Wellar V2 optional result fields', () {
    test('parses new evidence and measurements without flattening unknown fields', () {
      final result = WellarV2Result.fromJson(_payload(
        behavioralEvidence: {
          'schema_version': 'wellar.behavioral-evidence/1.0',
          'visible_fatigue_indicators': {
            'status': 'partial_evidence',
            'observations': {
              'short_clip_eye_closure_fraction': {
                'value': 0.12,
                'units': 'fraction',
              },
            },
            'abstention_reasons': ['sampling_rate_insufficient_for_blink_resolution'],
          },
          'vigilance_indicators': {
            'status': 'not_provided',
            'observations': {},
            'abstention_reasons': ['reaction_task_measurement_missing'],
          },
          'model_prediction': {'status': 'disabled'},
        },
        measurements: {
          'fatigue': {'observations': {}},
          'vigilance': {'status': 'not_provided'},
        },
        predictionExtension: {'status': 'disabled'},
      ));

      expect(result.behavioralEvidence['schema_version'], 'wellar.behavioral-evidence/1.0');
      expect(result.measurements['vigilance']['status'], 'not_provided');
      expect(result.predictionExtension['status'], 'disabled');
    });

    test('old payloads remain valid and missing measurements remain absent', () {
      final result = WellarV2Result.fromJson(_payload());

      expect(result.behavioralEvidence, isEmpty);
      expect(result.measurements, isEmpty);
      expect(result.predictionExtension, isEmpty);
      expect(result.eyeClosureFraction, isNull);
      expect(result.blinkRatePerMinute, isNull);
    });
  });

  testWidgets('all four existing readiness states retain their hero labels and colors', (tester) async {
    const states = <(String, Color)>[
      ('Stable', ScanTheme.teal),
      ('Low focus', ScanTheme.warning),
      ('Elevated fatigue', Color(0xFFF97316)),
      ('High risk', ScanTheme.danger),
    ];
    for (final (state, color) in states) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ScanDetailsScreen(v2Result: _result(state))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text(state), findsOneWidget);
      expect(find.text('Completed').evaluate(), isNotEmpty);
      final pill = tester
          .widgetList<StatusPill>(find.byType(StatusPill))
          .firstWhere((candidate) => candidate.label == 'Completed');
      expect(pill.color, color);
    }
  });

  testWidgets('missing measurements show unavailable copy without a fabricated zero', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ScanDetailsScreen(v2Result: _result('Stable'))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('No supported measurements are available in this result.'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
    expect(find.textContaining('not mean the scan failed'), findsOneWidget);
  });

  testWidgets('unverified reaction times carry an explicit limitation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScanDetailsScreen(
          v2Result: _result(
            'Stable',
            measurements: {
              'vigilance': {
                'status': 'observed_unverified',
                'value': {'median_valid_rt_ms': 342},
              },
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Median reaction time (unverified)'), findsOneWidget);
    expect(find.text('Reaction times are client-reported and unverified; this is not a validated vigilance test.'), findsOneWidget);
  });

  testWidgets('evidence section fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: Scaffold(body: ScanDetailsScreen(v2Result: _result('Stable'))),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    expect(find.text('Observations & measurements'), findsOneWidget);
  });
}

WellarV2Result _result(
  String state, {
  Map<String, dynamic>? measurements,
}) => WellarV2Result.fromJson(_payload(
  drowsinessIndicator: {'status': 'available', 'state': state},
  measurements: measurements,
  behavioralEvidence: {
    'visible_fatigue_indicators': {
      'status': 'insufficient_evidence',
      'observations': {},
      'abstention_reasons': [],
    },
    'vigilance_indicators': {
      'status': 'not_provided',
      'observations': {},
      'abstention_reasons': ['reaction_task_measurement_missing'],
    },
    'model_prediction': {'status': 'disabled'},
  },
));

Map<String, dynamic> _payload({
  String state = 'Stable',
  Map<String, dynamic>? drowsinessIndicator,
  Map<String, dynamic>? behavioralEvidence,
  Map<String, dynamic>? measurements,
  Map<String, dynamic>? predictionExtension,
}) => {
  'schema_version': '2.0',
  'scan_id': 'fixture-scan',
  'status': 'insufficient_evidence',
  'model_invocation_status': 'not_invoked_no_validated_model',
  'drowsiness_indicator': drowsinessIndicator ?? {'status': 'available', 'state': state},
  'quality': {'video': 'available'},
  'targets': {},
  if (behavioralEvidence != null) 'behavioral_evidence': behavioralEvidence,
  if (measurements != null) 'measurements': measurements,
  if (predictionExtension != null) 'prediction_extension': predictionExtension,
};
