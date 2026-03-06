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
    final response = await _api.post('/storyboard/', data: {
      'title': title,
      'storyboard_data': storyboardData,
      'expires_in_days': expiresInDays,
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

  Future<void> deleteStoryboard(String token) async {
    await _api.delete('/storyboard/$token/');
  }
}
