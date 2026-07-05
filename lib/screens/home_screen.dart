import 'package:flutter/material.dart';

import '../services/location_service.dart';
import 'register_screen.dart';
import 'recognize_screen.dart';
import 'registered_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _statusMessage = "";
  bool _isProcessing = false;

  void handleClockIn() async {
    setState(() {
      _statusMessage = "Verifying location perimeters...";
      _isProcessing = true;
    });

    try {
      // Pipeline Step 1: Check Geofence
      bool isAtWork = await LocationService.isEmployeeAtOffice();
      
      if (!isAtWork) {
        setState(() {
          _statusMessage = "Clock-in Failed: You are outside the office boundary.";
          _isProcessing = false;
        });
        return; // Stop execution immediately
      }

      // Pipeline Step 2: Trigger your Working Face Recognition Flow
      setState(() {
        _statusMessage = "Location Verified. Scanning Face...";
      });

      // bool faceMatched = await myFaceRecognitionService.verifyFace(); // Your existing function
      // Placeholder for compilation

        setState(() {
          _statusMessage = "Success! Attendance marked successfully.";
        });
        // TODO: Fire API call to your HR backend database here

    } catch (e) {
      setState(() {
        _statusMessage = "Error: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Attendance - Phase 1')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_statusMessage.isNotEmpty) ...[
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton(
                onPressed: _isProcessing ? null : handleClockIn,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _isProcessing 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Clock In', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isProcessing ? null : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RegisterScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('Register New Face'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isProcessing ? null : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecognizeScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('Recognize Face'),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _isProcessing ? null : () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RegisteredListScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('View Registered Faces'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
