/// Error codes from docs/INTERFACES.md "Error Contract". No others exist.
enum ErrorCode {
  insufficientClips('INSUFFICIENT_CLIPS'),
  lowPoseConfidence('LOW_POSE_CONFIDENCE'),
  phaseDetectionFailed('PHASE_DETECTION_FAILED'),
  schemaMismatch('SCHEMA_MISMATCH'),
  profileNotReady('PROFILE_NOT_READY'),
  patchRejected('PATCH_REJECTED'),
  adapterCompileFailed('ADAPTER_COMPILE_FAILED');

  const ErrorCode(this.wire);

  /// The string used on the wire (`error_code`).
  final String wire;

  static ErrorCode? fromWire(String s) {
    for (final c in values) {
      if (c.wire == s) return c;
    }
    return null;
  }
}

/// The Error Contract object. Every analysis operation returns either a
/// success payload or one of these.
class AnalysisError implements Exception {
  AnalysisError(this.code, this.message, [this.details = const {}]);

  final ErrorCode code;
  final String message;
  final Map<String, Object?> details;

  String get errorCode => code.wire;

  Map<String, Object?> toJson() =>
      {'error_code': code.wire, 'message': message, 'details': details};

  factory AnalysisError.fromJson(Map<String, Object?> json) {
    final code = ErrorCode.fromWire('${json['error_code']}');
    if (code == null || json['message'] is! String) {
      throw FormatException('Not an Error Contract object: $json');
    }
    return AnalysisError(code, json['message'] as String,
        Map<String, Object?>.from((json['details'] as Map?) ?? const {}));
  }

  @override
  String toString() => '${code.wire}: $message';
}
