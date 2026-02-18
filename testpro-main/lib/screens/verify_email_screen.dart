import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_page.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool isEmailVerified = false;
  bool canResendEmail = false;
  String? _statusMessage;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    // Check if email is already verified
    isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (!isEmailVerified) {
      _sendVerificationEmail();
      
      // Periodically check if the user verified the email
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkEmailVerified(),
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    // Reload user to get latest status
    await AuthService.reloadUser();
    
    setState(() {
      isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    });

    if (isEmailVerified) {
      timer?.cancel();
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    // Navigate to Home Screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  Future<void> _sendVerificationEmail() async {
    setState(() {
      _statusMessage = "Sending verification email...";
    });
    
    try {
      await AuthService.sendEmailVerification();
      
      setState(() {
        _statusMessage = "Email sent successfully! Please check your inbox (and Spam).";
        canResendEmail = false;
      });
      
      await Future.delayed(const Duration(seconds: 10)); // Increased cooldown
      if (mounted) setState(() => canResendEmail = true);
      
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          if (e.code == 'too-many-requests') {
             _statusMessage = "Too many requests. Please wait a few minutes before retrying.";
          } else {
             _statusMessage = "Error: ${e.message}";
          }
           canResendEmail = true; // Allow retry immediately if it was just an error, but usually keep it disabled.
        });
      }
    } catch (e) {
       if (mounted) {
        setState(() {
          _statusMessage = "Error: ${e.toString()}";
          canResendEmail = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isEmailVerified) {
      // Just in case it renders before navigation
      return const Scaffold(
        body: Center(child: Text("Email Verified! Redirecting...")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify Email"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              timer?.cancel();
              await AuthService.signOut();
              if (mounted) {
                 Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false
                 );
              }
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             const Icon(Icons.email_outlined, size: 80, color: Colors.blue),
             const SizedBox(height: 20),
             Text(
               "${FirebaseAuth.instance.currentUser?.email}",
               style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
             ),
             const SizedBox(height: 10),
             const Text(
              "A verification email has been sent to your email address.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
             ),
             const SizedBox(height: 20),
             const Text(
               "Please check your email and click the link to verify your account.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
             ),
             const SizedBox(height: 20),
             if (_statusMessage != null)
               Container(
                 padding: const EdgeInsets.all(10),
                 decoration: BoxDecoration(
                   color: Colors.grey[200],
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Colors.grey[400]!),
                 ),
                 child: Text(
                   _statusMessage!,
                   textAlign: TextAlign.center,
                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                 ),
               ),
             const SizedBox(height: 10),
             ElevatedButton(
               onPressed: canResendEmail ? _sendVerificationEmail : null,
               style: ElevatedButton.styleFrom(
                 minimumSize: const Size.fromHeight(50),
               ),
               child: const Text("Resend Email"),
             ),
             const SizedBox(height: 15),
             TextButton(
               onPressed: () async {
                  await _checkEmailVerified();
                  if (!isEmailVerified && mounted) {
                     setState(() {
                        _statusMessage = "Email not verified yet. Please check your inbox.";
                     });
                  }
               },
               child: const Text("I've Verified My Email"),
             ),
          ],
        ),
      ),
    );
  }
}
