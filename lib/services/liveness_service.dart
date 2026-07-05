import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Passive + active liveness checks using ML Kit face landmarks.
/// Requires a live face with a natural blink and slight head movement
/// to defeat printed photos and static screen replays.
class LivenessService {
  LivenessService._internal();
  static final LivenessService instance = LivenessService._internal();

  static const int minStableFrames = 8;
  static const double eyeOpenThreshold = 0.65;
  static const double eyeClosedThreshold = 0.35;
  static const double minHeadMovementDegrees = 7.0;
  static const Duration minObservationTime = Duration(milliseconds: 1500);

  int _consecutiveFaceFrames = 0;
  bool _eyesWereOpen = false;
  bool _blinkDetected = false;
  double? _initialYaw;
  bool _headMovementDetected = false;
  DateTime? _firstFaceSeenAt;

  /// Resets all tracked liveness state. Call when opening the camera.
  void reset() {
    _consecutiveFaceFrames = 0;
    _eyesWereOpen = false;
    _blinkDetected = false;
    _initialYaw = null;
    _headMovementDetected = false;
    _firstFaceSeenAt = null;
  }

  /// Processes a single detected face frame and returns current liveness progress.
  LivenessProgress processFace(Face face) {
    _consecutiveFaceFrames++;

    if (_firstFaceSeenAt == null) {
      _firstFaceSeenAt = DateTime.now();
    }

    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;

    if (leftEye != null && rightEye != null) {
      final avgOpen = (leftEye + rightEye) / 2;

      if (avgOpen >= eyeOpenThreshold) {
        _eyesWereOpen = true;
      }

      if (_eyesWereOpen && avgOpen <= eyeClosedThreshold) {
        _blinkDetected = true;
      }
    }

    final yaw = face.headEulerAngleY;
    if (yaw != null) {
      _initialYaw ??= yaw;
      if ((yaw - _initialYaw!).abs() >= minHeadMovementDegrees) {
        _headMovementDetected = true;
      }
    }

    final elapsed = DateTime.now().difference(_firstFaceSeenAt!);
    final hasStableFace = _consecutiveFaceFrames >= minStableFrames;
    final hasMinTime = elapsed >= minObservationTime;
    final isLive = hasStableFace &&
        _blinkDetected &&
        _headMovementDetected &&
        hasMinTime;

    return LivenessProgress(
      hasStableFace: hasStableFace,
      blinkDetected: _blinkDetected,
      headMovementDetected: _headMovementDetected,
      hasMinTime: hasMinTime,
      isLive: isLive,
      instruction: _currentInstruction(hasStableFace),
    );
  }

  /// Call when no face is detected in a frame to avoid stale progress.
  void onFaceLost() {
    if (_consecutiveFaceFrames > 0 && _consecutiveFaceFrames < minStableFrames) {
      _consecutiveFaceFrames = 0;
      _firstFaceSeenAt = null;
      _initialYaw = null;
    }
  }

  String _currentInstruction(bool hasStableFace) {
    if (!hasStableFace) return 'Center your face in the frame';
    if (!_blinkDetected) return 'Blink naturally';
    if (!_headMovementDetected) return 'Turn your head slightly left or right';
    return 'Hold still — verifying…';
  }
}

class LivenessProgress {
  final bool hasStableFace;
  final bool blinkDetected;
  final bool headMovementDetected;
  final bool hasMinTime;
  final bool isLive;
  final String instruction;

  const LivenessProgress({
    required this.hasStableFace,
    required this.blinkDetected,
    required this.headMovementDetected,
    required this.hasMinTime,
    required this.isLive,
    required this.instruction,
  });

  double get completionFraction {
    int steps = 0;
    if (hasStableFace) steps++;
    if (blinkDetected) steps++;
    if (headMovementDetected) steps++;
    if (hasMinTime) steps++;
    return steps / 4;
  }
}
