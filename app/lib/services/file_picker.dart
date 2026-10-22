import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

/// Picks files and folders. The screens use this interface so tests can
/// swap in a fake; the app uses [SystemFilePicker].
abstract interface class FilePicker {
  /// Paths of the files chosen to add to a project (empty if cancelled).
  Future<List<String>> pickFiles();

  /// Path of an image chosen as cover art, or null if cancelled.
  Future<String?> pickImage();

  /// Path of a folder for storing projects, or null if cancelled.
  Future<String?> pickFolder({String? initialDirectory});

  /// Where to save an export, or null if cancelled. The dialog doesn't ask
  /// before replacing a file; the export dialog warns about that itself.
  Future<String?> pickSaveLocation({required String suggestedName, String? initialDirectory});

  /// Path of a locked export (`.pjx`) to import, or null if cancelled.
  Future<String?> pickExport();
}

/// The desktop's own file dialog, through the Flutter team's
/// file_selector_linux plugin (GTK's native chooser, which also works
/// through the file-dialog portal inside a Flatpak).
final class SystemFilePicker implements FilePicker {
  const SystemFilePicker();

  static const XTypeGroup _images = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
    mimeTypes: ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp'],
  );

  @override
  Future<List<String>> pickFiles() async {
    final files = await FileSelectorPlatform.instance.openFiles(confirmButtonText: 'Add');
    return [for (final f in files) f.path];
  }

  @override
  Future<String?> pickImage() async {
    final file = await FileSelectorPlatform.instance.openFile(acceptedTypeGroups: [_images], confirmButtonText: 'Choose');
    return file?.path;
  }

  static const XTypeGroup _exports = XTypeGroup(label: 'Portfolio Jockey exports', extensions: ['pjx']);

  @override
  Future<String?> pickSaveLocation({required String suggestedName, String? initialDirectory}) async {
    final location = await FileSelectorPlatform.instance.getSaveLocation(
      options: SaveDialogOptions(suggestedName: suggestedName, initialDirectory: initialDirectory, confirmButtonText: 'Choose'),
    );
    return location?.path;
  }

  @override
  Future<String?> pickExport() async {
    final file = await FileSelectorPlatform.instance.openFile(acceptedTypeGroups: [_exports], confirmButtonText: 'Open');
    return file?.path;
  }

  @override
  Future<String?> pickFolder({String? initialDirectory}) => FileSelectorPlatform.instance.getDirectoryPathWithOptions(
    FileDialogOptions(initialDirectory: initialDirectory, confirmButtonText: 'Choose', canCreateDirectories: true),
  );
}
