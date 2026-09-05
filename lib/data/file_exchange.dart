import 'package:flutter/services.dart';

/// Handing a file to the user, and taking one back, through the system picker.
///
/// The app used to write backups to `/sdcard/Download/Prahar` and read one the
/// user had renamed `prahar-restore.json` by hand. Both assume a filesystem
/// layout that is not the app's to assume — scoped storage blocks raw writes
/// to public directories from API 30, so the path may not even be writable —
/// and telling somebody where their own data must live is the wrong shape for
/// a local-first app whose whole promise is that the file is theirs.
///
/// The Storage Access Framework asks instead. It needs no storage permission:
/// the user picking a document *is* the grant, which is why nothing was added
/// to the manifest for this.
///
/// Every method returns null when the picker is dismissed. Cancelling is an
/// ordinary outcome and must not read as an error.
class FileExchange {
  const FileExchange._();

  static const _channel = MethodChannel('prahar/files');

  /// Opens "save as" with [suggestedName] filled in, writes [contents] to
  /// wherever the user chooses, and returns the display name they gave it.
  static Future<String?> save({
    required String suggestedName,
    required String contents,
  }) => _channel.invokeMethod<String>('save', {
    'name': suggestedName,
    'contents': contents,
  });

  /// Opens the picker and returns the chosen file's text.
  static Future<String?> open() => _channel.invokeMethod<String>('open');

  /// Whether the platform side is there at all.
  ///
  /// False on desktop and in tests, where there is no picker behind the
  /// channel and the caller should fall back to writing a path itself.
  static Future<bool> get available async {
    try {
      await _channel.invokeMethod<void>('ping');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      // The handler exists and rejected an unknown method, which is all this
      // needs to know.
      return true;
    }
  }
}
