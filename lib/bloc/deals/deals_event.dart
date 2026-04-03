import 'package:equatable/equatable.dart';
import '../../models/deal.dart';

// ─── Deals Events ────────────────────────────────
abstract class DealsEvent extends Equatable {
  const DealsEvent();

  @override
  List<Object?> get props => [];
}

class DealsFetchTrending extends DealsEvent {}

class DealsSearchRequested extends DealsEvent {
  final String query;
  final String sort;
  final String? gender;
  final List<String>? sources;

  const DealsSearchRequested({
    required this.query,
    this.sort = 'relevance',
    this.gender,
    this.sources,
  });

  @override
  List<Object?> get props => [query, sort, gender, sources];
}

class DealsLoadMoreRequested extends DealsEvent {
  const DealsLoadMoreRequested();
}

class DealsImageSearchRequested extends DealsEvent {
  final String imagePath;
  final double? latitude;
  final double? longitude;

  const DealsImageSearchRequested({
    required this.imagePath,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [imagePath, latitude, longitude];
}

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
