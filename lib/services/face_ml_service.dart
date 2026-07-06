import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceMlException implements Exception {
  final String message;
  FaceMlException(this.message);
  @override
  String toString() => message;
}

class FaceMlService {
  FaceMlService._internal();
  static final FaceMlService instance = FaceMlService._internal();

  static const int inputSize = 112;
  static const int embeddingSize = 192;

  // Set true temporarily while tuning — prints similarity scores to console
  static const bool debugLogging = true;

  static const double matchThreshold = 0.68;

  Interpreter? _interpreter;

  bool get isReady => _interpreter != null;

  Future<void> init() async {
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
    print("TFLite model loaded successfully");
  }

  void dispose() {
    _interpreter?.close();
  }

  Future<List<double>> extractEmbeddingFromImage(String imagePath) async {
    await init();

    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableTracking: false,
        enableLandmarks: true, // ✅ needed for eye alignment
      ),
    );

    try {
      final bytes = await File(imagePath).readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw FaceMlException('Could not read the captured image.');
      }
      decoded = img.bakeOrientation(decoded);

      // --- Pass 1: detect face + landmarks on the raw image ---
      final firstPass = await _detectFaces(detector, decoded);
      if (firstPass.isEmpty) {
        throw FaceMlException('No face detected. Try again with better lighting.');
      }
      if (firstPass.length > 1) {
        throw FaceMlException('Multiple faces detected. Keep only one face in view.');
      }

      Face face = firstPass.first;
      img.Image workingImage = decoded;

      // --- Alignment: rotate so the eyes are level ---
      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

      if (leftEye != null && rightEye != null) {
        final dx = (rightEye.x - leftEye.x).toDouble();
        final dy = (rightEye.y - leftEye.y).toDouble();
        final angleDeg = atan2(dy, dx) * 180 / pi;

        if (angleDeg.abs() > 1.0) {
          try {
            // Negative sign corrects tilt direction (image coords: y grows downward)
            final rotated = img.copyRotate(decoded, angle: -angleDeg);
            final secondPass = await _detectFaces(detector, rotated);
            if (secondPass.length == 1) {
              workingImage = rotated;
              face = secondPass.first;
            }
            // If re-detection fails after rotation, silently fall back to
            // the original unrotated image + face instead of throwing.
          } catch (_) {
            // fall back to unrotated
          }
        }
      }

      final cropped = _cropFaceWithMargin(workingImage, face.boundingBox, marginRatio: 0.25);

      final resized = img.copyResize(
        cropped,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.cubic,
      );

      final embedding = _runModel(resized);
      final normalized = _l2Normalize(embedding);

      return normalized;
    } finally {
      detector.close();
    }
  }

  /// Writes [image] to a temp file and runs ML Kit face detection on it.
  Future<List<Face>> _detectFaces(FaceDetector detector, img.Image image) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/face_extract_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await tempFile.writeAsBytes(img.encodeJpg(image, quality: 95));
    try {
      final inputImage = InputImage.fromFilePath(tempFile.path);
      return await detector.processImage(inputImage);
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  /// Crops the face box with extra margin on every side so the model sees
  /// forehead/chin/ears context instead of a razor-tight crop.
  img.Image _cropFaceWithMargin(img.Image source, Rect box, {double marginRatio = 0.25}) {
    final marginX = box.width * marginRatio;
    final marginY = box.height * marginRatio;

    final left = (box.left - marginX).round().clamp(0, source.width - 1);
    final top = (box.top - marginY).round().clamp(0, source.height - 1);
    final right = (box.right + marginX).round().clamp(left + 1, source.width);
    final bottom = (box.bottom + marginY).round().clamp(top + 1, source.height);

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
              (pixel.r - 127.5) / 127.5,
              (pixel.g - 127.5) / 127.5,
              (pixel.b - 127.5) / 127.5,
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

  double cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    if (debugLogging) {
      print('🔬 cosineSimilarity = $dot');
    }
    return dot;
  }

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

class MatchResult {
  final String id;
  final String name;
  final double score;
  MatchResult({required this.id, required this.name, required this.score});
}