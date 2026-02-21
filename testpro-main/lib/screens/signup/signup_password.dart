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
              "Create a strong password with at least 8 characters, including a letter and a number.",
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
                final password = passwordController.text;
                final hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
                final hasNumber = password.contains(RegExp(r'[0-9]'));

                if (password.length < 8 || !hasLetter || !hasNumber) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must be at least 8 characters and include a letter and a number')),
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
