import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import 'api_client.dart';

/// Calls the backend to remove the background from an image.
///
/// Uses the NON-MOBILE endpoint (/api/tools/remove-bg/) directly via
/// a plain Dio instance (no auth, no mobile prefix). This matches the
/// web app's approach and avoids the mobile-specific throttle classes.
class BackgroundRemovalService {
  // ignore the ApiClient — we use our own Dio for the non-mobile path
  BackgroundRemovalService(ApiClient _);

  /// Direct Dio hitting https://api.outfi.ai/api/tools/remove-bg/
  Dio _buildDio() {
    final host = ApiConfig.baseUrl.replaceAll('/api/v1/mobile', '');
    return Dio(BaseOptions(
      baseUrl: '$host/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
    ));
  }

  /// Remove the background from a local [imageFile].
  /// Returns the transparent PNG bytes.
  Future<Uint8List?> removeBackgroundFromFile(File imageFile) async {
    const maxRetries = 2;
    const baseDelay = Duration(seconds: 5);
    final dio = _buildDio();

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final formData = FormData.fromMap({
          'image': await MultipartFile.fromFile(
            imageFile.path,
            filename: 'image.png',
          ),
        });
        debugPrint('🔧 Remove-bg calling: ${dio.options.baseUrl}/tools/remove-bg/');
        final response = await dio.post(
          '/tools/remove-bg/',
          data: formData,
          options: Options(contentType: 'multipart/form-data'),
        );
        if (response.statusCode == 200) {
          final data = response.data as Map<String, dynamic>;
          final b64 = data['image_base64'] as String;
          debugPrint('✅ Background removed (${b64.length} chars base64)');
          return base64Decode(b64);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt < maxRetries) {
          final delay = baseDelay * (attempt + 1);
          debugPrint(
              '⏳ Remove-bg rate limited. Retrying in ${delay.inSeconds}s '
              '(attempt ${attempt + 1}/$maxRetries)');
          await Future.delayed(delay);
          continue;
        }
        debugPrint('❌ Background removal failed: $e');
        return null;
      } catch (e) {
        debugPrint('❌ Background removal failed: $e');
        return null;
      }
    }
    return null;
  }

  /// Remove the background from image [bytes] (e.g. from a network image).
  Future<Uint8List?> removeBackgroundFromBytes(Uint8List bytes) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
        '${tempDir.path}/rembg_${DateTime.now().millisecondsSinceEpoch}.png');
    try {
      await tempFile.writeAsBytes(bytes);
      return await removeBackgroundFromFile(tempFile);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }
}
