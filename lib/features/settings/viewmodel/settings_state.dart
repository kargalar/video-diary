import '../model/settings.dart';

enum SettingsStatus { initial, loading, success, error }

class SettingsState {
  final SettingsStatus status;
  final SettingsModel settings;
  final String? errorMessage;

  const SettingsState({this.status = SettingsStatus.initial, this.settings = SettingsModel.def, this.errorMessage});

  SettingsState copyWith({SettingsStatus? status, SettingsModel? settings, String? errorMessage}) {
    return SettingsState(status: status ?? this.status, settings: settings ?? this.settings, errorMessage: errorMessage ?? this.errorMessage);
  }
}
