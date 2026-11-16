import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';
import '../../models/postcard.dart';
import '../../widgets/postcard_card.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.select((AuthProvider auth) => auth.isAdmin)) {
      return Scaffold(
        appBar: AppBar(title: const Text("Admin Dashboard")),
        body: Center(
          child: TextButton(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/admin-login'),
            child: const Text("Sign in as administrator"),
          ),
        ),
      );
    }
    return const _AuthorizedDashboard();
  }
}

class _AuthorizedDashboard extends StatefulWidget {
  const _AuthorizedDashboard();

  @override
  State<_AuthorizedDashboard> createState() => _AuthorizedDashboardState();
}

class _AuthorizedDashboardState extends State<_AuthorizedDashboard> {
  late final _postcards = FirebaseService().getAdminPostcards();

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.logout();
      if (navigator.mounted) {
        navigator.pushNamedAndRemoveUntil('/', (route) => false);
      }
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Logged out safely")),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Could not log out. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: _logout,
          ),
        ],
      ),
      body: StreamBuilder<List<Postcard>>(
        stream: _postcards,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Could not load requests."));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, i) => PostcardCard(
              postcard: snapshot.data![i],
              isAdminView: true, // 關鍵：開啟管理員模式
            ),
          );
        },
      ),
    );
  }
}
