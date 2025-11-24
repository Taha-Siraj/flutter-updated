/// Beacon to classroom/session mapping from API
class BeaconMapping {
  final String beaconId; // UUID or MAC address
  final String classroomId;
  final String classroomName;
  final String? sessionId;
  final String? sessionName;
  final String? courseId;
  final String? courseName;
  final DateTime? sessionStartTime;
  final DateTime? sessionEndTime;

  BeaconMapping({
    required this.beaconId,
    required this.classroomId,
    required this.classroomName,
    this.sessionId,
    this.sessionName,
    this.courseId,
    this.courseName,
    this.sessionStartTime,
    this.sessionEndTime,
  });

  /// Create from API JSON
  factory BeaconMapping.fromJson(Map<String, dynamic> json) {
    return BeaconMapping(
      beaconId: json['beacon_id'] as String,
      classroomId: json['classroom_id'] as String,
      classroomName: json['classroom_name'] as String,
      sessionId: json['session_id'] as String?,
      sessionName: json['session_name'] as String?,
      courseId: json['course_id'] as String?,
      courseName: json['course_name'] as String?,
      sessionStartTime: json['session_start_time'] != null
          ? DateTime.parse(json['session_start_time'])
          : null,
      sessionEndTime: json['session_end_time'] != null
          ? DateTime.parse(json['session_end_time'])
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'beacon_id': beaconId,
      'classroom_id': classroomId,
      'classroom_name': classroomName,
      if (sessionId != null) 'session_id': sessionId,
      if (sessionName != null) 'session_name': sessionName,
      if (courseId != null) 'course_id': courseId,
      if (courseName != null) 'course_name': courseName,
      if (sessionStartTime != null)
        'session_start_time': sessionStartTime!.toIso8601String(),
      if (sessionEndTime != null)
        'session_end_time': sessionEndTime!.toIso8601String(),
    };
  }

  /// Check if session is currently active
  bool get isSessionActive {
    if (sessionStartTime == null || sessionEndTime == null) return false;
    final now = DateTime.now();
    return now.isAfter(sessionStartTime!) && now.isBefore(sessionEndTime!);
  }

  @override
  String toString() {
    return 'BeaconMapping(beaconId: $beaconId, classroom: $classroomName, session: $sessionName)';
  }
}

