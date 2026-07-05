import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
// 💡 IMPORTANT: Make sure this path correctly imports your machine learning service!
import '../services/face_ml_service.dart'; 

class CameraCaptureScreen extends StatefulWidget {
  final String title;
  const CameraCaptureScreen({super.key, this.title = 'Capture Face'});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _busy = false;
  String? _error;

final FaceMlService _mlService = FaceMlService.instance; //  Use the singleton instance // Instantiate your working ML/TFLite service instance here
  
  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _initFuture = _controller!.initialize();
      await _initFuture;
      
      // Initialize/Load your TFLite models before tracking frames
      await _mlService.init(); 

      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 1. Capture the raw photo file context
      final XFile file = await _controller!.takePicture();
      
      // 2. Initialize the ML Kit interpreter engine
      await FaceMlService.instance.init();

      // 3. Process image path into a normalized 192-length double vector array
      final List<double> faceEmbedding = await _mlService.extractEmbeddingFromImage(file.path);

      // 4. Safely return the vector list array back down to your screens
      if (mounted) {
        Navigator.of(context).pop(faceEmbedding);
      }
    } catch (e) {
      setState(() {
        // Automatically catches FaceMlException errors cleanly
        _error = e.toString(); 
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // UI Theme Config Colors
    final Color brandOrange = const Color(0xFFFF6B00);
    final Color brandOffWhite = const Color(0xFFF9F9F6);
    final Color textDark = const Color(0xFF1F2937);

    return Scaffold(
      backgroundColor: brandOffWhite,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: brandOrange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 48, color: brandOrange),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: textDark, fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => _error = null),
                      style: ElevatedButton.styleFrom(backgroundColor: brandOrange),
                      child: const Text("Try Again", style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            )
          : _controller == null || _initFuture == null
              ? Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange)))
              : FutureBuilder(
                  future: _initFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandOrange)));
                    }
                    return Column(
                      children: [
                        Expanded(child: CameraPreview(_controller!)),
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: ElevatedButton.icon(
                            onPressed: _busy ? null : _capture,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brandOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.face_retouching_natural_rounded),
                            label: Text(_busy ? 'Analyzing Matrix...' : 'Scan My Face', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}