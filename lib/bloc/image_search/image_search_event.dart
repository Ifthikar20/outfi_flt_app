import 'package:equatable/equatable.dart';

/// Events for the image search BLoC.
abstract class ImageSearchEvent extends Equatable {
  const ImageSearchEvent();

  @override
  List<Object?> get props => [];
}

/// Fired when the user captures/selects a photo for visual search.
class ImageSearchRequested extends ImageSearchEvent {
  final String imagePath;
  final double? latitude;
  final double? longitude;

  const ImageSearchRequested({
    required this.imagePath,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [imagePath, latitude, longitude];
}

/// Resets the image search state (e.g. when user retakes).
class ImageSearchReset extends ImageSearchEvent {}
