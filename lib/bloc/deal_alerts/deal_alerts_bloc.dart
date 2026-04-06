import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/deal_alert.dart';
import '../../services/deal_alert_service.dart';
import 'deal_alerts_event.dart';

export 'deal_alerts_event.dart';

// ─── Deal Alerts States ─────────────────────────
abstract class DealAlertsState {
  const DealAlertsState();
}

class DealAlertsInitial extends DealAlertsState {}

class DealAlertsLoading extends DealAlertsState {}

class DealAlertsLoaded extends DealAlertsState {
  final List<DealAlert> alerts;
  const DealAlertsLoaded(this.alerts);
}

class DealAlertsError extends DealAlertsState {
  final String message;
  const DealAlertsError(this.message);
}

class DealAlertDetailLoaded extends DealAlertsState {
  final DealAlert alert;
  const DealAlertDetailLoaded(this.alert);
}

// ─── BLoC ────────────────────────────────────────
class DealAlertsBloc extends Bloc<DealAlertsEvent, DealAlertsState> {
  final DealAlertService _service;
  final List<DealAlert> _alerts = [];

  DealAlertsBloc({required DealAlertService dealAlertService})
      : _service = dealAlertService,
        super(DealAlertsInitial()) {
    on<DealAlertsFetchRequested>(_onFetch);
    on<DealAlertCreateRequested>(_onCreate);
    on<DealAlertDeleteRequested>(_onDelete);
    on<DealAlertTogglePauseRequested>(_onTogglePause);
    on<DealAlertDetailRequested>(_onDetail);
  }

  Future<void> _onFetch(DealAlertsFetchRequested event, Emitter<DealAlertsState> emit) async {
    if (_alerts.isNotEmpty) {
      emit(DealAlertsLoaded(List.from(_alerts)));
    } else {
      emit(DealAlertsLoading());
    }
    try {
      final alerts = await _service.getAlerts();
      _alerts
        ..clear()
        ..addAll(alerts);
      emit(DealAlertsLoaded(List.from(_alerts)));
    } catch (e) {
      debugPrint('Deal alerts fetch failed: $e');
      if (_alerts.isNotEmpty) {
        emit(DealAlertsLoaded(List.from(_alerts)));
      } else {
        emit(DealAlertsError(e.toString()));
      }
    }
  }

  Future<void> _onCreate(DealAlertCreateRequested event, Emitter<DealAlertsState> emit) async {
    try {
      final alert = await _service.createAlert(
        description: event.description,
        maxPrice: event.maxPrice,
        imagePath: event.imagePath,
      );
      _alerts.insert(0, alert);
      emit(DealAlertsLoaded(List.from(_alerts)));
    } catch (e) {
      debugPrint('Deal alert create failed: $e');
      emit(DealAlertsError(e.toString()));
      // Re-emit loaded state so UI isn't stuck
      if (_alerts.isNotEmpty) {
        emit(DealAlertsLoaded(List.from(_alerts)));
      }
    }
  }

  Future<void> _onDelete(DealAlertDeleteRequested event, Emitter<DealAlertsState> emit) async {
    _alerts.removeWhere((a) => a.id == event.alertId);
    emit(DealAlertsLoaded(List.from(_alerts)));
    try {
      await _service.deleteAlert(event.alertId);
    } catch (e) {
      debugPrint('Deal alert delete failed: $e');
    }
  }

  Future<void> _onTogglePause(DealAlertTogglePauseRequested event, Emitter<DealAlertsState> emit) async {
    try {
      final updated = await _service.updateAlert(
        event.alertId,
        status: event.pause ? 'paused' : 'active',
      );
      final idx = _alerts.indexWhere((a) => a.id == event.alertId);
      if (idx >= 0) _alerts[idx] = updated;
      emit(DealAlertsLoaded(List.from(_alerts)));
    } catch (e) {
      debugPrint('Deal alert toggle failed: $e');
    }
  }

  Future<void> _onDetail(DealAlertDetailRequested event, Emitter<DealAlertsState> emit) async {
    try {
      final alert = await _service.getAlertDetail(event.alertId);
      emit(DealAlertDetailLoaded(alert));
    } catch (e) {
      debugPrint('Deal alert detail failed: $e');
      emit(DealAlertsError(e.toString()));
    }
  }
}
