import '../domain/preferences.dart';
import 'preferences_codec.dart';

final class RestoreSettings {
  const RestoreSettings(this.settings);
  final SettingsPort settings;
  Future<void> call(String payload) async {
    // Validate the entire snapshot before a single atomic local replacement.
    final value = decodeBackup(payload);
    await settings.replaceSettings(
      aiEnabled: value.aiEnabled,
      privateWords: value.words,
      review: value.review,
    );
  }
}
