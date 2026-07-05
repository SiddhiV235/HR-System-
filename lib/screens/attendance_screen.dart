import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/face_storage_service.dart';
import '../services/location_service.dart';
import 'camera_capture_screen.dart';
import '../services/face_auth_controller.dart'; 

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
  bool _hasCheckedIn = false;
  bool _hasCheckedOut = false;
  
  String _checkInTime = "--:--";
  String _checkOutTime = "--:--";
  String _statusMessage = "Ready to verify presence.";

  // Theme Palette Config
  final Color brandOrange = const Color(0xFFFF6B00);
  final Color brandGreen = const Color(0xFF10B981);
  final Color brandOffWhite = const Color(0xFFF9F9F6);
  final Color textDark = const Color(0xFF1F2937);

  @override
  void initState() {
    super.initState();
    _loadTodayStatus();
  }

  /// Queries Supabase to see if user has already punched in/out today
 Future<void> _loadTodayStatus() async {
  setState(() => _isLoading = true);
  final record = await _storageService.getTodayAttendance();
  final logs = await _storageService.getAttendanceHistory(); // Add this line

  if (record != null) {
    setState(() {
      _checkInTime = record['check_in'] ?? "--:--";
      _checkOutTime = record['check_out'] ?? "--:--";
      _hasCheckedIn = record['check_in'] != null;
      _hasCheckedOut = record['check_out'] != null;
      _statusMessage = _hasCheckedOut 
          ? "Attendance shift completed for today!" 
          : "You are checked in. Remember to clock out before leaving.";
    });
  }

  setState(() {
    _historyLogs = logs; // Save to internal state
    _isLoading = false;
  });
}

  /// Sequential Execution Core Engine 
  Future<void> _handleAttendancePipeline() async {
    setState(() => _statusMessage = "Verifying location coordinates...");

    try {
      // Pipeline Step 1: Geolocation Fence Verification
      bool isAtOffice = await LocationService.isEmployeeAtOffice();
      if (!isAtOffice) {
        _showStatusDialog("Perimeter Access Error", "You are currently outside the 100m office boundary.", isSuccess: false);
        setState(() => _statusMessage = "Verification failed: Outside office perimeters.");
        return;
      }

      // Pipeline Step 2: Trigger Camera View for Verification
      setState(() => _statusMessage = "Location Verified. Initializing Camera...");
      
      // Navigate to your working face capture view to extract scanned embedding arrays
      final List<double>? scannedEmbedding = await Navigator.push<List<double>>(
        context,
        MaterialPageRoute(builder: (context) => const CameraCaptureScreen()),
      );

      // 💡 FIX: Guard the build context gap securely before using context variables
      if (!mounted) return; 

      if (scannedEmbedding == null) {
        setState(() => _statusMessage = "Scan cancelled.");
        return;
      }

      setState(() => _statusMessage = "Authenticating identity patterns...");

      // Pull current logged-in user email directly from Supabase Authentication Session
      final String? userEmail = Supabase.instance.client.auth.currentUser?.email;
      if (userEmail == null) {
        _showStatusDialog("Auth Error", "User email context session not found.", isSuccess: false);
        return;
      }

      // Pipeline Step 3: Match vectors locally using Euclidean calculations
      bool isFaceMatched = await _verificationController.checkInUserCredentials(
        email: userEmail,
        scannedFaceEmbedding: scannedEmbedding,
      );

      if (!isFaceMatched) {
        _showStatusDialog("Identity Mismatch", "Face verification failed. Embedding patterns do not match profile records.", isSuccess: false);
        setState(() => _statusMessage = "Verification failed: Identity mismatch.");
        return;
      }

      // Process Timestamp Logging
      String formattedTime = DateFormat('hh:mm a').format(DateTime.now());

      if (!_hasCheckedIn) {
        // Commit Clock-In event record entries
        await _storageService.logAttendance(time: formattedTime, isCheckIn: true);
        _showStatusDialog("Checked In!", "Clock-In registered successfully at $formattedTime", isSuccess: true);
      } else {
        // Commit Clock-Out event record entries
        await _storageService.logAttendance(time: formattedTime, isCheckIn: false);
        _showStatusDialog("Checked Out!", "Clock-Out registered successfully at $formattedTime", isSuccess: true);
      }

      // Refresh layout metrics
      _loadTodayStatus();

    } catch (e) {
      _showStatusDialog("Pipeline Error", e.toString(), isSuccess: false);
      setState(() => _statusMessage = "Error occurred during verification.");
    }
  }

  void _showStatusDialog(String title, String body, {required bool isSuccess}) {
    showDialog(
      context: context,
      builder: (ctx) => AppSyncDialog(title: title, body: body, isSuccess: isSuccess, brandGreen: brandGreen, brandOrange: brandOrange, textDark: textDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange))));
    }

    return Scaffold(
      backgroundColor: brandOffWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
           Text("Welcome Back,", style: TextStyle(color: textDark.withValues(alpha: 0.5), fontSize: 16)),
              Text("Employee Terminal", style: TextStyle(color: textDark, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),

              // Timestamps History Panel Matrix
              Row(
                children: [
                  Expanded(
                    child: _buildTimeCard("CHECK IN", _checkInTime, Icons.login_rounded, brandGreen),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimeCard("CHECK OUT", _checkOutTime, Icons.logout_rounded, brandOrange),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Status Tracking Center
              Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: textDark, fontSize: 15, fontWeight: FontWeight.w500)),
              
              const Spacer(),

              // Core Verification Trigger Action Target Point
              if (!_hasCheckedOut)
                Center(
                  child: GestureDetector(
                    onTap: _handleAttendancePipeline,
                    child: Container(
                      height: 180,
                      width: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hasCheckedIn ? brandGreen : brandOrange,
                        boxShadow: [
                          BoxShadow(
                            color: (_hasCheckedIn ? brandGreen : brandOrange).withValues(alpha: 0.35),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _hasCheckedIn ? "CLOCK OUT" : "CLOCK IN",
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 100, color: brandGreen),
                      const SizedBox(height: 8),
                      Text("Shift Completed", style: TextStyle(color: brandGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
              
              const SizedBox(height: 24),
              Text(
                "Recent Logs (Past Week)",
                style: TextStyle(color: textDark, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _historyLogs.isEmpty
                    ? Center(child: Text("No tracking history found.", style: TextStyle(color: textDark.withValues(alpha: 0.4))))
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
                                      log['date'] ?? "",
                                      style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "In: ${log['check_in'] ?? '--:--'} • Out: ${log['check_out'] ?? '--:--'}",
                                      style: TextStyle(color: textDark.withValues(alpha: 0.6), fontSize: 13),
                                    ),
                                  ],
                                ),
                                Icon(
                                  log['check_out'] != null ? Icons.done_all_rounded : Icons.hourglass_top_rounded,
                                  color: log['check_out'] != null ? brandGreen : brandOrange,
                                )
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
              Text(label, style: TextStyle(color: textDark.withValues(alpha: 0.4), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Text(time, style: TextStyle(color: textDark, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class AppSyncDialog extends StatelessWidget {
  final String title;
  final String body;
  final bool isSuccess;
  final Color brandGreen;
  final Color brandOrange;
  final Color textDark;

  const AppSyncDialog({
    Key? key,
    required this.title,
    required this.body,
    required this.isSuccess,
    required this.brandGreen,
    required this.brandOrange,
    required this.textDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(title, style: TextStyle(color: isSuccess ? brandGreen : brandOrange, fontWeight: FontWeight.bold)),
      content: Text(body, style: TextStyle(color: textDark)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("OK", style: TextStyle(color: brandOrange, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}