import 'package:flutter/material.dart';

import '../services/face_ml_service.dart';
import '../services/face_storage_service.dart';
import 'camera_capture_screen.dart';

class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  bool _busy = false;
  String _status = 'Capture a photo to check if the face is known.';

  Future<void> _captureAndRecognize() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const CameraCaptureScreen(title: 'Recognize Face'),
      ),
    );
    if (path == null) return;

    setState(() {
      _busy = true;
      _status = 'Detecting face and extracting embedding...';
    });

    try {
      final embedding =
          await FaceMlService.instance.extractEmbeddingFromImage(path);

      final registered = await FaceStorageService.instance.loadAll();
      if (registered.isEmpty) {
        setState(() {
          _busy = false;
          _status = 'No faces registered yet. Register someone first.';
        });
        return;
      }

      final candidates = registered
          .map((f) => (id: f.id, name: f.name, embedding: f.embedding))
          .toList();

      final match =
          FaceMlService.instance.findBestMatch(embedding, candidates);

      setState(() {
        _busy = false;
        if (match != null) {
          _status = 'MATCH: ${match.name}\n'
              'confidence: ${(match.score * 100).toStringAsFixed(1)}%';
        } else {
          _status = 'UNKNOWN FACE — not in the registered list.';
        }
      });
    } on FaceMlException catch (e) {
      setState(() {
        _busy = false;
        _status = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recognize Face')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _captureAndRecognize,
                child: _busy
                    ? const CircularProgressIndicator()
                    : const Text('Capture & Check'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
