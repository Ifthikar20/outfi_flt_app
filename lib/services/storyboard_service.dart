import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/storyboard.dart';
import 'api_client.dart';

class StoryboardService {
  final ApiClient _api;

  StoryboardService(this._api);

  Future<List<Storyboard>> getStoryboards() async {
    final response = await _api.get('/storyboard/');
    final data = response.data;
    // Backend returns { storyboards: [...], count: N }
    final list = (data is Map && data['storyboards'] != null)
        ? data['storyboards'] as List<dynamic>
        : (data is List ? data : []);
    return list
        .map((s) => Storyboard.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<Storyboard> createStoryboard({
    required String title,
    required Map<String, dynamic> storyboardData,
    int expiresInDays = 30,
  }) async {
    // Extract snapshot_path from board data if present
    final snapshotPath = storyboardData.remove('snapshot_path') ?? '';
    final response = await _api.post('/storyboard/', data: {
      'title': title,
      'storyboard_data': storyboardData,
      'expires_in_days': expiresInDays,
      if (snapshotPath.toString().isNotEmpty) 'snapshot_path': snapshotPath,
    });
    return Storyboard.fromJson(response.data);
  }

  /// Update an existing storyboard by token.
  Future<Storyboard> updateStoryboard({
    required String token,
    required String title,
    required Map<String, dynamic> storyboardData,
  }) async {
    final response = await _api.put('/storyboard/$token/', data: {
      'title': title,
      'storyboard_data': storyboardData,
    });
    return Storyboard.fromJson(response.data);
  }

  Future<Storyboard> getSharedStoryboard(String token) async {
    final response = await _api.get('/storyboard/$token/');
    return Storyboard.fromJson(response.data);
  }

  /// Toggle public/private visibility.
  Future<Storyboard> togglePublic(String token, bool isPublic) async {
    final response = await _api.put('/storyboard/$token/', data: {
      'is_public': isPublic,
    });
    return Storyboard.fromJson(response.data);
  }

  Future<void> deleteStoryboard(String token) async {
    await _api.delete('/storyboard/$token/');
  }

  /// Upload an image to S3 via the backend.
  /// Returns the URL of the uploaded image.
  Future<String> uploadImage(Uint8List imageBytes, {String filename = 'board_image.jpg'}) async {
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        imageBytes,
        filename: filename,
      ),
    });
    final response = await _api.uploadFile('/storyboard/upload-image/', formData);
    return response.data['url'] as String;
  }
}
