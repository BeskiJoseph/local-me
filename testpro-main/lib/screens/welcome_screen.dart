import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/signup_data.dart';
import 'signup/signup_email.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import 'package:geolocator/geolocator.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool _isLoading = false;
  bool _loadingLocation = true;

  final SignupData data = SignupData();

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      await LocationService.detectLocation();
      
      Position? position;
      if (kIsWeb) {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      } else {
        position = await Geolocator.getLastKnownPosition() ?? 
                   await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      }
      
      data.latitude = position.latitude;
      data.longitude = position.longitude;
    } catch (e) {
      if (kDebugMode) debugPrint("Location initialization error: $e");
    }

    if (mounted) {
      setState(() {
        _loadingLocation = false;
      });
    }
  }

  Future<void> _signInWithEmail() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential? result = await AuthService.signInWithEmail(
        emailController.text.trim(),
        passwordController.text,
      );

      if (result != null && result.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage = _getErrorMessage(e.code);
        _showSnackBar(errorMessage, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Invalid email address.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      UserCredential? result = await AuthService.signInWithGoogle();
      if (result != null && result.user != null && mounted) {
        await UserService.syncGoogleUser(result.user!.uid);
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted && !e.toString().contains('popup_closed')) {
        _showSnackBar('Google sign in failed. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade400 : Colors.green.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Loading screen
    if (_loadingLocation) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7B4EFF), Color(0xFFE84393)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 20),
                Text(
                  'LocalMe',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Share Your Moment',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox(
        height: screenHeight,
        child: Stack(
          children: [
            // White Background
            Container(
              color: Colors.white,
            ),

            // Smooth Curved Gradient Background
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: _SmoothWaveClipper(),
                child: Container(
                  height: screenHeight * 0.68,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF7B4EFF), Color(0xFFE84393)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),

            // Content
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 50),

                      // Logo
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child: Image.asset(
                            "assets/logo.png",
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // App Name
                      const Text(
                        "LocalMe",
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Tagline
                      const Text(
                        "Share Your Moment",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Layered White Card
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 400),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Email Field
                              TextField(
                                controller: emailController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF5F5F5),
                                  hintText: "Email Address",
                                  hintStyle: const TextStyle(
                                    color: Color(0xFFAAAAAA),
                                    fontSize: 14,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.email_outlined,
                                    color: Color(0xFF999999),
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Password Field
                              TextField(
                                controller: passwordController,
                                obscureText: obscurePassword,
                                enabled: !_isLoading,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF5F5F5),
                                  hintText: "Password",
                                  hintStyle: const TextStyle(
                                    color: Color(0xFFAAAAAA),
                                    fontSize: 14,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Color(0xFF999999),
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: const Color(0xFF999999),
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        obscurePassword = !obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Login Button
                              Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF7B4EFF), Color(0xFFE84393)],
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF7B4EFF).withOpacity(0.4),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _signInWithEmail,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          "Login",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Divider
                              Row(
                                children: const [
                                  Expanded(
                                    child: Divider(
                                      color: Color(0xFFE0E0E0),
                                      thickness: 1,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      "or",
                                      style: TextStyle(
                                        color: Color(0xFF9E9E9E),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: Color(0xFFE0E0E0),
                                      thickness: 1,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // Google Button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : _signInWithGoogle,
                                  icon: Image.network(
                                    "https://cdn-icons-png.flaticon.com/512/2991/2991148.png",
                                    height: 22,
                                    width: 22,
                                  ),
                                  label: const Text(
                                    "Continue with Google",
                                    style: TextStyle(
                                      color: Color(0xFF1A1A1A),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF5F5F5),
                                    shadowColor: Colors.transparent,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Sign Up Text
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Don't have an account? ",
                                    style: TextStyle(
                                      color: Color(0xFF7A7A7A),
                                      fontSize: 13,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SignupEmailScreen(data: data),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      "Sign up",
                                      style: TextStyle(
                                        color: Color(0xFF7B4EFF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Clean Smooth Wave Clipper
class _SmoothWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    
    // Start from top left
    path.lineTo(0, size.height - 60);
    
    // Create ONE smooth wave using cubic bezier
    path.cubicTo(
      size.width * 0.25, size.height,        // First control point
      size.width * 0.75, size.height - 120,  // Second control point
      size.width, size.height - 60,          // End point
    );
    
    // Complete the path
    path.lineTo(size.width, 0);
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}