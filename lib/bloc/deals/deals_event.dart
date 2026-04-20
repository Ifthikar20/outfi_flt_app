import 'package:equatable/equatable.dart';
import '../../models/deal.dart';

// ─── Deals Events ────────────────────────────────
abstract class DealsEvent extends Equatable {
  const DealsEvent();

  @override
  List<Object?> get props => [];
}

class DealsFetchTrending extends DealsEvent {
  final bool nearMe;
  final double? latitude;
  final double? longitude;
  final int? maxDistance;

  const DealsFetchTrending({
    this.nearMe = false,
    this.latitude,
    this.longitude,
    this.maxDistance,
  });

  @override
  List<Object?> get props => [nearMe, latitude, longitude, maxDistance];
}

class DealsSearchRequested extends DealsEvent {
  final String query;
  final String sort;
  final String? gender;
  final List<String>? sources;
  final int? maxDistance;

  const DealsSearchRequested({
    required this.query,
    this.sort = 'relevance',
    this.gender,
    this.sources,
    this.maxDistance,
  });

  @override
  List<Object?> get props => [query, sort, gender, sources, maxDistance];
}

class DealsLoadMoreRequested extends DealsEvent {
  const DealsLoadMoreRequested();
}

// NOTE: DealsImageSearchRequested has been moved to
// bloc/image_search/image_search_event.dart to prevent
// image search results from overwriting trending deals state.

// ─── Deals States ────────────────────────────────
abstract class DealsState extends Equatable {
  const DealsState();

  @override
  List<Object?> get props => [];
}

class DealsInitial extends DealsState {}

class DealsLoading extends DealsState {}

class DealsLoaded extends DealsState {
  final SearchResult result;
  final bool isLoadingMore;

  const DealsLoaded(this.result, {this.isLoadingMore = false});

  DealsLoaded copyWith({SearchResult? result, bool? isLoadingMore}) {
    return DealsLoaded(
      result ?? this.result,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [result.total, result.query, isLoadingMore];
}

class DealsError extends DealsState {
  final String message;

  const DealsError(this.message);

  @override
  List<Object?> get props => [message];
}
