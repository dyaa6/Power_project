//power_data.dart
import 'package:flutter/foundation.dart';

// Model to hold the power data fetched from Firebase
@immutable
class PowerData {
  final double voltage;
  final double current;
  final double power;
  final double apparentPower;
  final double powerFactor;
  final double energy;
  final double frequency;
  final int timestamp; // Firebase server timestamp (milliseconds since epoch)

  const PowerData({
    required this.voltage,
    required this.current,
    required this.power,
    required this.apparentPower,
    required this.powerFactor,
    required this.energy,
    required this.frequency,
    required this.timestamp,
  });

  factory PowerData.fromFirebaseMap(Map<dynamic, dynamic> map) {
    // Helper to safely parse double values from Firebase (which might be int or String)
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Helper to safely parse int values
    int parseInt(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return PowerData(
      voltage: parseDouble(map['voltage']),
      current: parseDouble(map['current']),
      power: parseDouble(map['power']),
      apparentPower: parseDouble(map['apparentPower']),
      powerFactor: parseDouble(map['powerFactor']),
      energy: parseDouble(map['energy']),
      frequency: parseDouble(map['frequency']),
      // Firebase timestamp is usually milliseconds since epoch
      timestamp: parseInt(map['timestamp']),
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}
