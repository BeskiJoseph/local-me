import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import 'signup_dob.dart';

class SignupUsernameScreen extends StatelessWidget {
  final SignupData data;
  SignupUsernameScreen({super.key, required this.data});

  final TextEditingController usernameController = TextEditingController();

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
                onPressed: () {
                  data.username = usernameController.text.trim();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SignupDobScreen(data:data),
                    ),
                  );
                },
                child: const Text("Next"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
