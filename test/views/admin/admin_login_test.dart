import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:wander_stamp/views/admin/admin_login.dart';
import 'package:wander_stamp/views/admin/admin_dashboard.dart';
import 'package:wander_stamp/providers/auth_provider.dart';
import 'package:wander_stamp/services/firebase_service.dart';

class MockAuthProvider extends Mock implements AuthProvider {}

class MockFirebaseService extends Mock implements FirebaseService {}

void main() {
  late MockAuthProvider mockAuthProvider;
  late MockFirebaseService mockFirebaseService;

  setUp(() {
    mockAuthProvider = MockAuthProvider();
    mockFirebaseService = MockFirebaseService();
    FirebaseService.setMockInstance(mockFirebaseService);
  });

  group('AdminLoginPage Widget Tests', () {
    testWidgets('should show login fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AuthProvider>.value(
            value: mockAuthProvider,
            child: const AdminLoginPage(),
          ),
        ),
      );

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text("Login"), findsOneWidget);
    });

    testWidgets('should call login on button press', (
      WidgetTester tester,
    ) async {
      when(
        () => mockAuthProvider.login(any(), any()),
      ).thenAnswer((_) async => null);
      when(() => mockAuthProvider.isAdmin).thenReturn(true);
      when(
        () => mockFirebaseService.getAdminPostcards(),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: mockAuthProvider,
          child: const MaterialApp(home: AdminLoginPage()),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'admin@test.com');
      await tester.enterText(find.byType(TextField).at(1), 'password');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      verify(
        () => mockAuthProvider.login('admin@test.com', 'password'),
      ).called(1);
      expect(find.byType(AdminDashboard), findsOneWidget);
    });

    testWidgets('login failure keeps the form and shows a generic error', (
      tester,
    ) async {
      when(
        () => mockAuthProvider.login(any(), any()),
      ).thenAnswer((_) async => 'internal detail');
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AuthProvider>.value(
            value: mockAuthProvider,
            child: const AdminLoginPage(),
          ),
        ),
      );

      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to sign in as an administrator.'),
        findsOneWidget,
      );
      expect(find.text('internal detail'), findsNothing);
      verifyNever(() => mockFirebaseService.getAdminPostcards());
    });
  });
}
