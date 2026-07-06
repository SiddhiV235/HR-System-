import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/face_ml_service.dart';
import '../services/liveness_service.dart';

/// Camera screen for attendance verification.
/// Runs live liveness checks, then captures and returns a face embedding.
class FaceVerifyScreen extends StatefulWidget {
  final String title;

  const FaceVerifyScreen({
    super.key,
    this.title = 'Verify Identity',
  });

  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _busy = false;
  String? _error;

  final FaceMlService _mlService = FaceMlService.instance;
  final LivenessService _liveness = LivenessService.instance;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.20, // Slightly increased to ensure face is close enough for a clean embedding crop
    ),
  );

  LivenessProgress _progress = const LivenessProgress(
    hasStableFace: false,
    blinkDetected: false,
    headMovementDetected: false,
    hasMinTime: false,
    isLive: false,
    instruction: 'Initializing camera…',
  );

  bool _isProcessingFrame = false;
  int _frameSkipCounter = 0;
  CameraDescription? _camera;

  // Post-liveness frontal face stabilization
  bool _livenessConfirmed = false;
  int _frontalFrameCount = 0;
  static const int _requiredFrontalFrames = 3;
  static const double _maxFrontalYaw = 8.0;

  @override
  void initState() {
    super.initState();
    _liveness.reset();
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }

      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        _camera!,
        ResolutionPreset.medium, // 480x360+ optimized resolution balancing frame rate performance and crop clarity
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      _initFuture = _controller!.initialize();
      await _initFuture;
      await _mlService.init();

      await _controller!.startImageStream(_onCameraFrame);

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera initialization error: $e');
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_busy || _isProcessingFrame || _camera == null) return;

    // Drop frames strategically to allow the CPU thread enough time to calculate without UI lag
    _frameSkipCounter++;
    if (_frameSkipCounter % 3 != 0) return;

    _isProcessingFrame = true;

    try {
      final inputImage = _inputImageFromCamera(image, _camera!);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted || _busy) return;

      if (faces.isEmpty) {
        _liveness.onFaceLost();
        _frontalFrameCount = 0;
        setState(() {
          _progress = LivenessProgress(
            hasStableFace: false,
            blinkDetected: _progress.blinkDetected,
            headMovementDetected: _progress.headMovementDetected,
            hasMinTime: _progress.hasMinTime,
            isLive: false,
            instruction: 'Position your face in the oval',
          );
        });
        return;
      }

      if (faces.length > 1) {
        _frontalFrameCount = 0;
        setState(() {
          _progress = const LivenessProgress(
            hasStableFace: false,
            blinkDetected: false,
            headMovementDetected: false,
            hasMinTime: false,
            isLive: false,
            instruction: 'Only one face should be visible',
          );
        });
        return;
      }

      final face = faces.first;

      // Phase 1: Live movement and blink verification checks
      if (!_livenessConfirmed) {
        final progress = _liveness.processFace(face);

        if (progress.isLive) {
          _livenessConfirmed = true;
          _frontalFrameCount = 0;
          setState(() {
            _progress = LivenessProgress(
              hasStableFace: true,
              blinkDetected: true,
              headMovementDetected: true,
              hasMinTime: true,
              isLive: true,
              instruction: 'Now look straight at the camera',
            );
          });
        } else {
          setState(() => _progress = progress);
        }
        return;
      }

      // Phase 2: Confirm clean frontal alignment before execution
      final yaw = face.headEulerAngleY;
      if (yaw != null && yaw.abs() < _maxFrontalYaw) {
        _frontalFrameCount++;
        setState(() {
          _progress = LivenessProgress(
            hasStableFace: true,
            blinkDetected: true,
            headMovementDetected: true,
            hasMinTime: true,
            isLive: true,
            instruction: 'Hold still… capturing',
          );
        });

        if (_frontalFrameCount >= _requiredFrontalFrames) {
          _busy = true;
          // Defer capture to safely execute outside the stream event frame loop context
          Future.microtask(() => _captureAndReturn());
        }
      } else {
        _frontalFrameCount = 0;
        setState(() {
          _progress = LivenessProgress(
            hasStableFace: true,
            blinkDetected: true,
            headMovementDetected: true,
            hasMinTime: true,
            isLive: true,
            instruction: 'Look straight at the camera',
          );
        });
      }
    } catch (_) {
      // Catch transient exceptions thrown by hardware skips safely
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _captureAndReturn() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      _busy = false;
      return;
    }

    if (mounted) {
      setState(() => _progress = LivenessProgress(
        hasStableFace: true,
        blinkDetected: true,
        headMovementDetected: true,
        hasMinTime: true,
        isLive: true,
        instruction: 'Processing face signature…',
      ));
    }

    try {
      // Step 1: Stop live frame mapping loops before triggering hardware shutter
      await _controller!.stopImageStream();

      // Step 2: Give auto-exposure sensors explicit time to settle down
      await Future.delayed(const Duration(milliseconds: 350));

      // Step 3: Write still image out to cache directory path safely
      final XFile file = await _controller!.takePicture();
      print("📸 Captured verification image: ${file.path}");

      // Step 4: Map file path directly into standard 128 dimension vector
      final List<double> embedding =
          await _mlService.extractEmbeddingFromImage(file.path);
      print("✅ Embedding extracted successfully");

      if (mounted) {
        Navigator.of(context).pop(embedding);
      }
    } catch (e) {
      print("❌ Camera Pipeline Capture Failure: $e");
      if (mounted) {
        setState(() {
          _error = "Recognition framework mapping failed: $e";
          _busy = false;
          _livenessConfirmed = false;
          _frontalFrameCount = 0;
        });

        _liveness.reset();
        try {
          // Restart image streams automatically if hardware fails a photo snap
          await _controller?.startImageStream(_onCameraFrame);
        } catch (_) {}
      }
    }
  }

  InputImage? _inputImageFromCamera(CameraImage image, CameraDescription camera) {
    final rotation = _rotationFromSensor(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    if (image.planes.isEmpty) return null;
    
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFromSensor(int sensorOrientation) {
    return InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;
  }

  @override
  void dispose() {
    try {
      _controller?.stopImageStream();
    } catch (_) {}
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandOrange = Color(0xFFFF6B00);
    const brandOffWhite = Color(0xFFF9F9F6);
    const brandGreen = Color(0xFF10B981);
    const textDark = Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: brandOrange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _error != null
          ? _buildErrorState(brandOrange, textDark)
          : _controller == null || _initFuture == null
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange)))
              : FutureBuilder(
                  future: _initFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange)));
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.55),
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 240,
                            height: 300,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _livenessConfirmed ? brandGreen : brandOrange,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(120),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 24,
                          left: 24,
                          right: 24,
                          child: Column(
                            children: [
                              Text(
                                _progress.instruction,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: _livenessConfirmed ? 1.0 : _progress.completionFraction,
                                backgroundColor: Colors.white24,
                                color: brandGreen,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 32,
                          left: 24,
                          right: 24,
                          child: Column(
                            children: [
                              _buildStepChip('Face detected', _progress.hasStableFace, brandGreen),
                              const SizedBox(height: 8),
                              _buildStepChip('Blink verified', _progress.blinkDetected, brandGreen),
                              const SizedBox(height: 8),
                              _buildStepChip('Movement verified', _progress.headMovementDetected, brandGreen),
                              const SizedBox(height: 8),
                              _buildStepChip('Frontal alignment', _livenessConfirmed && _frontalFrameCount > 0, brandGreen),
                              if (_busy) ...[
                                const SizedBox(height: 20),
                                const CircularProgressIndicator(color: brandOrange),
                                const SizedBox(height: 8),
                                Text(
                                  'Matching face…',
                                  style: TextStyle(color: brandOffWhite.withOpacity(0.9)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildStepChip(String label, bool done, Color doneColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: done ? doneColor : Colors.white54,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: done ? doneColor : Colors.white70,
            fontWeight: done ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(Color brandOrange, Color textDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: brandOrange),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: textDark, fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _busy = false;
                  _livenessConfirmed = false;
                  _frontalFrameCount = 0;
                });
                _liveness.reset();
                _setup();
              },
              style: ElevatedButton.styleFrom(backgroundColor: brandOrange),
              child: const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}