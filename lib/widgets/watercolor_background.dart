import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

/// Animated watercolor background — plays `assets/videos/watercolor_main.mp4`
/// on loop, muted, covering the full widget. Used on login/register screens.
///
/// Falls back to a solid [AppTheme.bgMain] while the video is loading, and
/// stays on [AppTheme.bgMain] if the video fails to load (e.g. asset missing).
class WatercolorBackground extends StatefulWidget {
  final Widget? child;
  const WatercolorBackground({super.key, this.child});

  @override
  State<WatercolorBackground> createState() => _WatercolorBackgroundState();
}

class _WatercolorBackgroundState extends State<WatercolorBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.asset(
        'assets/videos/watercolor_main.mp4',
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base warm background — shows while loading or if video fails
        Container(color: AppTheme.bgMain),

        if (_ready && _controller != null && !_failed)
          // Cover the whole box with the video, cropping as needed
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),

        if (widget.child != null) widget.child!,
      ],
    );
  }
}
