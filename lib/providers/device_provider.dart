// providers/device_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device.dart';
import '../models/power_data.dart';
import '../services/storage_service.dart';
import '../services/esp32_service.dart';

/// State management class using ChangeNotifier
class DeviceProvider with ChangeNotifier {
  final StorageService _storageService = StorageService();
  final Esp32Service _esp32Service = Esp32Service();
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // --------------------
  // Fields
  // --------------------
  List<Device> _devices = [];
  Device? _selectedDevice;

  /// Holds **all** readings fetched from Firebase for the selected device
  List<PowerData> _powerDataList = [];

  /// The most recent reading
  PowerData? _currentPowerData;

  bool _isLoading = false;
  bool _isFirebaseLoading = false;
  String? _errorMessage;

  StreamSubscription<DatabaseEvent>? _firebaseSubscription;

  // --------------------
  // NEW Fields for cost calculation
  // --------------------

  /// Electricity rate in IQD per kWh (default or loaded from settings)
  double _electricityRateIQD = 75.0;

  // --------------------
  // Getters
  // --------------------

  List<Device> get devices => _devices;
  Device? get selectedDevice => _selectedDevice;
  List<PowerData> get powerDataList => _powerDataList;
  PowerData? get currentPowerData => _currentPowerData;
  bool get isLoading => _isLoading;
  bool get isFirebaseLoading => _isFirebaseLoading;
  String? get errorMessage => _errorMessage;

  /// Instantaneous power from the latest reading, in watts.
  double get currentPowerWatts => _currentPowerData?.power ?? 0.0;

  /// Total energy used this month, in kWh,
  /// computed by integrating power over time between readings.
  double get monthlyConsumption {
    if (_powerDataList.length < 2) return 0.0;

    double totalKWh = 0.0;

    for (int i = 1; i < _powerDataList.length; i++) {
      final prev = _powerDataList[i - 1];
      final curr = _powerDataList[i];

      // time difference in hours
      final elapsedHours =
          curr.dateTime.difference(prev.dateTime).inSeconds / 3600.0;

      // average power in kW
      final avgPowerKW = (prev.power + curr.power) / 2.0 / 1000.0;

      totalKWh += avgPowerKW * elapsedHours;
    }

    return totalKWh;
  }

  /// Current electricity rate in IQD per kWh
  double get electricityRateIQD => _electricityRateIQD;

  // --------------------
  // Constructor
  // --------------------
  DeviceProvider() {
    _loadDevices();
    // Optionally: _loadElectricityRate();
  }

  // --------------------
  // Private Methods
  // --------------------
  Future<void> _loadDevices() async {
    _setLoading(true);
    _devices = await _storageService.loadDevices();
    if (_devices.isNotEmpty) {
      _selectDevice(_devices.first, notify: false);
    }
    _setLoading(false);
  }

  // --------------------
  // Public Methods
  // --------------------
  Future<void> addDevice(String deviceId, {String? name}) async {
    if (deviceId.isEmpty) return;

    if (_devices.any((d) => d.id == deviceId)) {
      _selectDevice(_devices.firstWhere((d) => d.id == deviceId));
      return;
    }

    final newDevice = Device(id: deviceId, name: name);
    _devices.add(newDevice);
    await _storageService.saveDevices(_devices);

    _selectDevice(newDevice);
  }

  /// Exposed method to select a device
  void selectDevice(Device? device) {
    _selectDevice(device);
  }

  // --------------------
  // Internal selection + Firebase listener
  // --------------------
  void _selectDevice(Device? device, {bool notify = true}) {
    if (_selectedDevice == device) return;

    _selectedDevice = device;
    _currentPowerData = null;
    _powerDataList.clear();
    _cancelFirebaseSubscription();

    if (_selectedDevice != null) {
      _listenToFirebase(_selectedDevice!.id);
    }

    if (notify) notifyListeners();
  }

  void _listenToFirebase(String deviceId) {
    if (deviceId.isEmpty) return;

    _setFirebaseLoading(true);
    final deviceRef = _database.ref('/power/$deviceId/readings');

    _firebaseSubscription = deviceRef.onValue.listen(
      (DatabaseEvent event) {
        _setFirebaseLoading(false);

        if (event.snapshot.exists && event.snapshot.value != null) {
          final rawMap = event.snapshot.value as Map<dynamic, dynamic>;
          final List<PowerData> newReadings = [];

          rawMap.forEach((key, value) {
            if (value is Map) {
              try {
                newReadings.add(PowerData.fromFirebaseMap(Map.from(value)));
              } catch (_) {
                // skip invalid
              }
            }
          });

          newReadings.sort((a, b) => a.dateTime.compareTo(b.dateTime));
          _powerDataList = newReadings;
          _currentPowerData =
              _powerDataList.isNotEmpty ? _powerDataList.last : null;
          _clearError();
        } else {
          _setError("No data received from Firebase yet.");
          _powerDataList.clear();
          _currentPowerData = null;
        }

        notifyListeners();
      },
      onError: (error) {
        _setFirebaseLoading(false);
        _setError("Failed to listen to Firebase data.");
        _powerDataList.clear();
        _currentPowerData = null;
        notifyListeners();
      },
    );
  }

  Future<bool> configureAndAddDevice(String ssid, String password) async {
    _setLoading(true);
    _clearError();
    try {
      final deviceId = await _esp32Service.getDeviceId();
      if (deviceId.isEmpty) throw Exception("Empty Device ID.");
      final sent = await _esp32Service.sendCredentials(ssid, password);
      if (sent) {
        await addDevice(deviceId);
        _setLoading(false);
        return true;
      } else {
        throw Exception("ESP32 failed after credentials.");
      }
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // --------------------
  // State Helpers
  // --------------------
  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  void _setFirebaseLoading(bool value) {
    if (_isFirebaseLoading == value) return;
    _isFirebaseLoading = value;
    // UI can listen if needed
  }

  void _setError(String? message) {
    if (_errorMessage == message) return;
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  void _cancelFirebaseSubscription() {
    _firebaseSubscription?.cancel();
    _firebaseSubscription = null;
  }

  @override
  void dispose() {
    _cancelFirebaseSubscription();
    super.dispose();
  }

  // --------------------
  // Utility Methods
  // --------------------

  /// Check if a device ID exists in Firebase
  Future<bool> checkDeviceExists(String deviceId) async {
    final ref = _database.ref('/power/$deviceId');
    final snapshot = await ref.get();
    return snapshot.exists;
  }

  /// Add device by ID only
  Future<bool> addDeviceById(String deviceId) async {
    _clearError();
    if (deviceId.isEmpty) {
      _setError("Device ID can't be empty.");
      return false;
    }
    try {
      await addDevice(deviceId);
      return true;
    } catch (e) {
      _setError("Could not add device: $e");
      return false;
    }
  }
}
