import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device.dart';
import '../models/power_data.dart';
import '../services/storage_service.dart';
import '../services/esp32_service.dart';

// State management class using ChangeNotifier
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
  // Getters
  // --------------------
  List<Device> get devices => _devices;
  Device? get selectedDevice => _selectedDevice;
  List<PowerData> get powerDataList => _powerDataList;
  PowerData? get currentPowerData => _currentPowerData;
  bool get isLoading => _isLoading;
  bool get isFirebaseLoading => _isFirebaseLoading;
  String? get errorMessage => _errorMessage;

  // --------------------
  // Constructor
  // --------------------
  DeviceProvider() {
    _loadDevices();
  }

  // --------------------
  // Private Methods
  // --------------------
  Future<void> _loadDevices() async {
    _setLoading(true);
    _devices = await _storageService.loadDevices();
    if (_devices.isNotEmpty) {
      // Select the first device by default if any exist
      _selectDevice(_devices.first, notify: false);
    }
    _setLoading(false);
    print("Loaded devices: $_devices");
  }

  // --------------------
  // Public Methods
  // --------------------
  Future<void> addDevice(String deviceId, {String? name}) async {
    if (deviceId.isEmpty) return;

    // Avoid adding duplicates
    if (_devices.any((d) => d.id == deviceId)) {
      print("Device $deviceId already exists.");
      // Optionally select the existing device
      _selectDevice(_devices.firstWhere((d) => d.id == deviceId));
      return;
    }

    final newDevice = Device(id: deviceId, name: name);
    _devices.add(newDevice);
    await _storageService.saveDevices(_devices);

    // Select the newly added device and start listening
    _selectDevice(newDevice);
    print("Added device: $newDevice");
  }

  /// Exposed method to select a device
  void selectDevice(Device? device) {
    _selectDevice(device);
  }

  // --------------------
  // Internal selection + Firebase listener
  // --------------------
  void _selectDevice(Device? device, {bool notify = true}) {
    if (_selectedDevice == device) return; // No change

    _selectedDevice = device;
    _currentPowerData = null;
    _powerDataList.clear(); // Clear old readings
    _cancelFirebaseSubscription(); // Stop listening to the old device

    if (_selectedDevice != null) {
      // Listen to the new device's entire "readings" child
      _listenToFirebase(_selectedDevice!.id);
    }

    if (notify) {
      notifyListeners();
    }
    print("Selected device: $_selectedDevice");
  }

  void _listenToFirebase(String deviceId) {
    if (deviceId.isEmpty) return;

    _setFirebaseLoading(true);
    // Point reference to: /power/<deviceId>/readings
    final deviceRef = _database.ref('/power/$deviceId/readings');

    _firebaseSubscription = deviceRef.onValue.listen(
      (DatabaseEvent event) {
        _setFirebaseLoading(false);

        if (event.snapshot.exists && event.snapshot.value != null) {
          try {
            // The 'readings' node is typically a map
            final rawMap = event.snapshot.value as Map<dynamic, dynamic>;
            final List<PowerData> newReadings = [];

            rawMap.forEach((key, value) {
              if (value is Map) {
                try {
                  final mapData = Map<dynamic, dynamic>.from(value);
                  final reading = PowerData.fromFirebaseMap(mapData);
                  newReadings.add(reading);
                } catch (ex) {
                  print("Error parsing child '$key': $ex");
                }
              }
            });

            // Optional: sort by dateTime ascending
            newReadings.sort((a, b) => a.dateTime.compareTo(b.dateTime));

            _powerDataList = newReadings;
            _currentPowerData =
                _powerDataList.isNotEmpty ? _powerDataList.last : null;

            _clearError();
            print(
              "Received ${_powerDataList.length} reading(s) from Firebase for $deviceId.",
            );
          } catch (e) {
            print("Error parsing Firebase data for $deviceId: $e");
            _setError("Error parsing data from Firebase.");
            _powerDataList.clear();
            _currentPowerData = null;
          }
        } else {
          print("No data found in Firebase for $deviceId/readings");
          _setError("No data received from Firebase yet for this device.");
          _powerDataList.clear();
          _currentPowerData = null;
        }

        notifyListeners();
      },
      onError: (error) {
        _setFirebaseLoading(false);
        print("Firebase listener error for $deviceId: $error");
        _setError("Failed to listen to Firebase data.");
        _powerDataList.clear();
        _currentPowerData = null;
        notifyListeners();
      },
    );
  }

  /// Configure ESP32 and add device
  Future<bool> configureAndAddDevice(String ssid, String password) async {
    _setLoading(true);
    _clearError();
    try {
      // 1. Get ID from ESP32
      print("Attempting to get Device ID from ESP32...");
      final deviceId = await _esp32Service.getDeviceId();
      print("Received Device ID: $deviceId");

      if (deviceId.isEmpty) {
        throw Exception("Received empty Device ID from ESP32.");
      }

      // 2. Send Credentials to ESP32
      print("Attempting to send credentials to ESP32...");
      final bool credentialsSent = await _esp32Service.sendCredentials(
        ssid,
        password,
      );
      print("Credentials sent status: $credentialsSent");

      if (credentialsSent) {
        // 3. Add device to local storage and state
        await addDevice(deviceId); // This also selects the device
        _setLoading(false);
        return true;
      } else {
        throw Exception("ESP32 reported failure after sending credentials.");
      }
    } catch (e) {
      print("Configuration failed: $e");
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
    // Only call notifyListeners() if your UI depends on isFirebaseLoading changing
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
    print("Cancelled Firebase subscription.");
  }

  @override
  void dispose() {
    _cancelFirebaseSubscription();
    super.dispose();
  }

  // --------------------
  // NEW #1: Check if a device ID exists in Firebase
  // --------------------
  Future<bool> checkDeviceExists(String deviceId) async {
    try {
      // For example, check if the path "/power/<deviceId>" exists
      final ref = _database.ref('/power/$deviceId');
      final snapshot = await ref.get();
      return snapshot.exists;
    } catch (e) {
      // Throw so that calling code can catch/handle it
      throw Exception("No connection with the server or Firebase error: $e");
    }
  }

  // --------------------
  // NEW #2: Add device by ID only
  // --------------------
  Future<bool> addDeviceById(String deviceId) async {
    _clearError();
    if (deviceId.isEmpty) {
      _setError("Device ID can't be empty.");
      return false;
    }

    try {
      // Reuse existing logic to add the device
      await addDevice(deviceId);
      return true;
    } catch (e) {
      _setError("Could not add device by ID. Error: $e");
      return false;
    }
  }
}
