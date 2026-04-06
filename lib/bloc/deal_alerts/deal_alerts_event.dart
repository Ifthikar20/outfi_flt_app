import 'package:equatable/equatable.dart';

// ─── Deal Alerts Events ─────────────────────────
abstract class DealAlertsEvent extends Equatable {
  const DealAlertsEvent();

  @override
  List<Object?> get props => [];
}

class DealAlertsFetchRequested extends DealAlertsEvent {}

class DealAlertCreateRequested extends DealAlertsEvent {
  final String description;
  final double? maxPrice;
  final String? imagePath;

  const DealAlertCreateRequested({required this.description, this.maxPrice, this.imagePath});

  @override
  List<Object?> get props => [description, maxPrice, imagePath];
}

class DealAlertDeleteRequested extends DealAlertsEvent {
  final String alertId;

  const DealAlertDeleteRequested(this.alertId);

  @override
  List<Object?> get props => [alertId];
}

class DealAlertTogglePauseRequested extends DealAlertsEvent {
  final String alertId;
  final bool pause;

  const DealAlertTogglePauseRequested({required this.alertId, required this.pause});

  @override
  List<Object?> get props => [alertId, pause];
}

class DealAlertDetailRequested extends DealAlertsEvent {
  final String alertId;

  const DealAlertDetailRequested(this.alertId);

  @override
  List<Object?> get props => [alertId];
}
