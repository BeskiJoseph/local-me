import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../widgets/input_field.dart';
import '../../widgets/primary_button.dart';

import 'signup_username.dart';
import '../../services/otp_service.dart';
import 'signup_otp.dart';

class SignupEmailScreen extends StatefulWidget {
  final SignupData data;
  const SignupEmailScreen({super.key, required this.data});

  @override
  State<SignupEmailScreen> createState() => _SignupEmailScreenState();
}

class _SignupEmailScreenState extends State<SignupEmailScreen> {
  final emailController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create account")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            InputField(hint: "Email", controller: emailController),
            const Spacer(),
            PrimaryButton(
              text: _isLoading ? "Sending..." : "Next",
              enabled: !_isLoading,
              onTap: () async {
                final email = emailController.text.trim();
                final emailRegex = RegExp(r"^[^@]+@[^@]+\.[^@]+");
                if (email.isEmpty || !emailRegex.hasMatch(email)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email')),
                  );
                  return;
                }

                setState(() => _isLoading = true);

                try {
                  await OtpService.sendOtp(emailController.text.trim());
                  
                  if (!context.mounted) return;

                  widget.data.email = emailController.text.trim();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SignupOtpScreen(data: widget.data),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""))),
                  );
                } finally {
                  if (context.mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

