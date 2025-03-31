//storage_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';

// Service to handle saving/loading device list locally
class StorageService {
  static const String _devicesKey = 'devices_list';

  Future<List<Device>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? devicesJson = prefs.getStringList(_devicesKey);
    if (devicesJson == null) {
      return []; // No devices saved yet
    }
    try {
      return devicesJson
          .map((jsonString) => Device.fromJson(jsonDecode(jsonString)))
          .toList();
    } catch (e) {
      print("Error loading devices from storage: $e");
      // Optionally clear corrupted data
      // await prefs.remove(_devicesKey);
      return [];
    }
  }

  Future<bool> saveDevices(List<Device> devices) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final List<String> devicesJson =
          devices.map((device) => jsonEncode(device.toJson())).toList();
      return await prefs.setStringList(_devicesKey, devicesJson);
    } catch (e) {
      print("Error saving devices to storage: $e");
      return false;
    }
  }
}
