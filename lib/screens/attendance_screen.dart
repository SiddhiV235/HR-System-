import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/face_storage_service.dart';
import '../services/location_service.dart';
import '../services/face_auth_controller.dart';
import 'face_verify_screen.dart';
import 'camera_capture_screen.dart'; // Ensure these routes are imported correctly
import 'login_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final FaceStorageService _storageService = FaceStorageService.instance;
  final LoginVerificationController _verificationController = LoginVerificationController();

  List<Map<String, dynamic>> _historyLogs = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasCheckedIn = false;
  bool _hasCheckedOut = false;

  String _checkInTime = '--:--';
  String _checkOutTime = '--:--';
  String _statusMessage = 'Ready to verify presence.';

  final Color brandOrange = const Color(0xFFFF6B00);
  final Color brandGreen = const Color(0xFF10B981);
  final Color brandOffWhite = const Color(0xFFF9F9F6);
  final Color textDark = const Color(0xFF1F2937);

  @override
  void initState() {
    super.initState();
    _loadTodayStatus();
  }

  Future<void> _loadTodayStatus() async {
    setState(() => _isLoading = true);

    final record = await _storageService.getTodayAttendance();
    final logs = await _storageService.getAttendanceHistory();

    if (record != null) {
      setState(() {
        _checkInTime = record['check_in'] ?? '--:--';
        _checkOutTime = record['check_out'] ?? '--:--';
        _hasCheckedIn = record['check_in'] != null;
        _hasCheckedOut = record['check_out'] != null;
        _statusMessage = _hasCheckedOut
            ? 'Attendance shift completed for today!'
            : 'You are checked in. Remember to check out before leaving.';
      });
    } else {
      setState(() {
        _checkInTime = '--:--';
        _checkOutTime = '--:--';
        _hasCheckedIn = false;
        _hasCheckedOut = false;
        _statusMessage = 'Ready to verify presence.';
      });
    }

    setState(() {
      _historyLogs = logs;
      _isLoading = false;
    });
  }

  Future<void> _handleCheckIn() async {
    if (_hasCheckedIn || _isProcessing) return;
    await _runAttendancePipeline(isCheckIn: true);
  }

  Future<void> _handleCheckOut() async {
    if (!_hasCheckedIn || _hasCheckedOut || _isProcessing) return;
    await _runAttendancePipeline(isCheckIn: false);
  }

  Future<void> _runAttendancePipeline({required bool isCheckIn}) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Verifying location…';
    });

    try {
      final isAtOffice = await LocationService.isEmployeeAtOffice();
      if (!isAtOffice) {
        _showSnack('You are outside the allowed office zone.', isError: true);
        setState(() => _statusMessage = 'Check-in failed: outside office boundary.');
        return;
      }

      setState(() => _statusMessage = 'Location verified. Opening camera…');

      if (!mounted) return;

      final List<double>? scannedEmbedding = await Navigator.push<List<double>>(
        context,
        MaterialPageRoute(
          builder: (context) => FaceVerifyScreen(
            title: isCheckIn ? 'Check In Verification' : 'Check Out Verification',
          ),
        ),
      );

      if (!mounted) return;

      if (scannedEmbedding == null) {
        setState(() => _statusMessage = 'Verification cancelled.');
        return;
      }

      setState(() => _statusMessage = 'Matching face profile…');

      final userEmail = Supabase.instance.client.auth.currentUser?.email;
      if (userEmail == null) {
        _showSnack('Session expired. Please sign in again.', isError: true);
        return;
      }

      final isFaceMatched = await _verificationController.checkInUserCredentials(
        email: userEmail,
        scannedFaceEmbedding: scannedEmbedding,
      );

      if (!isFaceMatched) {
        _showSnack('Face not recognized. Please try again.', isError: true);
        setState(() => _statusMessage = 'Verification failed: face mismatch.');
        return;
      }

      final formattedTime = DateFormat('hh:mm a').format(DateTime.now());

      await _storageService.logAttendance(time: formattedTime, isCheckIn: isCheckIn);

      _showSnack(isCheckIn ? 'Recognized and checked in at $formattedTime' : 'Recognized and checked out at $formattedTime');
      
      await _loadTodayStatus();
    } catch (e) {
      _showSnack(e.toString(), isError: true);
      setState(() => _statusMessage = 'An error occurred during verification.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleUpdateFace() async {
    setState(() => _statusMessage = "Opening biometric scanner for re-registration...");

    try {
      final List<double>? newEmbedding = await Navigator.push<List<double>>(
        context,
        MaterialPageRoute(builder: (context) => const CameraCaptureScreen()),
      );

      if (!mounted) return;

      if (newEmbedding == null) {
        setState(() => _statusMessage = "Update face cancelled.");
        return;
      }

      setState(() => _statusMessage = "Uploading new facial signature patterns...");

      bool updateSuccess = await _storageService.updateFaceEmbedding(newEmbedding);

      if (updateSuccess) {
        _showSnack("Your new face biometric signature has been saved.", isError: false);
      } else {
        _showSnack("Could not save your new biometric scan.", isError: true);
      }
    } catch (e) {
      _showSnack("Pipeline Error: ${e.toString()}", isError: true);
    } finally {
      _loadTodayStatus();
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? brandOrange : brandGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: brandOffWhite,
      appBar: AppBar(
        title: const Text("Terminal Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: brandOrange,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: Colors.white,
            onSelected: (value) async {
              if (value == 'update_face') {
                _handleUpdateFace();
              } else if (value == 'logout') {
                await _storageService.signOutEmployee();
                if (!mounted) return;
                
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'update_face',
                child: Row(
                  children: [
                    Icon(Icons.face_rounded, color: brandOrange, size: 20),
                    const SizedBox(width: 10),
                    Text("Update Face ID", style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Text("Log Out", style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ), // 💡 FIXED: Added the missing closing parenthesis to seal the AppBar constructor
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome Back,',
                style: TextStyle(color: textDark.withValues(alpha: 0.5), fontSize: 16),
              ),
              Text(
                Supabase.instance.client.auth.currentUser?.email?.split('@').first ?? 'Employee',
                style: TextStyle(color: textDark, fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildTimeCard('CHECK IN', _checkInTime, Icons.login_rounded, brandGreen)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTimeCard('CHECK OUT', _checkOutTime, Icons.logout_rounded, brandOrange)),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: textDark, fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (!_hasCheckedOut) ...[
                if (!_hasCheckedIn)
                  _buildActionButton(
                    label: 'CHECK IN',
                    color: brandOrange,
                    icon: Icons.login_rounded,
                    onPressed: _isProcessing ? null : _handleCheckIn,
                  ),
                if (_hasCheckedIn && !_hasCheckedOut) ...[
                  _buildActionButton(
                    label: 'CHECK OUT',
                    color: brandGreen,
                    icon: Icons.logout_rounded,
                    onPressed: _isProcessing ? null : _handleCheckOut,
                  ),
                ],
              ] else
                Column(
                  children: [
                    Icon(Icons.verified_user_rounded, size: 80, color: brandGreen),
                    const SizedBox(height: 8),
                    Text(
                      'Shift Completed',
                      style: TextStyle(color: brandGreen, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              if (_isProcessing) ...[
                const SizedBox(height: 20),
                Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange))),
              ],
              const SizedBox(height: 24),
              Text(
                'Recent Logs (Past Week)',
                style: TextStyle(color: textDark, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _historyLogs.isEmpty
                    ? Center(
                        child: Text(
                          'No tracking history found.',
                          style: TextStyle(color: textDark.withValues(alpha: 0.4)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _historyLogs.length,
                        itemBuilder: (context, index) {
                          final log = _historyLogs[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: textDark.withValues(alpha: 0.05)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      log['date'] ?? '',
                                      style: TextStyle(
                                        color: textDark,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'In: ${log['check_in'] ?? '--:--'} • Out: ${log['check_out'] ?? '--:--'}',
                                      style: TextStyle(color: textDark.withValues(alpha: 0.6), fontSize: 13),
                                    ),
                                  ],
                                ),
                                Icon(
                                  log['check_out'] != null ? Icons.done_all_rounded : Icons.hourglass_top_rounded,
                                  color: log['check_out'] != null ? brandGreen : brandOrange,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      ),
    );
  }

  Widget _buildTimeCard(String label, String time, IconData icon, Color stateColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stateColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: stateColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: textDark.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(time, style: TextStyle(color: textDark, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}