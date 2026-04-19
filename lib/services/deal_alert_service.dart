import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/deal_alert.dart';
import 'api_client.dart';

class DealAlertService {
  final ApiClient _api;

  DealAlertService(this._api);

  Future<List<DealAlert>> getAlerts({String? status}) async {
    final hasAuth = await _api.hasTokens();
    if (!hasAuth) {
      debugPrint('DealAlertService.getAlerts: no auth tokens — returning empty');
      return [];
    }

    final params = <String, String>{};
    if (status != null) params['status'] = status;

    final response = await _api.get('/deal-alerts/', params: params);
    final data = response.data;
    debugPrint('DealAlertService.getAlerts: response type=${data.runtimeType}');

    if (data is Map) {
      debugPrint('DealAlertService.getAlerts: keys=${data.keys.toList()}');
      final alertsList = data['alerts'];
      if (alertsList is List) {
        debugPrint('DealAlertService.getAlerts: found ${alertsList.length} alerts');
        return alertsList
            .map((j) => DealAlert.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    }

    if (data is List) {
      debugPrint('DealAlertService.getAlerts: response is List with ${data.length} items');
      return data
          .map((j) => DealAlert.fromJson(j as Map<String, dynamic>))
          .toList();
    }

    debugPrint('DealAlertService.getAlerts: unexpected data format, returning empty');
    return [];
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

  Future<List<DealAlertMatch>> getMatches(
    String alertId, {
    bool unseenOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
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
