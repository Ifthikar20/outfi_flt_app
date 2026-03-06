import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// Removes white/near-white backgrounds from product images entirely
/// client-side using pixel manipulation. No server call needed.
///
/// This matches the result of the web app's rembg approach for product
/// images (which almost always have white/light backgrounds).
class BackgroundRemovalService {
  BackgroundRemovalService(ApiClient _);

  /// Download an image from [url] and make white-ish pixels transparent.
  /// Returns transparent PNG bytes.
  Future<Uint8List?> removeBackgroundFromUrl(String imageUrl) async {
    try {
      // Download the image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) return null;
      return await removeBackgroundFromBytes(
          Uint8List.fromList(response.bodyBytes));
    } catch (e) {
      debugPrint('❌ Background removal failed: $e');
      return null;
    }
  }

  /// Make white/near-white pixels transparent in [bytes].
  Future<Uint8List?> removeBackgroundFromBytes(Uint8List bytes) async {
    try {
      // Decode image
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Get pixel data
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final pixels = byteData.buffer.asUint8List();
      final width = image.width;
      final height = image.height;

      // Process in an isolate to avoid blocking UI
      final result = await compute(_removeWhiteBackground, {
        'pixels': pixels,
        'width': width,
        'height': height,
      });

      // Encode back to PNG
      final processed = result as Uint8List;
      final builder = ui.ImmutableBuffer.fromUint8List(processed);
      final descriptor = ui.ImageDescriptor.raw(
        await builder,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final outputCodec = await descriptor.instantiateCodec();
      final outputFrame = await outputCodec.getNextFrame();
      final outputByteData =
          await outputFrame.image.toByteData(format: ui.ImageByteFormat.png);

      debugPrint('✅ Background removed client-side (${width}x$height)');
      return outputByteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('❌ Background removal failed: $e');
      return null;
    }
  }
}

/// Runs in an isolate — makes white/near-white pixels transparent.
/// Uses flood-fill from edges to only remove the outer background,
/// not white areas inside the product.
Uint8List _removeWhiteBackground(Map<String, dynamic> params) {
  final pixels = params['pixels'] as Uint8List;
  final width = params['width'] as int;
  final height = params['height'] as int;
  final result = Uint8List.fromList(pixels);

  // Threshold: pixels with R,G,B all above this value are considered "white"
  const threshold = 225;
  // Secondary threshold for near-white with slight color tint
  const softThreshold = 210;

  // Track which pixels are part of the background (flood fill from edges)
  final visited = List<bool>.filled(width * height, false);
  final queue = <int>[];

  // Seed from all edge pixels
  for (int x = 0; x < width; x++) {
    queue.add(x); // top row
    queue.add((height - 1) * width + x); // bottom row
  }
  for (int y = 0; y < height; y++) {
    queue.add(y * width); // left col
    queue.add(y * width + width - 1); // right col
  }

  // BFS flood fill
  while (queue.isNotEmpty) {
    final idx = queue.removeLast();
    if (idx < 0 || idx >= width * height) continue;
    if (visited[idx]) continue;

    final px = idx * 4;
    if (px + 3 >= result.length) continue;

    final r = result[px];
    final g = result[px + 1];
    final b = result[px + 2];

    // Check if this pixel is "white enough" to be background
    final isWhite = r >= threshold && g >= threshold && b >= threshold;
    final isSoftWhite = r >= softThreshold &&
        g >= softThreshold &&
        b >= softThreshold &&
        (r - g).abs() < 20 &&
        (r - b).abs() < 20;

    if (!isWhite && !isSoftWhite) continue;

    visited[idx] = true;

    // Make transparent
    result[px + 3] = 0; // alpha = 0

    // Add neighbors (4-connected)
    final x = idx % width;
    final y = idx ~/ width;
    if (x > 0) queue.add(idx - 1);
    if (x < width - 1) queue.add(idx + 1);
    if (y > 0) queue.add(idx - width);
    if (y < height - 1) queue.add(idx + width);
  }

  // Smooth edges: semi-transparent border pixels
  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      final idx = y * width + x;
      if (visited[idx]) continue; // already transparent

      // Count transparent neighbors
      int transparentNeighbors = 0;
      if (visited[idx - 1]) transparentNeighbors++;
      if (visited[idx + 1]) transparentNeighbors++;
      if (visited[idx - width]) transparentNeighbors++;
      if (visited[idx + width]) transparentNeighbors++;

      // If this pixel borders transparent pixels, soften its alpha
      if (transparentNeighbors >= 2) {
        final px = idx * 4;
        result[px + 3] = (result[px + 3] * 0.5).round();
      }
    }
  }

  return result;
}
