import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device.dart';
import '../models/power_data.dart';
import '../services/storage_service.dart';
import '../services/esp32_service.dart';

class DeviceProvider with ChangeNotifier {
  final StorageService _storageService = StorageService();
  final Esp32Service _esp32Service = Esp32Service();
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  List<Device> _devices = [];
  Device? _selectedDevice;
  List<PowerData> _powerDataList = [];
  PowerData? _currentPowerData;

  bool _isLoading = false;
  bool _isFirebaseLoading = false;
  String? _errorMessage;

  StreamSubscription<DatabaseEvent>? _firebaseSubscription;

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

  double get currentPowerWatts => _currentPowerData?.power ?? 0.0;

  double get monthlyConsumption {
    if (_powerDataList.length < 2) return 0.0;
    double totalKWh = 0.0;
    for (int i = 1; i < _powerDataList.length; i++) {
      final prev = _powerDataList[i - 1];
      final curr = _powerDataList[i];
      final elapsedHours =
          curr.dateTime.difference(prev.dateTime).inSeconds / 3600.0;
      final avgPowerKW = (prev.power + curr.power) / 2.0 / 1000.0;
      totalKWh += avgPowerKW * elapsedHours;
    }
    return totalKWh;
  }

  // --------------------
  // Constructor
  // --------------------
  DeviceProvider() {
    _loadDevices();
  }

  // --------------------
  // Private: load saved devices
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
  // Public: add / configure
  // --------------------

  Future<bool> configureAndAddDevice(String ssid, String password) async {
    _setLoading(true);
    _clearError();
    try {
      final deviceId = await _esp32Service.getDeviceId();
      if (deviceId.isEmpty) throw Exception("Empty Device ID.");
      final sent = await _esp32Service.sendCredentials(ssid, password);
      if (!sent) throw Exception("ESP32 failed after credentials.");
      await addDevice(deviceId);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

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

  Future<bool> checkDeviceExists(String deviceId) async {
    final ref = _database.ref('/sensorData/$deviceId');
    final snapshot = await ref.get();
    return snapshot.exists;
  }

  // --------------------
  // Selection & Firebase listener
  // --------------------
  void selectDevice(Device? device) => _selectDevice(device);

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

    final deviceRef = _database.ref('/sensorData/$deviceId');

    _firebaseSubscription = deviceRef.onValue.listen(
      (DatabaseEvent event) {
        _setFirebaseLoading(false);

        if (event.snapshot.exists && event.snapshot.value != null) {
          final rawData = Map<String, dynamic>.from(
            event.snapshot.value as Map<dynamic, dynamic>,
          );
          final List<PowerData> newReadings = [];

          // iterate year → month → day → entries
          rawData.forEach((yearKey, yearVal) {
            final monthsMap = Map<String, dynamic>.from(
              yearVal as Map<dynamic, dynamic>,
            );
            monthsMap.forEach((monthKey, monthVal) {
              final daysMap = Map<String, dynamic>.from(
                monthVal as Map<dynamic, dynamic>,
              );
              daysMap.forEach((dayKey, dayVal) {
                final entriesMap = Map<String, dynamic>.from(
                  dayVal as Map<dynamic, dynamic>,
                );
                entriesMap.forEach((pushKey, entryVal) {
                  if (entryVal is Map) {
                    final entryMap = Map<String, dynamic>.from(
                      entryVal as Map<dynamic, dynamic>,
                    );
                    try {
                      newReadings.add(PowerData.fromFirebaseMap(entryMap));
                    } catch (_) {
                      // skip invalid entries
                    }
                  }
                });
              });
            });
          });

          newReadings.sort((a, b) => a.dateTime.compareTo(b.dateTime));
          _powerDataList = newReadings;
          _currentPowerData = newReadings.isNotEmpty ? newReadings.last : null;
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

  // --------------------
  // State helpers & cleanup
  // --------------------
  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void _setFirebaseLoading(bool v) {
    _isFirebaseLoading = v;
  }

  void _setError(String? m) {
    _errorMessage = m;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
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
}
