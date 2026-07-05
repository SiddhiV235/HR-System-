import 'package:uuid/uuid.dart';
import '../models/registered_face.dart';
import 'face_ml_service.dart';
import 'face_storage_service.dart';

class RegistrationController {
  final FaceStorageService _storageService = FaceStorageService.instance;

  /// Handles the complete synchronized registration flow
  Future<bool> handleUserOnboarding({
    required String email,
    required String password,
    required List<double> faceEmbedding,
  }) async {
    try {
      // Step 1: Commit data to Supabase Cloud Server
      bool cloudSuccess = await _storageService.registerEmployee(
        email: email,
        password: password,
        faceEmbedding: faceEmbedding,
      );

      if (!cloudSuccess) return false;

      // Step 2: Cache the profile details to the local JSON engine for offline processing
      final uniqueId = const Uuid().v4(); // Generates a unique local identifier string
      final localFaceRecord = RegisteredFace(
        id: uniqueId,
        name: email.split('@')[0], // Use the name prefix of the email as a dummy display name
        embedding: faceEmbedding,
      );

      await _storageService.addFace(localFaceRecord);
      
      print("User fully synchronized across local storage and cloud backend arrays.");
      return true;
    } catch (e) {
      print("Synchronized Onboarding Error: $e");
      return false;
    }
  }
}

class LoginVerificationController {
  final FaceStorageService _storageService = FaceStorageService.instance;

  /// Pulls down profile info to determine if a scanned face matches a user account
  Future<bool> checkInUserCredentials({
    required String email,
    required List<double> scannedFaceEmbedding,
  }) async {
    // 1. Fetch the original registered face profile array matrix from Supabase
    print("🔍 Fetching registered embedding for: $email");
    List<double>? registeredEmbedding = await _storageService.getEmbeddingByEmail(email);

    if (registeredEmbedding == null) {
      print("❌ No user registration records matched this email profile.");
      return false;
    }

    print("✅ Retrieved registered embedding (${registeredEmbedding.length} dims), first 5: ${registeredEmbedding.take(5).toList()}");
    print("📊 Scanned embedding (${scannedFaceEmbedding.length} dims), first 5: ${scannedFaceEmbedding.take(5).toList()}");

    final similarityScore = FaceMlService.instance.cosineSimilarity(
      scannedFaceEmbedding,
      registeredEmbedding,
    );

    final threshold = FaceMlService.matchThreshold;
    final passed = similarityScore >= threshold;
    print("🎯 Facial similarity score: $similarityScore (threshold: $threshold) → ${passed ? 'MATCH ✅' : 'NO MATCH ❌'}");
    return passed;
  }
}
