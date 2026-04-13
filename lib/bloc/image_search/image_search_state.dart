import 'package:equatable/equatable.dart';
import '../../models/deal.dart';

/// States for the image search BLoC.
abstract class ImageSearchState extends Equatable {
  const ImageSearchState();

  @override
  List<Object?> get props => [];
}

class ImageSearchInitial extends ImageSearchState {}

class ImageSearchLoading extends ImageSearchState {}

class ImageSearchLoaded extends ImageSearchState {
  final SearchResult result;

  const ImageSearchLoaded(this.result);

  @override
  List<Object?> get props => [result.total, result.query];
}

class ImageSearchError extends ImageSearchState {
  final String message;

  const ImageSearchError(this.message);

  @override
  List<Object?> get props => [message];
}
