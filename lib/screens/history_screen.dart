import 'dart:io';
import 'package:flutter/material.dart';
import '../data/models/image_entity.dart';
import '../data/models/scan_result.dart';
import '../data/repositories/image_repository.dart';
import '../data/repositories/scan_result_repository.dart';
import '../theme/app_colors.dart';
import 'scan_result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ImageRepository _imageRepository = ImageRepository();
  final ScanResultRepository _resultRepository = ScanResultRepository();
  List<ImageEntity> _images = [];
  Map<int, ScanResult> _resultsMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final images = await _imageRepository.getAllImages();
      final resultsMap = <int, ScanResult>{};

      // Load results for each image
      for (final image in images) {
        if (image.imageId != null) {
          final results = await _resultRepository.getResultsByImageId(
            image.imageId!,
          );
          if (results.isNotEmpty) {
            resultsMap[image.imageId!] = results.first;
          }
        }
      }

      setState(() {
        _images = images;
        _resultsMap = resultsMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading history: $e')));
      }
    }
  }

  Future<void> _viewResult(ImageEntity image) async {
    try {
      final results = await _resultRepository.getResultsByImageId(
        image.imageId!,
      );
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No scan result found for this image'),
            ),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ScanResultScreen(image: image, result: results.first),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading result: $e')));
      }
    }
  }

  Future<void> _deleteImage(ImageEntity image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text(
          'Are you sure you want to delete this image and its results?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.errorRed),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && image.imageId != null) {
      try {
        await _imageRepository.deleteImage(image.imageId!);
        _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Image deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting image: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.bgColor,
        elevation: 0,
        title: const Text('Scan History'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
          ? const Center(
              child: Text(
                'No scan history yet',
                style: TextStyle(fontSize: 16, color: AppColors.textGrey),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: ListView.builder(
                itemCount: _images.length,
                padding: const EdgeInsets.all(8),
                itemBuilder: (context, index) {
                  final image = _images[index];
                  final result = image.imageId != null
                      ? _resultsMap[image.imageId!]
                      : null;
                  return _HistoryItem(
                    image: image,
                    result: result,
                    onTap: () => _viewResult(image),
                    onDelete: () => _deleteImage(image),
                  );
                },
              ),
            ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final ImageEntity image;
  final ScanResult? result;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryItem({
    required this.image,
    this.result,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(image.imagePath),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image),
          ),
        ),
        title: Text(
          result?.diseaseLabel ?? 'No result',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Text(
                      '${(result!.confidence * 100).toStringAsFixed(1)}% confidence',
                      style: TextStyle(
                        fontSize: 12,
                        color: _getConfidenceColor(result!.confidence),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                _formatDateTime(image.capturedAt),
                style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: AppColors.errorRed),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return AppColors.successGreen;
    if (confidence >= 0.6) return AppColors.warningOrange;
    return AppColors.errorRed;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
