import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
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

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  bool _obscurePassword = true;
  bool _isLoading = false;

  final SignupData data = SignupData();
  bool _loadingLocation = true;
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _floatingController;
  late AnimationController _shimmerController;
  late AnimationController _waveController;
  late AnimationController _particleController;
  late AnimationController _glowController;
  late AnimationController _gradientController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _floatingAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _gradientAnimation;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initAnimations();
  }

  void _initAnimations() {
    // Fade animation - smoother entrance
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    
    // Slide animation - elastic bounce
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    // Pulse animation (for loading)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    
    // Rotate animation (for globe) - slower, smoother
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    // Floating animation (for icons) - more dynamic
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    
    // Shimmer animation (for buttons) - faster, more noticeable
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    
    // Wave animation for background
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    
    // Particle animation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    
    // Glow animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    // Gradient animation for background
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));
    
    _pulseAnimation = Tween<double>(begin: 0.90, end: 1.10).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _rotateAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_rotateController);
    
    _floatingAnimation = Tween<double>(begin: -12, end: 12).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );
    
    _shimmerAnimation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
    
    _waveAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_waveController);
    
    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    
    _gradientAnimation = Tween<double>(begin: 0, end: 1).animate(_gradientController);
    
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    _floatingController.dispose();
    _shimmerController.dispose();
    _waveController.dispose();
    _particleController.dispose();
    _glowController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      // Use LocationService for the logic, but we still need the raw coordinates for the signup data model
      await LocationService.detectLocation();
      
      // Get position for early signup data
      final position = await Geolocator.getLastKnownPosition() ?? 
                       await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      
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
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential? result = await AuthService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (result != null && result.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                  ),
                  child: child,
                ),
              );
            },
          ),
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
        // Create/Sync user profile in Firestore
        await UserService.syncGoogleUser(result.user!.uid);
        
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
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
  Widget build(BuildContext context) {
    // Enhanced loading screen with particle effects
    if (_loadingLocation) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667EEA),
                Color(0xFF764BA2),
                Color(0xFF8B5CF6),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Animated wave background
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: WavePainter(_waveAnimation.value),
                    size: Size.infinite,
                  );
                },
              ),
              
              // Enhanced particle system
              ...List.generate(30, (index) {
                return AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, child) {
                    final progress = (_particleController.value + (index * 0.033)) % 1.0;
                    final angle = (progress * 2 * math.pi) + (index * 0.209);
                    final radius = 100.0 + (index * 15);
                    final x = MediaQuery.of(context).size.width / 2 + math.cos(angle) * radius;
                    final y = MediaQuery.of(context).size.height / 2 + math.sin(angle) * radius;
                    
                    return Positioned(
                      left: x,
                      top: y,
                      child: Opacity(
                        opacity: 0.15 + (math.sin(progress * math.pi) * 0.3),
                        child: Container(
                          width: 6 + (index % 5) * 1.5,
                          height: 6 + (index % 5) * 1.5,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.white,
                                Colors.white.withValues(alpha: 0.5),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.5),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
              
              // Center content with enhanced animations
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Multi-layered rotating and pulsing globe
                    AnimatedBuilder(
                      animation: Listenable.merge([_rotateController, _pulseController, _glowController]),
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer glow ring
                            Transform.scale(
                              scale: _pulseAnimation.value * 1.3,
                              child: Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.white.withValues(alpha: 0.1 * _glowAnimation.value),
                                      Colors.white.withValues(alpha: 0.2 * _glowAnimation.value),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Main globe
                            Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Transform.rotate(
                                angle: _rotateAnimation.value,
                                child: Container(
                                  width: 130,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.9),
                                        Colors.white.withValues(alpha: 0.4),
                                        Colors.white.withValues(alpha: 0.1),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        blurRadius: 50,
                                        spreadRadius: 15,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.public,
                                    size: 70,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            // Orbiting particles
                            ...List.generate(3, (index) {
                              final orbitAngle = _rotateAnimation.value * (index + 1) + (index * 2.094);
                              final orbitRadius = 80.0;
                              return Transform.translate(
                                offset: Offset(
                                  math.cos(orbitAngle) * orbitRadius,
                                  math.sin(orbitAngle) * orbitRadius,
                                ),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                    // Animated app name with glow effect
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        return ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: [
                                Colors.white,
                                Colors.white.withValues(alpha: 0.9),
                                Colors.white,
                              ],
                              stops: [
                                0.0,
                                _glowAnimation.value,
                                1.0,
                              ],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'LocalMe',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontFamily: 'Inter',
                              letterSpacing: 3,
                              shadows: [
                                Shadow(
                                  color: Colors.white,
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share Your Moment',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Custom loading indicator
                    AnimatedBuilder(
                      animation: _rotateController,
                      builder: (context, child) {
                        return SizedBox(
                          width: 50,
                          height: 50,
                          child: CustomPaint(
                            painter: LoadingRingPainter(_rotateAnimation.value),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Animated gradient header (replacing video)
            Stack(
              children: [
                AnimatedBuilder(
                  animation: _gradientController,
                  builder: (context, child) {
                    return Container(
                      height: MediaQuery.of(context).size.height * 0.42,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(const Color(0xFF667EEA), const Color(0xFF764BA2), _gradientAnimation.value)!,
                            Color.lerp(const Color(0xFF764BA2), const Color(0xFF8B5CF6), _gradientAnimation.value)!,
                            Color.lerp(const Color(0xFF8B5CF6), const Color(0xFF667EEA), _gradientAnimation.value)!,
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Animated geometric shapes
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.42,
                      child: CustomPaint(
                        painter: GeometricShapesPainter(_waveAnimation.value),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
                // Animated particles
                AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, child) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.42,
                      child: Stack(
                        children: List.generate(25, (index) {
                          final progress = (_particleController.value * 2 + (index * 0.04)) % 2.0;
                          final y = progress * MediaQuery.of(context).size.height * 0.42;
                          final x = (MediaQuery.of(context).size.width * (index / 25)) +
                              (math.sin(progress * math.pi * 2) * 40);
                          
                          return Positioned(
                            left: x,
                            top: y,
                            child: Opacity(
                              opacity: (1 - (progress / 2)) * 0.6,
                              child: Container(
                                width: 5 + (index % 3),
                                height: 5 + (index % 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
                // Bottom gradient fade
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.5),
                          Colors.white,
                        ],
                      ),
                    ),
                  ),
                ),
                // Eye-catching top-left branding
                Positioned(
                  top: 30,
                  left: 24,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_floatingController, _glowController]),
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _floatingAnimation.value * 0.5),
                          child: Row(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Outer glow
                                  AnimatedBuilder(
                                    animation: _glowController,
                                    builder: (context, child) {
                                      return Container(
                                        width: 65,
                                        height: 65,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.white.withValues(alpha: 0.7 * _glowAnimation.value),
                                              blurRadius: 30,
                                              spreadRadius: 8,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  // Rotating icon container
                                  AnimatedBuilder(
                                    animation: _rotateController,
                                    builder: (context, child) {
                                      return Transform.rotate(
                                        angle: _rotateAnimation.value * 0.2,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.white.withValues(alpha: 0.6),
                                                blurRadius: 20,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Transform.rotate(
                                            angle: -_rotateAnimation.value * 0.2,
                                            child: ShaderMask(
                                              shaderCallback: (bounds) {
                                                return const LinearGradient(
                                                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                                ).createShader(bounds);
                                              },
                                              child: const Icon(
                                                Icons.location_on,
                                                size: 28,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (bounds) {
                                      return const LinearGradient(
                                        colors: [Colors.white, Colors.white],
                                      ).createShader(bounds);
                                    },
                                    child: const Text(
                                      'LocalMe',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        fontFamily: 'Inter',
                                        letterSpacing: 1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black26,
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ShaderMask(
                                      shaderCallback: (bounds) {
                                        return const LinearGradient(
                                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                        ).createShader(bounds);
                                      },
                                      child: const Text(
                                        'Your World, Your Stories',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Floating event icons scattered across header
                ...List.generate(6, (index) {
                  final positions = [
                    {'top': 60.0, 'right': 30.0, 'icon': Icons.camera_alt, 'delay': 0.0},
                    {'top': 140.0, 'right': 80.0, 'icon': Icons.celebration, 'delay': 0.3},
                    {'top': 100.0, 'left': 80.0, 'icon': Icons.favorite, 'delay': 0.6},
                    {'top': 180.0, 'left': 40.0, 'icon': Icons.share, 'delay': 0.9},
                    {'top': 220.0, 'right': 50.0, 'icon': Icons.groups, 'delay': 1.2},
                    {'top': 260.0, 'left': 140.0, 'icon': Icons.explore, 'delay': 1.5},
                  ];
                  
                  final pos = positions[index];
                  
                  return Positioned(
                    top: pos['top'] as double,
                    left: pos['left'] as double?,
                    right: pos['right'] as double?,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: AnimatedBuilder(
                        animation: _floatingController,
                        builder: (context, child) {
                          final floatOffset = math.sin(
                            (_floatingController.value * 2 * math.pi) + 
                            ((pos['delay'] as double) * math.pi)
                          ) * 8;
                          
                          return TweenAnimationBuilder<double>(
                            duration: Duration(milliseconds: 1000 + (index * 150)),
                            tween: Tween(begin: 0.0, end: 1.0),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, floatOffset - (30 * (1 - value))),
                                child: Opacity(
                                  opacity: value * 0.85,
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                pos['icon'] as IconData,
                                size: 18,
                                color: const Color(0xFF667EEA),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ],
            ),

            // Enhanced login form
            Expanded(
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Animated welcome section
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 800),
                          tween: Tween(begin: 0.0, end: 1.0),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(-20 * (1 - value), 0),
                              child: Opacity(opacity: value, child: child),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome Back',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1F2937),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ShaderMask(
                                shaderCallback: (bounds) {
                                  return const LinearGradient(
                                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                  ).createShader(bounds);
                                },
                                child: const Text(
                                  'Share your moment, connect with your world',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),

                        // Email field with enhanced animation
                        _buildAnimatedTextField(
                          controller: _emailController,
                          hint: "Email address",
                          icon: Icons.email_outlined,
                          delay: 200,
                        ),

                        const SizedBox(height: 18),

                        // Password field
                        _buildAnimatedTextField(
                          controller: _passwordController,
                          hint: "Password",
                          icon: Icons.lock_outline,
                          isPassword: true,
                          delay: 400,
                        ),

                        const SizedBox(height: 8),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                ).createShader(bounds);
                              },
                              child: const Text(
                                "Forgot password?",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Premium login button with advanced shimmer
                        AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) {
                            return Container(
                              width: double.infinity,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: const [
                                    Color(0xFF667EEA),
                                    Color(0xFF764BA2),
                                    Color(0xFF8B5CF6),
                                    Color(0xFF667EEA),
                                  ],
                                  stops: [
                                    (_shimmerAnimation.value - 0.5).clamp(0.0, 1.0),
                                    (_shimmerAnimation.value - 0.2).clamp(0.0, 1.0),
                                    _shimmerAnimation.value.clamp(0.0, 1.0),
                                    (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF667EEA).withValues(alpha: 0.5),
                                    blurRadius: 25,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signInWithEmail,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 26,
                                        width: 26,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        "Log in",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 28),

                        // Divider with animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1000),
                          tween: Tween(begin: 0.0, end: 1.0),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Transform.scale(
                                    scaleX: value,
                                    child: Divider(color: Colors.grey.shade300, thickness: 1.5),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Opacity(
                                    opacity: value,
                                    child: Text(
                                      "OR",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Transform.scale(
                                    scaleX: value,
                                    child: Divider(color: Colors.grey.shade300, thickness: 1.5),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 24),

                        // Enhanced Google button with hover effect
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1200),
                          tween: Tween(begin: 0.0, end: 1.0),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: 0.8 + (value * 0.2),
                              child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            height: 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.shade300,
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _signInWithGoogle,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey.shade300, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                backgroundColor: Colors.white,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.g_mobiledata,
                                      size: 28,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    "Continue with Google",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Sign up link with animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1400),
                          tween: Tween(begin: 0.0, end: 1.0),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: child,
                            );
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation, secondaryAnimation) =>
                                          SignupEmailScreen(data: data),
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                        return SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(1, 0),
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          )),
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                child: ShaderMask(
                                  shaderCallback: (bounds) {
                                    return const LinearGradient(
                                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                    ).createShader(bounds);
                                  },
                                  child: const Text(
                                    "Sign up",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Enhanced feature showcase with staggered animation
                        AnimatedBuilder(
                          animation: _floatingController,
                          builder: (context, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildFloatingFeatureIcon(Icons.location_on, 'Local Events', 0),
                                _buildFloatingFeatureIcon(Icons.groups, 'Connect', 1),
                                _buildFloatingFeatureIcon(Icons.public, 'Go Global', 2),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    int delay = 0,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingFeatureIcon(IconData icon, String label, int index) {
    final offset = math.sin((_floatingController.value * 2 * math.pi) + (index * 1.047)) * 10;
    
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 1600 + (index * 200)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Transform.translate(
        offset: Offset(0, offset),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for wave background
class WavePainter extends CustomPainter {
  final double animationValue;
  
  WavePainter(this.animationValue);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    
    final path = Path();
    
    for (int i = 0; i < 3; i++) {
      path.reset();
      final waveHeight = 30.0 + (i * 15);
      final phaseShift = animationValue + (i * 0.5);
      
      path.moveTo(0, size.height / 2);
      
      for (double x = 0; x <= size.width; x += 5) {
        final y = size.height / 2 + 
            math.sin((x / size.width * 4 * math.pi) + (phaseShift * 2 * math.pi)) * waveHeight;
        path.lineTo(x, y);
      }
      
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      
      canvas.drawPath(path, paint);
    }
  }
  
  @override
  bool shouldRepaint(WavePainter oldDelegate) => true;
}

// Custom painter for geometric shapes
class GeometricShapesPainter extends CustomPainter {
  final double animationValue;
  
  GeometricShapesPainter(this.animationValue);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Draw animated circles
    for (int i = 0; i < 5; i++) {
      final progress = (animationValue + (i * 0.2)) % 1.0;
      final radius = 50.0 + (i * 40) + (progress * 50);
      final x = size.width * (0.2 + (i * 0.15));
      final y = size.height * (0.3 + (progress * 0.4));
      
      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint..color = Colors.white.withValues(alpha: 0.08 * (1 - progress)),
      );
    }
    
    // Draw animated lines
    for (int i = 0; i < 8; i++) {
      final progress = (animationValue + (i * 0.125)) % 1.0;
      final x1 = (i / 8) * size.width;
      final y1 = progress * size.height;
      final x2 = ((i + 1) / 8) * size.width;
      final y2 = ((progress + 0.2) % 1.0) * size.height;
      
      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        paint..color = Colors.white.withValues(alpha: 0.05),
      );
    }
  }
  
  @override
  bool shouldRepaint(GeometricShapesPainter oldDelegate) => true;
}

// Custom painter for loading ring
class LoadingRingPainter extends CustomPainter {
  final double animationValue;
  
  LoadingRingPainter(this.animationValue);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Draw multiple rotating arcs
    for (int i = 0; i < 3; i++) {
      final startAngle = (animationValue + (i * 0.33)) * 2 * math.pi;
      final sweepAngle = math.pi / 2;
      
      paint.color = Colors.white.withValues(alpha: 0.3 + (i * 0.2));
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (i * 5)),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(LoadingRingPainter oldDelegate) => true;
}
