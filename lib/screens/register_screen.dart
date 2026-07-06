import 'package:flutter/material.dart';
import 'camera_capture_screen.dart';
import 'login_screen.dart';
import '../services/face_auth_controller.dart';
import '../services/face_ml_service.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final RegistrationController _registrationController = RegistrationController();
  
  List<double>? _capturedFaceEmbedding;
  bool _isLoading = false;

  // Theme Palette Config
  final Color brandOrange = const Color(0xFFFF6B00);
  final Color brandGreen = const Color(0xFF10B981);
  final Color brandOffWhite = const Color(0xFFF9F9F6);
  final Color textDark = const Color(0xFF1F2937);

  /// Step 1: Open the face scanning camera layer to get the 192 float array

Future<void> _scanFaceForRegistration() async {
    final String? imagePath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const CameraCaptureScreen(title: 'Register Face')),
    );

    // Guard against an unmounted widget before proceeding
    if (!mounted || imagePath == null) return; 

    setState(() => _isLoading = true);
    try {
      final result = await FaceMlService.instance.extractEmbeddingFromImage(imagePath);
      
      // Check mounted state again after the async ML processing gap completes
      if (!mounted) return;

      setState(() {
        _capturedFaceEmbedding = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Face signature captured successfully!")),
      );
    } catch (e) {
      _showErrorSnackBar("Failed to extract face features: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Step 2: Push everything to Supabase and the local file cache
  Future<void> _handleRegistration() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackBar("Please fill out email and password fields.");
      return;
    }

    if (_capturedFaceEmbedding == null) {
      _showErrorSnackBar("You must scan your face to complete registration.");
      return;
    }

    setState(() => _isLoading = true);

    // Call your working unified synchronization onboarding pipeline
    bool isSuccess = await _registrationController.handleUserOnboarding(
      email: email,
      password: password,
      faceEmbedding: _capturedFaceEmbedding!,
    );

    setState(() => _isLoading = false);

    if (isSuccess) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text("Registration Complete", style: TextStyle(color: brandGreen, fontWeight: FontWeight.bold)),
            content: const Text("Your account and facial profile are securely registered."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Redirect straight to the Login gateway screen
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                },
                child: Text("Proceed to Login", style: TextStyle(color: brandOrange, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }
    } else {
      _showErrorSnackBar("Registration failed. Please check your credentials or network.");
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: brandOrange),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandOffWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.person_add_alt_1_rounded, size: 64, color: brandOrange),
                  const SizedBox(height: 16),
                  Text(
                    "New Employee",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textDark, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Register credentials and biometrics",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textDark.withValues(alpha: 0.5), fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // Email Input Field
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Workspace Email",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password Input Field
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Secure Password",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Face Capture Trigger Section
                  OutlinedButton.icon(
                    onPressed: _scanFaceForRegistration,
                    icon: Icon(
                      _capturedFaceEmbedding != null ? Icons.check_circle_rounded : Icons.face_rounded,
                      color: _capturedFaceEmbedding != null ? brandGreen : brandOrange,
                    ),
                    label: Text(
                      _capturedFaceEmbedding != null ? "FACE CAPTURED" : "SCAN BIOMETRIC FACE",
                      style: TextStyle(
                        color: _capturedFaceEmbedding != null ? brandGreen : brandOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: _capturedFaceEmbedding != null ? brandGreen : brandOrange,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Primary Submission Action Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("REGISTER NOW", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),

                  // Route link to toggle back to login screen view
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                      );
                    },
                    child: Text("Already registered? Sign In Here", style: TextStyle(color: brandOrange)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}