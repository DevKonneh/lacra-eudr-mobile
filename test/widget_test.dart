// Basic smoke test for the LACRA Farm Mapping Tools Inspector app.
//
// This replaces the default Flutter counter-app template test, which
// referenced a non-existent `MyApp` class and a counter UI that doesn't
// exist in this app. The real root widget is `InspectorApp` (see
// lib/main.dart), which renders an auth-gated `AuthWrapper` as its home.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inspector_app/main.dart';

void main() {
  testWidgets('InspectorApp builds without throwing and shows a MaterialApp', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const InspectorApp());
    await tester.pump();

    // Verify the app shell renders successfully.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
