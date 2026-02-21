import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../services/backend_service.dart';
import 'signup_dob.dart';

class SignupUsernameScreen extends StatefulWidget {
  final SignupData data;
  const SignupUsernameScreen({super.key, required this.data});

  @override
  State<SignupUsernameScreen> createState() => _SignupUsernameScreenState();
}

class _SignupUsernameScreenState extends State<SignupUsernameScreen> {
  final TextEditingController usernameController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Choose username"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Pick a username",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "You can always change it later.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: usernameController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                hintText: "Username",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const Spacer(),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onNext,
                child: _isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Next"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNext() async {
    final username = usernameController.text.trim();
    
    // 1. Basic length check
    if (username.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username must be at least 3 characters')),
      );
      return;
    }

    // 2. Character check (no spaces, only alphanumeric and underscores)
    if (!RegExp(r"^[a-zA-Z0-9_]+$").hasMatch(username)) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usernames can only contain letters, numbers, and underscores')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 3. Uniqueness check via backend
      final response = await BackendService.checkUsername(username);
      
      if (!mounted) return;

      if (!response.success || response.data != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.error ?? 'Username is already taken')),
        );
        return;
      }

      widget.data.username = username;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SignupDobScreen(data: widget.data),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
