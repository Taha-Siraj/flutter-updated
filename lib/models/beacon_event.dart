/// Beacon attendance event model
class BeaconEvent {
  final String studentId;
  final String beaconId;
  final String event; // "present", "left", "absent"
  final DateTime timestamp;
  final int? rssi; // Optional RSSI value
  final bool synced; // Whether this event has been sent to API

  BeaconEvent({
    required this.studentId,
    required this.beaconId,
    required this.event,
    required this.timestamp,
    this.rssi,
    this.synced = false,
  });

  /// Create from JSON
  factory BeaconEvent.fromJson(Map<String, dynamic> json) {
    return BeaconEvent(
      studentId: json['student_id'] as String,
      beaconId: json['beacon_id'] as String,
      event: json['event'] as String,
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'])
          : DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      rssi: json['rssi'] as int?,
      synced: json['synced'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'beacon_id': beaconId,
      'event': event,
      'timestamp': timestamp.toIso8601String(),
      if (rssi != null) 'rssi': rssi,
      'synced': synced,
    };
  }

  /// Copy with modifications
  BeaconEvent copyWith({
    String? studentId,
    String? beaconId,
    String? event,
    DateTime? timestamp,
    int? rssi,
    bool? synced,
  }) {
    return BeaconEvent(
      studentId: studentId ?? this.studentId,
      beaconId: beaconId ?? this.beaconId,
      event: event ?? this.event,
      timestamp: timestamp ?? this.timestamp,
      rssi: rssi ?? this.rssi,
      synced: synced ?? this.synced,
    );
  }

  @override
  String toString() {
    return 'BeaconEvent(studentId: $studentId, beaconId: $beaconId, event: $event, timestamp: $timestamp, rssi: $rssi, synced: $synced)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BeaconEvent &&
        other.studentId == studentId &&
        other.beaconId == beaconId &&
        other.event == event &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return studentId.hashCode ^
        beaconId.hashCode ^
        event.hashCode ^
        timestamp.hashCode;
  }
}

