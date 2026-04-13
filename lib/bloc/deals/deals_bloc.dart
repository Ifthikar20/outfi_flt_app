import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/deal.dart';
import '../../services/deal_service.dart';
import 'deals_event.dart';

// Re-export event and state for convenience
export 'deals_event.dart';

/// BLoC for the deals feed (trending + text search).
///
/// Image search has been moved to [ImageSearchBloc] to prevent
/// image results from overwriting the trending deals state.
class DealsBloc extends Bloc<DealsEvent, DealsState> {
  final DealService _dealService;

  // Track current search params for load-more
  String _currentQuery = '';
  String _currentSort = 'relevance';
  String? _currentGender;
  List<String>? _currentSources;
  int? _currentMaxDistance;
  int _currentOffset = 0;
  int _currentLimit = 20;

  DealsBloc({required DealService dealService})
      : _dealService = dealService,
        super(DealsInitial()) {
    on<DealsFetchTrending>(_onFetchTrending);
    on<DealsSearchRequested>(_onSearchRequested);
    on<DealsLoadMoreRequested>(_onLoadMore);
  }

  Future<void> _onFetchTrending(
    DealsFetchTrending event,
    Emitter<DealsState> emit,
  ) async {
    emit(DealsLoading());
    try {
      final result = await _dealService.getTrending();
      emit(DealsLoaded(result));
    } catch (e) {
      emit(DealsError(e.toString()));
    }
  }

  Future<void> _onSearchRequested(
    DealsSearchRequested event,
    Emitter<DealsState> emit,
  ) async {
    emit(DealsLoading());

    // Reset pagination for new search
    _currentQuery = event.query;
    _currentSort = event.sort;
    _currentGender = event.gender;
    _currentSources = event.sources;
    _currentMaxDistance = event.maxDistance;
    _currentOffset = 0;

    try {
      final result = await _dealService.search(
        query: event.query,
        sort: event.sort,
        gender: event.gender,
        sources: event.sources,
        maxDistance: event.maxDistance,
        offset: 0,
        limit: _currentLimit,
      );
      _currentOffset = result.deals.length;
      emit(DealsLoaded(result));
    } catch (e) {
      emit(DealsError(e.toString()));
    }
  }

  Future<void> _onLoadMore(
    DealsLoadMoreRequested event,
    Emitter<DealsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DealsLoaded) return;
    if (currentState.isLoadingMore) return;
    if (!currentState.result.hasMore) return;

    // Show loading spinner at bottom
    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final moreResults = await _dealService.search(
        query: _currentQuery,
        sort: _currentSort,
        gender: _currentGender,
        sources: _currentSources,
        maxDistance: _currentMaxDistance,
        offset: _currentOffset,
        limit: _currentLimit,
      );

      // Merge new deals into existing results
      final mergedDeals = [...currentState.result.deals, ...moreResults.deals];
      _currentOffset = mergedDeals.length;

      final mergedResult = SearchResult(
        deals: mergedDeals,
        total: moreResults.total,
        query: moreResults.query,
        searchTimeMs: moreResults.searchTimeMs,
        sourcesSearched: moreResults.sourcesSearched,
        quotaWarning: moreResults.quotaWarning,
        extracted: moreResults.extracted,
        searchQueries: moreResults.searchQueries,
        hasMore: moreResults.hasMore,
        offset: _currentOffset,
        limit: _currentLimit,
      );

      emit(DealsLoaded(mergedResult));
    } catch (e) {
      // On error, stop loading but keep existing results
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }
}
