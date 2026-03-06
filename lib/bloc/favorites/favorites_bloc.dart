import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/deal.dart';
import '../../services/favorites_service.dart';
import 'favorites_event.dart';

// Re-export for convenience
export 'favorites_event.dart';

class FavoritesBloc extends Bloc<FavoritesEvent, FavoritesState> {
  final FavoritesService _favoritesService;

  // Local in-memory favorites (persists across tab switches)
  final List<Deal> _localFavorites = [];
  final Set<String> _localFavoriteIds = {};

  FavoritesBloc({required FavoritesService favoritesService})
      : _favoritesService = favoritesService,
        super(FavoritesInitial()) {
    on<FavoritesFetchRequested>(_onFetch);
    on<FavoritesSaveRequested>(_onSave);
    on<FavoritesRemoveRequested>(_onRemove);
  }

  /// Check if a deal is saved (locally)
  bool isSaved(String dealId) => _localFavoriteIds.contains(dealId);

  /// Get the current local favorites list
  List<Deal> get favorites => List.unmodifiable(_localFavorites);

  Future<void> _onFetch(
    FavoritesFetchRequested event,
    Emitter<FavoritesState> emit,
  ) async {
    // If we already have local favorites, show them immediately
    if (_localFavorites.isNotEmpty) {
      emit(FavoritesLoaded(List.from(_localFavorites)));
    } else {
      emit(FavoritesLoading());
    }

    // Try to sync from server in background
    try {
      final serverDeals = await _favoritesService.getFavorites();
      // Merge server data with local saves
      for (final deal in serverDeals) {
        if (!_localFavoriteIds.contains(deal.id)) {
          _localFavorites.add(deal);
          _localFavoriteIds.add(deal.id);
        }
      }
      emit(FavoritesLoaded(List.from(_localFavorites)));
    } catch (e) {
      // Server failed — that's fine, serve local data
      debugPrint('⚠️ Server favorites sync failed: $e');
      emit(FavoritesLoaded(List.from(_localFavorites)));
    }
  }

  Future<void> _onSave(
    FavoritesSaveRequested event,
    Emitter<FavoritesState> emit,
  ) async {
    // Optimistic local save — instant
    if (!_localFavoriteIds.contains(event.deal.id)) {
      _localFavorites.insert(0, event.deal);
      _localFavoriteIds.add(event.deal.id);
    }
    emit(FavoritesLoaded(List.from(_localFavorites)));

    // Background server sync (doesn't block UI)
    try {
      await _favoritesService.saveDeal(event.deal);
    } catch (e) {
      debugPrint('⚠️ Server save failed (kept locally): $e');
      // Don't remove local save — it persists for the session
    }
  }

  Future<void> _onRemove(
    FavoritesRemoveRequested event,
    Emitter<FavoritesState> emit,
  ) async {
    // Optimistic local remove — instant
    _localFavorites.removeWhere((d) => d.id == event.dealId);
    _localFavoriteIds.remove(event.dealId);
    emit(FavoritesLoaded(List.from(_localFavorites)));

    // Background server sync
    try {
      await _favoritesService.removeDeal(event.dealId);
    } catch (e) {
      debugPrint('⚠️ Server remove failed: $e');
    }
  }
}
