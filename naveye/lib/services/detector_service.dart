import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';

class DetectionResult {
  final String label;
  final double confidence;
  final String direction;
  final String distance;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.direction,
    required this.distance,
  });

  String get announcement => '\ on the \, \';
}

class DetectorService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;
  bool _isProcessing = false;

  bool get isLoaded => _isLoaded;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('models/detect.tflite');
      final labelData = await rootBundle.loadString('assets/labelmap.txt');
      _labels = labelData.split('\n').where((l) => l.trim().isNotEmpty).toList();
      _isLoaded = true;
    } catch (e) {
      _isLoaded = false;
    }
  }

  Future<List<DetectionResult>> detect(img.Image image) async {
    if (!_isLoaded || _interpreter == null || _isProcessing) return [];
    _isProcessing = true;
    try {
      final resized = img.copyResize(image, width: 300, height: 300);
      final input = _imageToByteList(resized);
      final outputBoxes = List.filled(1 * 10 * 4, 0.0).reshape([1, 10, 4]);
      final outputClasses = List.filled(1 * 10, 0.0).reshape([1, 10]);
      final outputScores = List.filled(1 * 10, 0.0).reshape([1, 10]);
      final outputCount = List.filled(1, 0.0).reshape([1]);
      final outputs = {0: outputBoxes, 1: outputClasses, 2: outputScores, 3: outputCount};
      _interpreter!.runForMultipleInputs([input], outputs);
      final results = <DetectionResult>[];
      final count = outputCount[0].toInt();
      for (int i = 0; i < count; i++) {
        final score = outputScores[0][i] as double;
        if (score < 0.5) continue;
        final classIndex = (outputClasses[0][i] as double).toInt() + 1;
        if (classIndex >= _labels.length) continue;
        final label = _labels[classIndex].trim();
        final box = outputBoxes[0][i] as List;
        final xCenter = ((box[1] as double) + (box[3] as double)) / 2;
        final boxHeight = (box[2] as double) - (box[0] as double);
        final direction = xCenter < 0.33 ? 'left' : xCenter > 0.66 ? 'right' : 'center';
        final distance = boxHeight > 0.5 ? 'very close' : boxHeight > 0.3 ? 'nearby' : 'ahead';
        results.add(DetectionResult(label: label, confidence: score, direction: direction, distance: distance));
      }
      return results;
    } catch (e) {
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  List<List<List<List<int>>>> _imageToByteList(img.Image image) {
    final input = List.generate(1, (_) =>
      List.generate(300, (y) =>
        List.generate(300, (x) {
          final pixel = image.getPixel(x, y);
          return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
        })
      )
    );
    return input;
  }

  void dispose() {
    _interpreter?.close();
  }
}
