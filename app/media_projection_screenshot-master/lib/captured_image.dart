import 'dart:typed_data';

class CapturedImage {
  Uint8List bytes;
  Uint8List nv21;
  int width;
  int height;
  int rowBytes;
  int pixelStride;
  int rowStride;
  String format;
  int time;
  int queue;

  CapturedImage({
    required this.bytes,
    required this.nv21,
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.pixelStride,
    required this.rowStride,
    required this.format,
    required this.time,
    required this.queue,
  });

  factory CapturedImage.fromMap(Map<String, dynamic> map) {
    Uint8List ensureBytes(dynamic value) {
      if (value is Uint8List) {
        return value;
      }
      if (value is List<int>) {
        return Uint8List.fromList(value);
      }
      return Uint8List(0);
    }

    int readInt(String key) {
      final dynamic value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final Uint8List bytes = ensureBytes(map['bytes']);
    final Uint8List nv21 = ensureBytes(map['nv21']);

    return CapturedImage(
      bytes: bytes,
      nv21: nv21,
      width: readInt('width'),
      height: readInt('height'),
      rowBytes: readInt('rowBytes'),
      pixelStride: readInt('pixelStride'),
      rowStride: readInt('rowStride'),
      format: (map['format'] as String?) ?? '',
      time: readInt('time'),
      queue: readInt('queue'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bytes': bytes,
      'nv21': nv21,
      'width': width,
      'height': height,
      'rowBytes': rowBytes,
      'format': format,
      'pixelStride': pixelStride,
      'rowStride': rowStride,
      'time': time,
      'queue': queue,
    };
  }

  @override
  String toString() =>
      "ScreenshotImage(time: $time, queue: $queue, bytes: [${bytes.length} BYTES...], nv21: [${nv21.length} BYTES...], width: $width, height: $height, rowBytes: $rowBytes, format: $format, pixelStride: $pixelStride, rowStride: $rowStride)";

  @override
  int get hashCode => Object.hash(bytes, nv21, width, height, rowBytes, format, pixelStride, rowStride, time, queue);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapturedImage &&
          runtimeType == other.runtimeType &&
          bytes == other.bytes &&
          nv21 == other.nv21 &&
          width == other.width &&
          height == other.height &&
          rowBytes == other.rowBytes &&
          format == other.format &&
          pixelStride == other.pixelStride &&
          time == other.time &&
          queue == other.queue &&
          rowStride == other.rowStride;
}
