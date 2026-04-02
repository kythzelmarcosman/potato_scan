import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/models/image_entity.dart';
import '../data/models/scan_result.dart';
import '../data/repositories/image_repository.dart';
import '../data/repositories/scan_result_repository.dart';
import '../services/disease_detection_service.dart';
import '../theme/app_colors.dart';
import 'scan_result_screen.dart';
import 'history_screen.dart';
import 'sensor_data_screen.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final ImageRepository _imageRepository = ImageRepository();
  final ScanResultRepository _resultRepository = ScanResultRepository();
  final DiseaseDetectionService _detectionService =
      DiseaseDetectionService.instance;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.bgColor,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon/logo.png', height: 28, width: 28),
            const SizedBox(width: 8),
            const Text(
              'Potato Scan',
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.more_vert, color: AppColors.textDark),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                /// BIG CAPTURE BUTTON
                _PrimaryButton(
                  icon: Icons.camera_alt,
                  label: 'Capture Image',
                  height: 90,
                  onTap: _isProcessing
                      ? null
                      : () => _showImageSourceDialog(context),
                ),

                const SizedBox(height: 20),

                /// TWO SMALL BUTTONS
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryButton(
                        icon: Icons.history,
                        label: 'View History',
                        onTap: _isProcessing
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HistoryScreen(),
                                  ),
                                );
                              },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _SecondaryButton(
                        icon: Icons.sensors,
                        label: 'Sensor Data',
                        onTap: _isProcessing
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SensorDataScreen(),
                                  ),
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_isProcessing)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing image...'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showImageSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      setState(() => _isProcessing = true);

      // Save image locally
      final File savedImage = await _saveImageLocally(File(pickedFile.path));

      // Save image to database
      final imageEntity = ImageEntity(
        imagePath: savedImage.path,
        capturedAt: DateTime.now(),
      );
      final imageId = await _imageRepository.insertImage(imageEntity);
      imageEntity.imageId = imageId;

      // Analyze image with CNN service
      final result = await _detectionService.analyzeImage(savedImage.path);

      // Update result with actual imageId
      final scanResult = ScanResult(
        imageId: imageId,
        diseaseLabel: result.diseaseLabel,
        confidence: result.confidence,
        createdAt: result.createdAt,
      );

      // Save scan result to database
      await _resultRepository.insertResult(scanResult);

      setState(() => _isProcessing = false);

      // Navigate to result screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ScanResultScreen(image: imageEntity, result: scanResult),
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error processing image: $e')));
      }
    }
  }

  Future<File> _saveImageLocally(File imageFile) async {
    final Directory appDir = await getApplicationDocumentsDirectory();

    final Directory imagesDir = Directory(p.join(appDir.path, 'scan_images'));

    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final String fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final String newPath = p.join(imagesDir.path, fileName);

    return imageFile.copy(newPath);
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double height;

  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textWhite, size: 36),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textWhite, size: 30),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class _HomeButton extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final VoidCallback? onTap;

//   const _HomeButton({required this.icon, required this.label, this.onTap});

//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       width: double.infinity,
//       height: 70,
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(12),
//         child: Ink(
//           decoration: BoxDecoration(
//             color: onTap == null ? Colors.grey : Colors.blue,
//             borderRadius: BorderRadius.circular(12),
//           ),
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16.0),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(icon, color: Colors.white, size: 40),
//                 const SizedBox(width: 16),
//                 Flexible(
//                   child: Text(
//                     label,
//                     textAlign: TextAlign.center,
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontSize: 30,
//                       fontWeight: FontWeight.w500,
//                       height: 1,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
//}
