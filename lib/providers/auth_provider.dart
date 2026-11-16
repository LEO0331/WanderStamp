import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth;
  late final StreamSubscription<User?> _authSubscription;
  Future<void>? _sessionRefresh;
  User? _user;
  bool _isAdmin = false;
  bool _disposed = false;
  int _sessionVersion = 0;

  User? get user => _user;
  bool get isAdmin => _isAdmin && _user?.uid == _auth.currentUser?.uid;

  AuthProvider({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance {
    _authSubscription = _auth.idTokenChanges().listen(
      (user) => _sessionRefresh = _refreshSession(user),
      onError: (Object _) {
        _sessionVersion++;
        _setSession(_auth.currentUser, false);
      },
    );
  }

  Future<void> _refreshSession(User? user) async {
    if (_disposed || user?.uid != _auth.currentUser?.uid) return;
    final version = ++_sessionVersion;
    if (_user?.uid != user?.uid) _setSession(user, false);
    bool isAdmin = false;
    if (user != null) {
      try {
        final result = await user.getIdTokenResult();
        isAdmin = result.claims?['admin'] == true;
      } catch (_) {
        // A token lookup failure must not grant access.
      }
    }
    if (version == _sessionVersion && user?.uid == _auth.currentUser?.uid) {
      _setSession(user, isAdmin);
    }
  }

  void _setSession(User? user, bool isAdmin) {
    if (_disposed || (_user == user && _isAdmin == isAdmin)) return;
    _user = user;
    _isAdmin = isAdmin;
    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      _sessionRefresh = _refreshSession(user);
      Future<void>? refresh;
      do {
        refresh = _sessionRefresh;
        await refresh;
      } while (refresh != _sessionRefresh);
      if (user != null && _auth.currentUser?.uid == user.uid) {
        if (isAdmin) return null;
        await logout();
      }
    } catch (_) {
      // Keep Firebase error details out of the login screen.
    }
    return 'Unable to sign in as an administrator.';
  }

  Future<void> logout() async {
    await _auth.signOut();
    if (_auth.currentUser == null) {
      _sessionRefresh = _refreshSession(null);
      await _sessionRefresh;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionVersion++;
    _authSubscription.cancel();
    super.dispose();
  }
}
