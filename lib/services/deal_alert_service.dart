import 'package:dio/dio.dart';

import '../models/deal_alert.dart';
import 'api_client.dart';

class DealAlertService {
  final ApiClient _api;

  DealAlertService(this._api);

  Future<List<DealAlert>> getAlerts({String? status}) async {
    final hasAuth = await _api.hasTokens();
    if (!hasAuth) return [];

    final params = <String, String>{};
    if (status != null) params['status'] = status;

    final response = await _api.get('/deal-alerts/', params: params);
    final data = response.data;
    final list = (data is Map ? data['alerts'] : data) as List<dynamic>? ?? [];
    return list.map((j) => DealAlert.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<DealAlert> createAlert({required String description, double? maxPrice, String? imagePath}) async {
    if (imagePath != null) {
      // Image-based alert — multipart upload
      final formData = FormData.fromMap({
        'description': description,
        if (maxPrice != null) 'max_price': maxPrice,
        'image': await MultipartFile.fromFile(imagePath, filename: 'alert_ref.jpg'),
      });
      final response = await _api.uploadFile('/deal-alerts/', formData);
      return DealAlert.fromJson(response.data as Map<String, dynamic>);
    }
    // Text-only alert
    final body = <String, dynamic>{'description': description};
    if (maxPrice != null) body['max_price'] = maxPrice;
    final response = await _api.post('/deal-alerts/', data: body);
    return DealAlert.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DealAlert> getAlertDetail(String alertId) async {
    final response = await _api.get('/deal-alerts/$alertId/');
    return DealAlert.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DealAlert> updateAlert(String alertId, {String? description, double? maxPrice, String? status}) async {
    final body = <String, dynamic>{};
    if (description != null) body['description'] = description;
    if (maxPrice != null) body['max_price'] = maxPrice;
    if (status != null) body['status'] = status;
    final response = await _api.patch('/deal-alerts/$alertId/', data: body);
    return DealAlert.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteAlert(String alertId) async {
    await _api.delete('/deal-alerts/$alertId/');
  }

  Future<List<DealAlertMatch>> getMatches(String alertId, {bool unseenOnly = false}) async {
    final params = <String, String>{};
    if (unseenOnly) params['unseen_only'] = 'true';
    final response = await _api.get('/deal-alerts/$alertId/matches/', params: params);
    final data = response.data;
    final list = (data is Map ? data['matches'] : data) as List<dynamic>? ?? [];
    return list.map((j) => DealAlertMatch.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> markMatchesSeen(String alertId, {List<String>? matchIds}) async {
    final body = <String, dynamic>{
      'action': matchIds != null ? 'mark_seen' : 'mark_all_seen',
    };
    if (matchIds != null) body['match_ids'] = matchIds;
    await _api.post('/deal-alerts/$alertId/matches/', data: body);
  }
}
