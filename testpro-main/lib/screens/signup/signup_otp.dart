import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../widgets/primary_button.dart';
import '../../services/otp_service.dart';
import '../../utils/safe_error.dart';
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
  int _resendCooldown = 0;
  int _attempts = 0;
  final int _maxAttempts = 5;

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
            const SizedBox(height: 20),
            
            // Resend Label/Button
            if (_resendCooldown > 0)
              Text("Resend code in $_resendCooldown s", style: const TextStyle(color: Colors.grey))
            else
              TextButton(
                onPressed: _resendOtp,
                child: const Text("Resend code"),
              ),

            const Spacer(),
            
            PrimaryButton(
              text: _isLoading ? "Verifying..." : "Next",
              enabled: !_isLoading,
              onTap: () async {
                if (_attempts >= _maxAttempts) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Too many attempts. Please try again later.')),
                  );
                  return;
                }

                String otp = _controllers.map((e) => e.text).join();
                if (otp.length != 6) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a 6-digit code')),
                  );
                  return;
                }

                setState(() {
                  _isLoading = true;
                  _attempts++;
                });

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
                    SnackBar(content: Text(safeErrorMessage(e, fallback: 'Verification failed. Please try again.'))),
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

  void _resendOtp() async {
    setState(() => _resendCooldown = 30);
    _startCooldownTimer();
    try {
      await OtpService.sendOtp(widget.data.email ?? "");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code resent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resend code. Please try again.')),
        );
      }
    }
  }

  void _startCooldownTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _resendCooldown--;
      });
      return _resendCooldown > 0;
    });
  }
}
