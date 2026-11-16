import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wander_stamp/widgets/success_dialog.dart';

void main() {
  group('SuccessDialog Widget Tests', () {
    testWidgets('should display the short ID correctly', (
      WidgetTester tester,
    ) async {
      const fullId = 'long-firebase-doc-id-1234';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SuccessDialog(docId: fullId)),
        ),
      );

      // Wait for TweenAnimation
      await tester.pumpAndSettle();

      expect(find.text("W-1234"), findsOneWidget);
      expect(find.text("Warmth Requested!"), findsOneWidget);
    });

    testWidgets('should close when "Open Tracking" is pressed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          const SuccessDialog(docId: 'test-id'),
                    );
                  },
                  child: const Text("Show"),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text("Show"));
      await tester.pumpAndSettle();

      expect(find.byType(SuccessDialog), findsOneWidget);

      await tester.tap(find.text("Open Tracking"));
      await tester.pumpAndSettle();

      expect(find.byType(SuccessDialog), findsNothing);
    });

    testWidgets('should copy ID action is visible', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SuccessDialog(docId: 'test-doc-id-1234')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Copy ID"), findsOneWidget);
      expect(find.text("Share"), findsOneWidget);
    });

    testWidgets('Share copies only the public tracking route and code', (
      WidgetTester tester,
    ) async {
      String? copiedText;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SuccessDialog(docId: 'test-doc-id-5678')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("Share"));
      await tester.pumpAndSettle();
      expect(Uri.parse(copiedText!).fragment, '/track?code=W-5678');
    });

    testWidgets('uses custom open tracking callback when provided', (
      WidgetTester tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuccessDialog(
              docId: 'test-doc-id-9876',
              onOpenTracking: () => called = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("Open Tracking"));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });
  });
}
