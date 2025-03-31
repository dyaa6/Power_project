//device.dart
import 'package:flutter/foundation.dart';

// Simple model to hold device information
@immutable // Good practice for model classes used in state management
class Device {
  final String id;
  final String name; // Optional: User-friendly name

  const Device({required this.id, String? name})
    : name = name ?? id; // Default name is ID

  // For saving/loading from SharedPreferences (e.g., as JSON)
  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Device.fromJson(Map<String, dynamic> json) =>
      Device(id: json['id'] as String, name: json['name'] as String?);

  // Override equality and hashCode for comparisons (e.g., in Dropdowns)
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Device{id: $id, name: $name}';
  }
}
