import 'dart:convert';

class AttendanceModel {
  final int id;
  final String date;
  final String time;
  final String beaconId;
  final int rssi;
  final String status; // "Present" or "Absent"
  final bool synced;
  final String? _studentId; // Optional student ID

  AttendanceModel({
    required this.id,
    required this.date,
    required this.time,
    required this.beaconId,
    required this.rssi,
    required this.status,
    this.synced = false,
    String? studentId,
  }) : _studentId = studentId;

  // Get student ID (returns stored value or empty string)
  String get studentId => _studentId ?? '';

  // Convert model to Map for JSON serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'time': time,
      'beaconId': beaconId,
      'rssi': rssi,
      'status': status,
      'synced': synced,
      if (_studentId != null) 'studentId': _studentId,
    };
  }

  // Create model from Map
  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id: map['id'] ?? 0,
      date: map['date'] ?? '',
      time: map['time'] ?? '',
      beaconId: map['beaconId'] ?? '',
      rssi: map['rssi'] ?? 0,
      status: map['status'] ?? '',
      synced: map['synced'] ?? false,
      studentId: map['studentId'] as String?,
    );
  }

  // Convert to JSON string
  String toJson() => json.encode(toMap());

  // Create from JSON string
  factory AttendanceModel.fromJson(String source) =>
      AttendanceModel.fromMap(json.decode(source));

  // Copy with method for updating specific fields
  AttendanceModel copyWith({
    int? id,
    String? date,
    String? time,
    String? beaconId,
    int? rssi,
    String? status,
    bool? synced,
    String? studentId,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      date: date ?? this.date,
      time: time ?? this.time,
      beaconId: beaconId ?? this.beaconId,
      rssi: rssi ?? this.rssi,
      status: status ?? this.status,
      synced: synced ?? this.synced,
      studentId: studentId ?? this._studentId,
    );
  }

  @override
  String toString() {
    return 'AttendanceModel(id: $id, date: $date, time: $time, beaconId: $beaconId, rssi: $rssi, status: $status, synced: $synced)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AttendanceModel && other.id == id;
  }

  @override
  int get hashCode {
    return id.hashCode;
  }
}

