import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart'; // Or your initial routing screen
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Configuration Globally
  await Supabase.initialize(
    url: 'https://vixafwsyjpzhpohnyahz.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZpeGFmd3N5anB6aHBvaG55YWh6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMwOTY2NzQsImV4cCI6MjA5ODY3MjY3NH0.tNe4LnC8F_jrQxcWDlKGDElmJmLrxr4XkrPSyGHn5NM',
  );

  runApp(const FaceAttendanceApp());
}

class FaceAttendanceApp extends StatelessWidget {
  const FaceAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Attendance System',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF9F9F6), // Brand Off-White
        primaryColor: const Color(0xFFFF6B00),           // Brand Orange
      ),
      // 💡 FIX: Route directly to Login or Register instead of the old 4-button menu screen
      home: Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen() // Shows the modern Login Screen gateway first
          : const HomeScreen(), // Bypasses straight to Terminal if active session exists
    );
  }
}