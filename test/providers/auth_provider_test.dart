import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show IdTokenResult, User;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wander_stamp/providers/auth_provider.dart';

class _TokenAuth extends MockFirebaseAuth {
  _TokenAuth({super.signedIn, super.mockUser});

  @override
  Stream<User?> idTokenChanges() => userChanges();
}

// The Firebase test double uses mutable profile fields.
// ignore: must_be_immutable
class _DelayedTokenUser extends MockUser {
  _DelayedTokenUser() : super(customClaim: {'admin': true});

  final token = Completer<IdTokenResult>();

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) =>
      token.future;
}

void main() {
  test('initial session has no admin access', () {
    final provider = AuthProvider(auth: _TokenAuth());
    addTearDown(provider.dispose);
    expect(provider.user, isNull);
    expect(provider.isAdmin, isFalse);
  });

  test('login succeeds only with the boolean admin claim', () async {
    final auth = _TokenAuth(mockUser: MockUser(customClaim: {'admin': true}));
    final provider = AuthProvider(auth: auth);
    addTearDown(provider.dispose);

    expect(await provider.login('test@example.com', 'password'), isNull);
    expect(provider.user, isNotNull);
    expect(provider.isAdmin, isTrue);
  });

  test('a signed-in account without the admin claim is rejected', () async {
    final auth = _TokenAuth(mockUser: MockUser(customClaim: {'admin': 'true'}));
    final provider = AuthProvider(auth: auth);
    addTearDown(provider.dispose);

    expect(
      await provider.login('test@example.com', 'password'),
      'Unable to sign in as an administrator.',
    );
    expect(auth.currentUser, isNull);
    expect(provider.isAdmin, isFalse);
  });

  test('a token change rechecks admin access for the same user', () async {
    final user = MockUser(customClaim: {'admin': true});
    final auth = _TokenAuth(signedIn: true, mockUser: user);
    final provider = AuthProvider(auth: auth);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(provider.isAdmin, isTrue);

    auth.mockUser = MockUser(uid: user.uid);
    auth.userChangedStreamController.add(auth.currentUser);
    await Future<void>.delayed(Duration.zero);

    expect(provider.isAdmin, isFalse);
  });

  test('a delayed token lookup cannot grant access after logout', () async {
    final user = _DelayedTokenUser();
    final auth = _TokenAuth(signedIn: true, mockUser: user);
    final provider = AuthProvider(auth: auth);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);

    await provider.logout();
    user.token.complete(user.getIdTokenResultSync());
    await Future<void>.delayed(Duration.zero);

    expect(provider.user, isNull);
    expect(provider.isAdmin, isFalse);
  });
}
