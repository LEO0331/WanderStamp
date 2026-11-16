import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wander_stamp/views/received_confirmation_page.dart';
import 'package:wander_stamp/services/firebase_service.dart';

class MockFirebaseService extends Mock implements FirebaseService {}

void main() {
  const receiptToken = 'Abcdefghijklmnopqrstuvwxyz0123456789_-AbCde';
  const feedbackToken = 'test-feedback-token';
  late MockFirebaseService mockFirebaseService;

  setUp(() {
    mockFirebaseService = MockFirebaseService();
    FirebaseService.setMockInstance(mockFirebaseService);
  });

  group('ReceivedConfirmationPage Widget Tests', () {
    testWidgets('should show initial form', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      await tester.pumpWidget(
        const MaterialApp(home: ReceivedConfirmationPage()),
      );

      expect(find.text("Did you receive a postcard?"), findsOneWidget);
    });

    testWidgets('rejects public tracking codes without a write', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      await tester.pumpWidget(
        const MaterialApp(home: ReceivedConfirmationPage()),
      );

      await tester.enterText(find.byType(TextField), 'W-1234');
      await tester.tap(find.text("Confirm Arrival ❤️"));
      await tester.pump();

      expect(
        find.text(
          "Use your private receipt link or ask the sender for a new one.",
        ),
        findsOneWidget,
      );
      verifyNever(() => mockFirebaseService.confirmPostcard(any()));
    });

    testWidgets(
      'a private link waits for confirmation and feedback is sent once',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1600));
        when(
          () => mockFirebaseService.confirmPostcard(receiptToken),
        ).thenAnswer((_) async => feedbackToken);
        when(
          () => mockFirebaseService.updateReceiptFeedback(
            any(),
            reaction: any(named: 'reaction'),
            message: any(named: 'message'),
            showOnWall: any(named: 'showOnWall'),
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/confirm',
            routes: {
              '/confirm': (context) =>
                  const ReceivedConfirmationPage(receiptToken: receiptToken),
              '/': (context) => const Scaffold(body: Text("Home Screen")),
            },
          ),
        );

        verifyNever(() => mockFirebaseService.confirmPostcard(any()));
        await tester.tap(find.text("Confirm Arrival ❤️"));
        await tester.pump();

        verify(
          () => mockFirebaseService.confirmPostcard(receiptToken),
        ).called(1);

        await tester.pumpAndSettle();
        expect(find.text("You made my day!"), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'So meaningful');
        await tester.ensureVisible(find.text("Share Feedback"));
        await tester.tap(find.text("Share Feedback"));
        await tester.pumpAndSettle();
        verify(
          () => mockFirebaseService.updateReceiptFeedback(
            feedbackToken,
            reaction: '❤️',
            message: 'So meaningful',
            showOnWall: false,
          ),
        ).called(1);
        expect(find.text("Share Feedback"), findsNothing);

        // Test Back to Home
        await tester.ensureVisible(find.text("Back to Home"));
        await tester.tap(find.text("Back to Home"));
        await tester.pumpAndSettle();
        expect(find.text("Home Screen"), findsOneWidget);
      },
    );
  });
}
