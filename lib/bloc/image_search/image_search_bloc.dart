import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/deal_service.dart';
import 'image_search_event.dart';
import 'image_search_state.dart';

// Re-export for convenience
export 'image_search_event.dart';
export 'image_search_state.dart';

/// Isolated BLoC for visual (image) search.
///
/// This is separate from [DealsBloc] so that image search results
/// don't overwrite the trending deals on the home screen.
class ImageSearchBloc extends Bloc<ImageSearchEvent, ImageSearchState> {
  final DealService _dealService;

  ImageSearchBloc({required DealService dealService})
      : _dealService = dealService,
        super(ImageSearchInitial()) {
    on<ImageSearchRequested>(_onSearchRequested);
    on<ImageSearchReset>(_onReset);
  }

  Future<void> _onSearchRequested(
    ImageSearchRequested event,
    Emitter<ImageSearchState> emit,
  ) async {
    emit(ImageSearchLoading());
    try {
      final result = await _dealService.imageSearch(
        File(event.imagePath),
        latitude: event.latitude,
        longitude: event.longitude,
      );
      emit(ImageSearchLoaded(result));
    } catch (e) {
      emit(ImageSearchError(e.toString()));
    }
  }

  void _onReset(ImageSearchReset event, Emitter<ImageSearchState> emit) {
    emit(ImageSearchInitial());
  }
}
