import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageHelper {
  final ImagePicker _picker = ImagePicker();

  /// Capture image from camera
  Future<String?> captureImageFromCamera() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (pickedFile == null) return null;

    return await _saveImageLocally(pickedFile);
  }

  /// Pick image from gallery
  Future<String?> pickImageFromGallery() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (pickedFile == null) return null;

    return await _saveImageLocally(pickedFile);
  }

  /// Save the picked file to app documents directory
  Future<String> _saveImageLocally(XFile pickedFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}${path.extension(pickedFile.path)}';
    final savedPath = path.join(appDir.path, fileName);

    final File imageFile = File(pickedFile.path);
    await imageFile.copy(savedPath);

    return savedPath;
  }
}
