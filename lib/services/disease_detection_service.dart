import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../data/models/scan_result.dart';

/// Service for disease detection using CNN model
class DiseaseDetectionService {
  static final DiseaseDetectionService instance = DiseaseDetectionService._internal();
  
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  static const String _modelPath = 'assets/model/potato_model.tflite';
  static const String _labelsPath = 'assets/model/labels.txt';
  static const int _inputSize = 224; // Model input size: 224x224

  DiseaseDetectionService._internal();

  /// Initialize the model and load labels
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load labels
      final labelsData = await rootBundle.loadString(_labelsPath);
      _labels = labelsData.split('\n')
          .where((label) => label.trim().isNotEmpty)
          .map((label) => label.trim())
          .toList();

      // Load TFLite model
      _interpreter = await Interpreter.fromAsset(_modelPath);
      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize model: $e');
    }
  }

  /// Analyze an image for potato diseases
  /// 
  /// [imagePath] - Path to the image file to analyze
  /// Returns a ScanResult with disease label and confidence score
  Future<ScanResult> analyzeImage(String imagePath) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_interpreter == null) {
      throw Exception('Model not initialized');
    }

    // Validate image
    final imageFile = File(imagePath);
    if (!isValidImage(imageFile)) {
      throw Exception('Invalid image file');
    }

    // Preprocess image (returns [1, 224, 224, 3] normalized float32)
    final inputImage = await _preprocessImage(imagePath);

    // Prepare output buffer
    final outputBuffer = List.generate(
      1,
      (_) => List.filled(_labels.length, 0.0),
    );

    // Run inference
    _interpreter!.run(inputImage, outputBuffer);

    // Get prediction results
    // Model already outputs softmax probabilities (activation='softmax' in training)
    final predictions = outputBuffer[0] as List<dynamic>;
    
    // Find the class with highest confidence
    // No need to apply softmax - model already outputs probabilities
    double maxConfidence = 0.0;
    int maxIndex = 0;
    for (int i = 0; i < predictions.length; i++) {
      final confidence = (predictions[i] as num).toDouble();
      if (confidence > maxConfidence) {
        maxConfidence = confidence;
        maxIndex = i;
      }
    }

    // Format disease label (convert snake_case to Title Case)
    final diseaseLabel = _formatLabel(_labels[maxIndex]);

    return ScanResult(
      imageId: 0, // Will be set by caller after image is saved
      diseaseLabel: diseaseLabel,
      confidence: maxConfidence,
      createdAt: DateTime.now(),
    );
  }

  /// Preprocess image: resize to 224x224 and normalize to [0.0, 1.0]
  /// For non-quantized models, we use normalized float32 values
  Future<List<List<List<List<double>>>>> _preprocessImage(String imagePath) async {
    // Read image file
    final imageBytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Resize to model input size (224x224)
    // The image package handles format conversion automatically
    final resizedImage = img.copyResize(
      image,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to normalized float32 format: [1, 224, 224, 3]
    // Normalize pixel values from [0, 255] to [0.0, 1.0]
    // Match training preprocessing: rescale=1./255
    final inputBuffer = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = resizedImage.getPixel(x, y);
            // Normalize RGB values to [0.0, 1.0] - matches training rescale=1./255
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );

    return inputBuffer;
  }

  /// Format label from snake_case to Title Case
  String _formatLabel(String label) {
    return label
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Validate image before processing
  bool isValidImage(File imageFile) {
    if (!imageFile.existsSync()) return false;
    // Add more validation if needed (size, format, etc.)
    return true;
  }

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
