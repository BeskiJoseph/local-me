import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'verify_email_screen.dart';
import '../services/user_service.dart';
import '../core/session/user_session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? result = await AuthService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (result != null) {
        // Reload user to get the latest emailVerified status
        await result.user?.reload();
        // We need to get the user again after reload to check the property
        final user = FirebaseAuth.instance.currentUser;
        
        if (user != null && user.emailVerified) {
          UserSession.update(
            id: user.uid,
            name: user.displayName,
            avatar: user.photoURL,
          );
          // No manual navigation needed - StreamBuilder in main.dart handles it
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        } else {
          // User not verified
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const VerifyEmailScreen()),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Please check your credentials.')),
        );
      }
    } catch (e) {
      String errorMessage = 'Login failed. Please try again.';
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'No account found with this email.';
            break;
          case 'wrong-password':
            errorMessage = 'Incorrect password.';
            break;
          case 'invalid-email':
            errorMessage = 'Invalid email address.';
            break;
          case 'user-disabled':
            errorMessage = 'Account has been disabled.';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many attempts. Try again later.';
            break;
          default:
            errorMessage = 'Login failed: ${e.message}';
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? result = await AuthService.signInWithGoogle();

      if (result != null) {
        // Sync Google User Data to Firestore
        if (result.user != null) {
           await UserService.syncGoogleUser(result.user!.uid);
        }

        // Google accounts usually come verified, but good to check or enforce if policy requires
        await result.user?.reload();
        final user = FirebaseAuth.instance.currentUser;

        if (user != null && user.emailVerified) {
           UserSession.update(
             id: user.uid,
             name: user.displayName,
             avatar: user.photoURL,
           );
           // No manual navigation needed - StreamBuilder in main.dart handles it
           if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
           }
        } else {
           if (mounted) {
             Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const VerifyEmailScreen()),
            );
           }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign in failed.')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Login"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Email
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "Email",
              ),
            ),
            const SizedBox(height: 15),

            // Password
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
              ),
            ),

            const SizedBox(height: 20),

            // Login Button
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signInWithEmail,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Login"),
              ),
            ),

            const SizedBox(height: 20),

            const Text("OR"),

            const SizedBox(height: 20),

            // Google Login
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text("Login with Google"),
                onPressed: _isLoading ? null : _signInWithGoogle,
              ),
            ),

            const SizedBox(height: 15),

            // Test Login Function
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton(
                child: const Text("Test Login Function"),
                onPressed: () {
                  _signInWithEmail();
                },
              ),
            ),

            const SizedBox(height: 15),

            // Debug button
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton(
                child: const Text("Debug Auth Status"),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Check console for debug info')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
