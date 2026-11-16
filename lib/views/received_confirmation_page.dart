import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';

class ReceivedConfirmationPage extends StatefulWidget {
  const ReceivedConfirmationPage({
    super.key,
    this.receiptToken,
    this.standalone = false,
  });

  final String? receiptToken;
  final bool standalone;

  @override
  State<ReceivedConfirmationPage> createState() =>
      _ReceivedConfirmationPageState();
}

class _ReceivedConfirmationPageState extends State<ReceivedConfirmationPage> {
  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  final _receiptController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isProcessing = false;
  bool _isSuccess = false;
  bool _isSendingFeedback = false;
  String? _feedbackToken;
  String? _error;
  String _reaction = "❤️";
  bool _showOnWall = false;

  String? get _linkToken => _parseReceiptToken(widget.receiptToken ?? '');

  String? _parseReceiptToken(String input) {
    if (_tokenPattern.hasMatch(input)) return input;
    final link = Uri.tryParse(input);
    if (link == null) return null;
    final route = Uri.tryParse(link.fragment);
    final token = route?.path == '/received'
        ? route?.queryParameters['token']
        : null;
    return token != null && _tokenPattern.hasMatch(token) ? token : null;
  }

  @override
  void dispose() {
    _receiptController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _confirmReceipt() async {
    if (_isProcessing) return;
    final token =
        _linkToken ?? _parseReceiptToken(_receiptController.text.trim());
    if (token == null) {
      setState(() {
        _error =
            "Use your private receipt link or ask the sender for a new one.";
      });
      return;
    }
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final feedbackToken = await FirebaseService().confirmPostcard(token);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _receiptController.clear();
      setState(() {
        _isSuccess = true;
        _feedbackToken = feedbackToken;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              "Could not confirm arrival. Check the link or ask the sender.";
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _submitFeedback() async {
    final token = _feedbackToken;
    if (token == null || _isSendingFeedback) return;
    setState(() => _isSendingFeedback = true);

    try {
      await FirebaseService().updateReceiptFeedback(
        token,
        reaction: _reaction,
        message: _messageController.text.trim(),
        showOnWall: _showOnWall,
      );
      if (!mounted) return;
      setState(() => _feedbackToken = null);
      _messageController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Feedback submitted. Thank you!")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not submit feedback. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _isSendingFeedback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 成功畫面
    if (_isSuccess) return _buildSuccessView();

    // 必須使用 Scaffold 包裹，以提供 Material 環境給 TextField
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.standalone
          ? AppBar(title: const Text("Confirm Receipt"), centerTitle: true)
          : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isProcessing)
                const CircularProgressIndicator()
              else ...[
                const Icon(
                  Icons.volunteer_activism_rounded,
                  size: 80,
                  color: Colors.amber,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Did you receive a postcard?",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (_linkToken == null) ...[
                  const Text(
                    "Paste the private receipt link or code from the sender.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: _receiptController,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: true,
                      onSubmitted: (_) => _confirmReceipt(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        labelText: "Receipt link or code",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _confirmReceipt,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, 50),
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    "Confirm Arrival ❤️",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, size: 120, color: Colors.pink),
                  const SizedBox(height: 30),
                  const Text(
                    "You made my day!",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "I'm so happy to know the postcard reached you safely. Thank you for being part of this journey!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  if (_feedbackToken != null) ...[
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _reaction,
                      decoration: const InputDecoration(
                        labelText: "How did this postcard make you feel?",
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: "❤️",
                          child: Text("❤️ Loved it"),
                        ),
                        DropdownMenuItem(
                          value: "😊",
                          child: Text("😊 So warm"),
                        ),
                        DropdownMenuItem(
                          value: "🥹",
                          child: Text("🥹 Touched"),
                        ),
                        DropdownMenuItem(
                          value: "🌟",
                          child: Text("🌟 Inspired"),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _reaction = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _messageController,
                      maxLines: 2,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: "One-line message (optional)",
                        hintText: "This postcard arrived at the perfect time.",
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _showOnWall,
                          onChanged: (v) =>
                              setState(() => _showOnWall = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            "Allow this message to appear on the public Wall of Warmth.",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: _isSendingFeedback ? null : _submitFeedback,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.amber.shade400),
                      ),
                      child: const Text("Share Feedback"),
                    ),
                  ],
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isSuccess = false;
                        _feedbackToken = null;
                        _error = null;
                        _reaction = "❤️";
                        _showOnWall = false;
                      });
                      _receiptController.clear();
                      _messageController.clear();
                      // 導回到首頁 (Request Tab)
                      Navigator.pushNamed(context, '/');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text("Back to Home"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
