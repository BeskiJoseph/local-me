import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../widgets/primary_button.dart';
import '../../services/otp_service.dart';
import 'signup_password.dart';

class SignupOtpScreen extends StatefulWidget {
  final SignupData data;
  const SignupOtpScreen({super.key, required this.data});

  @override
  State<SignupOtpScreen> createState() => _SignupOtpScreenState();
}

class _SignupOtpScreenState extends State<SignupOtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Enter confirmation code")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Enter the confirmation code we sent to ${widget.data.email}. To request a new code, wait a few moments.",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            
            // 6-digit OTP Input
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 45,
                  child: TextField(
                    controller: _controllers[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    decoration: InputDecoration(
                      counterText: "",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && index < 5) {
                        FocusScope.of(context).nextFocus();
                      } else if (value.isEmpty && index > 0) {
                        FocusScope.of(context).previousFocus();
                      }
                    },
                  ),
                );
              }),
            ),

            const Spacer(),
            
            PrimaryButton(
              text: _isLoading ? "Verifying..." : "Next",
              enabled: !_isLoading,
              onTap: () async {
                String otp = _controllers.map((e) => e.text).join();
                if (otp.length != 6) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a 6-digit code')),
                  );
                  return;
                }

                setState(() => _isLoading = true);

                try {
                  await OtpService.verifyOtp(widget.data.email ?? "", otp);
                  
                  if (!context.mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SignupPasswordScreen(data: widget.data),
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
