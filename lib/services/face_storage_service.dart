import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/registered_face.dart';

/// Simple local persistence: all registered faces are kept in a single
/// JSON file in the app's documents directory. No backend needed.
class FaceStorageService {
  final SupabaseClient _client = Supabase.instance.client;

Future<bool> registerEmployee({
    required String email,
    required String password,
    required List<double> faceEmbedding,
  }) async {
    try {
      // 1. Authenticate user account setup inside Supabase Auth Engine
      final AuthResponse response = await _client.auth.signUp(
        email: email,
        password: password,
      );

      final User? user = response.user;
      if (user == null) {
        print("❌ Supabase Auth failed to generate a user profile.");
        return false;
      }

      print("⚡ Auth user generated with ID: ${user.id}. Syncing face matrix array...");

      // 2. Insert profile information mapping explicitly into PostgreSQL
      await _client.from('profiles').insert({
        'id': user.id,
        'email': email.trim(),
        // 💡 FIX: Map the array explicitly as a primitive type sequence
        'face_embedding': faceEmbedding.map((e) => e.toDouble()).toList(), 
      });

      print("✅ Profile successfully written to cloud tables.");
      return true;
    } catch (e) {
      // This will capture the exact column validation error text in your console logs
      print("❌ Registration Service Error details: $e");
      return false; 
    }
  } 

  /// Fetches a registered profile's face vector embedding using their email address
  Future<List<double>?> getEmbeddingByEmail(String email) async {
    try {
      final data = await _client
          .from('profiles')
          .select('face_embedding')
          .eq('email', email)
          .maybeSingle();

      if (data == null || data['face_embedding'] == null) return null;

      // Convert dynamic database list explicitly back to a typed double array
      List<dynamic> rawList = data['face_embedding'];
      return rawList.map((item) => double.parse(item.toString())).toList();
    } catch (e) {
      print("Fetch Embedding Error: $e");
      return null;
    }
  }
  FaceStorageService._internal();
  static final FaceStorageService instance = FaceStorageService._internal();

  static const String _fileName = 'registered_faces.json';
  List<RegisteredFace>? _cache;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<RegisteredFace>> loadAll() async {
    if (_cache != null) return _cache!;
    final file = await _getFile();
    if (!await file.exists()) {
      _cache = [];
      return _cache!;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      _cache = [];
      return _cache!;
    }
    final List<dynamic> jsonList = jsonDecode(content);
    _cache = jsonList
        .map((e) => RegisteredFace.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cache!;
  }

  Future<void> _saveAll(List<RegisteredFace> faces) async {
    final file = await _getFile();
    final jsonStr = jsonEncode(faces.map((f) => f.toJson()).toList());
    await file.writeAsString(jsonStr);
    _cache = faces;
  }

  Future<void> addFace(RegisteredFace face) async {
    final faces = await loadAll();
    faces.add(face);
    await _saveAll(faces);
  }

  Future<void> deleteFace(String id) async {
    final faces = await loadAll();
    faces.removeWhere((f) => f.id == id);
    await _saveAll(faces);
  }

  Future<void> clearAll() async {
    await _saveAll([]);
  }
  /// Fetches today's attendance record for the current authenticated user
  Future<Map<String, dynamic>?> getTodayAttendance() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final data = await _client
          .from('attendance')
          .select()
          .eq('user_id', user.id)
          .eq('date', DateTime.now().toIso8601String().substring(0, 10))
          .maybeSingle();
      
      return data;
    } catch (e) {
      print("Error fetching today's attendance: $e");
      return null;
    }
  }

  /// Marks Check-In or Check-Out for today
  Future<void> logAttendance({required String time, required bool isCheckIn}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");
      
      final todayDate = DateTime.now().toIso8601String().substring(0, 10);

      if (isCheckIn) {
        // Create new row for today with check_in time
        await _client.from('attendance').upsert({
          'user_id': user.id,
          'date': todayDate,
          'check_in': time,
        });
      } else {
        // Update today's row with check_out time
        await _client.from('attendance').update({
          'check_out': time,
        }).eq('user_id', user.id).eq('date', todayDate);
      }
    } catch (e) {
      print("Error logging attendance: $e");
      rethrow;
    }
  }
  /// Fetches historical attendance logs for the current user
  Future<List<Map<String, dynamic>>> getAttendanceHistory() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return [];

      final data = await _client
          .from('attendance')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false)
          .limit(7); // Pull last 7 logs
      
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print("Error fetching log data: $e");
      return [];
    }
  }

  /// Logs the current employee session out of Supabase Auth
  Future<void> signOutEmployee() async {
    try {
      await _client.auth.signOut();
      print("✅ Session closed successfully.");
    } catch (e) {
      print("❌ Log Out Error: $e");
      rethrow;
    }
  }

  /// Overwrites the existing 192-length face vector embedding for the current user
  Future<bool> updateFaceEmbedding(List<double> newFaceEmbedding) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;

      print("⚡ Updating face embedding for User ID: ${user.id}...");

      // Overwrites the existing profile row's embedding column matrix
      await _client.from('profiles').update({
        'face_embedding': newFaceEmbedding.map((e) => e.toDouble()).toList(),
      }).eq('id', user.id);

      print("✅ Face matrix updated successfully in cloud tables.");
      return true;
    } catch (e) {
      print("❌ Update Face Service Error: $e");
      return false;
    }
  }
}
