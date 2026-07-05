import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
// Make sure this points to your file containing FaceStorageService
import 'face_storage_service.dart'; 

/// Thrown for any expected failure during face extraction
class FaceMlException implements Exception {
  final String message;
  FaceMlException(this.message);
  @override
  String toString() => message;
}

/// Handles Face Detection, Cropping, and TFLite embeddings.
class FaceMlService {
  FaceMlService._internal();
  static final FaceMlService instance = FaceMlService._internal();

  static const int inputSize = 112;
  static const int embeddingSize = 192;

  /// Cosine-similarity threshold above which two embeddings are considered the same person.
  static const double matchThreshold = 0.62;

  Interpreter? _interpreter;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableTracking: false,
    ),
  );

  bool get isReady => _interpreter != null;

  Future<void> init() async {
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
  }

  void dispose() {
    _faceDetector.close();
    _interpreter?.close();
  }

  /// Takes the path of a captured photo, finds the face, and returns its normalized 192-d embedding.
  Future<List<double>> extractEmbeddingFromImage(String imagePath) async {
    await init();

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      throw FaceMlException('No face detected. Try again with better lighting and the face centered.');
    }
    if (faces.length > 1) {
      throw FaceMlException('Multiple faces detected. Make sure only one face is in frame.');
    }

    final face = faces.first;

    final bytes = await File(imagePath).readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw FaceMlException('Could not read the captured image.');
    }
    decoded = img.bakeOrientation(decoded);

    final cropped = _cropFace(decoded, face.boundingBox);
    final resized = img.copyResize(
      cropped,
      width: inputSize,
      height: inputSize,
    );

    final embedding = _runModel(resized);
    return _l2Normalize(embedding);
  }

  img.Image _cropFace(img.Image source, Rect box) {
    final padW = box.width * 0.15;
    final padH = box.height * 0.15;

    final left = (box.left - padW).round().clamp(0, source.width - 1);
    final top = (box.top - padH).round().clamp(0, source.height - 1);
    final right = (box.right + padW).round().clamp(left + 1, source.width);
    final bottom = (box.bottom + padH).round().clamp(top + 1, source.height);

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  List<double> _runModel(img.Image faceImage) {
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = faceImage.getPixel(x, y);
            return [
              (pixel.r - 127.5) / 128.0,
              (pixel.g - 127.5) / 128.0,
              (pixel.b - 127.5) / 128.0,
            ];
          },
        ),
      ),
    );

    final output = List.generate(1, (_) => List.filled(embeddingSize, 0.0));
    _interpreter!.run(input, output);
    return List<double>.from(output[0]);
  }

  List<double> _l2Normalize(List<double> vec) {
    double sumSq = 0;
    for (final v in vec) {
      sumSq += v * v;
    }
    final norm = sqrt(sumSq);
    if (norm == 0) return vec;
    return vec.map((v) => v / norm).toList();
  }

  /// ✅ RESTORED: Cosine similarity between two already-normalized embeddings.
  double cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /// Compares [embedding] against candidate lists
  MatchResult? findBestMatch(
    List<double> embedding,
    List<({String id, String name, List<double> embedding})> candidates,
  ) {
    String? bestId;
    String? bestName;
    double bestScore = -1;

    for (final c in candidates) {
      final score = cosineSimilarity(embedding, c.embedding);
      if (score > bestScore) {
        bestScore = score;
        bestId = c.id;
        bestName = c.name;
      }
    }

    if (bestId == null || bestScore < matchThreshold) return null;
    return MatchResult(id: bestId, name: bestName!, score: bestScore);
  }
}

/// 💡 MOVED OUTSIDE: Cleaner, distinct controller for verification tasks
class LoginVerificationController {
  final FaceStorageService _storageService = FaceStorageService.instance;

  Future<bool> checkInUserCredentials({
    required String email,
    required List<double> scannedFaceEmbedding,
  }) async {
    List<double>? registeredEmbedding = await _storageService.getEmbeddingByEmail(email);

    if (registeredEmbedding == null) {
      print("No user registration records matched this email profile.");
      return false;
    }

    // Now cleanly references the restored similarity method
    double similarityScore = FaceMlService.instance.cosineSimilarity(
      scannedFaceEmbedding, 
      registeredEmbedding,
    );

    print("Calculated facial similarity match index metric score: $similarityScore");
    return similarityScore >= FaceMlService.matchThreshold; 
  }
}

class MatchResult {
  final String id;
  final String name;
  final double score;
  MatchResult({required this.id, required this.name, required this.score});
}