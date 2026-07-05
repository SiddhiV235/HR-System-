import 'package:uuid/uuid.dart';
import '../models/registered_face.dart';
import '../services/face_storage_service.dart';

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
    List<double>? registeredEmbedding = await _storageService.getEmbeddingByEmail(email);

    if (registeredEmbedding == null) {
      print("No user registration records matched this email profile.");
      return false;
    }

    // 2. Run Euclidean Distance comparison calculations using your ML utility
    double distanceThreshold = 1.0; // Adjust this sensitivity parameter based on your TFLite model constraints
    double calculatedDistance = calculateEuclideanDistance(scannedFaceEmbedding, registeredEmbedding);

    print("Calculated facial distance coefficient metric score: $calculatedDistance");
    return calculatedDistance < distanceThreshold;
  }

  /// Basic Euclidean Distance helper algorithm framework
  double calculateEuclideanDistance(List<double> v1, List<double> v2) {
    double sum = 0.0;
    for (int i = 0; i < v1.length; i++) {
      double diff = v1[i] - v2[i];
      sum += diff * diff;
    }
    return sum; // Returns the variance factor deviation score
  }
}
