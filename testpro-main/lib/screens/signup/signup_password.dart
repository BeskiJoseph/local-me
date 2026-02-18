import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../widgets/input_field.dart';
import '../../widgets/primary_button.dart';
import 'signup_username.dart';

class SignupPasswordScreen extends StatelessWidget {
  final SignupData data;
  SignupPasswordScreen({super.key, required this.data});

  final passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create a password")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Create a strong password with at least 6 characters.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            InputField(
              hint: "Password",
              controller: passwordController,
              obscure: true,
            ),
            const Spacer(),
            PrimaryButton(
              text: "Next",
              onTap: () {
                if (passwordController.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must be at least 6 characters')),
                  );
                  return;
                }
                data.password = passwordController.text;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SignupUsernameScreen(data: data),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
