import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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

      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _error = 'Camera initialization error: $e');
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
      // 1. Capture the raw photo file
      final XFile file = await _controller!.takePicture();
      
      // 2. Return the file path back to the calling screen safely
      if (mounted) {
        Navigator.of(context).pop(file.path);
      }
    } catch (e) {
      setState(() {
        _error = "Capture failed: ${e.toString()}"; 
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
                                : const Icon(Icons.camera_alt_rounded),
                            label: Text(_busy ? 'Capturing Frame...' : 'Take Photo', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}