// screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:power/screens/add_device_screen.dart';
import 'package:power/screens/scan.dart';
import '../models/device.dart';
import '../services/storage_service.dart';

// Firebase configuration
const DB_URL =
    'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app';
const AUTH = 'G7FMO4LjkSOHrs5Ms5it3aHKKfOsb57Z9SzP2e';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirebaseDatabase _database = FirebaseDatabase(databaseURL: DB_URL);

  List<Device> _storedDevices = [];
  List<String> _deviceIds = [];
  String? _selectedDeviceId;

  bool _loadingDevices = true;
  bool _loadingLatestReadings = false;
  bool _loadingTotalEnergy = false;
  String? _error;

  PowerData? _current;
  double _totalEnergySinceReset = 0.0; // (in Wh)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFirebaseAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When coming back from AddDeviceScreen, reload stored devices
    if (state == AppLifecycleState.resumed) {
      _loadStoredDevices();
    }
  }

  Future<void> _initFirebaseAndLoad() async {
    await Firebase.initializeApp();
    await _loadStoredDevices();
  }

  Future<void> _loadStoredDevices() async {
    setState(() {
      _loadingDevices = true;
      _error = null;
      _storedDevices = [];
      _deviceIds = [];
      _selectedDeviceId = null;
      _current = null;
      _totalEnergySinceReset = 0.0;
      _loadingLatestReadings = false;
      _loadingTotalEnergy = false;
    });

    try {
      final devices = await StorageService().loadDevices();
      _storedDevices = devices;
      _deviceIds = _storedDevices.map((d) => d.id).toList();

      if (_deviceIds.length == 1) {
        _selectedDeviceId = _deviceIds.first;
        // Start fetching data in background
        _fetchDataInSequence(_selectedDeviceId!);
      }
    } catch (e) {
      _error = 'Failed to load stored devices: $e';
      _storedDevices = [];
      _deviceIds = [];
      _selectedDeviceId = null;
    }

    if (mounted) {
      setState(() {
        _loadingDevices = false;
      });
    }
  }

  void _onDeviceSelected(String? id) {
    if (_selectedDeviceId == id) return;

    setState(() {
      _selectedDeviceId = id;
      _current = null;
      _totalEnergySinceReset = 0.0;
      _error = null;
      _loadingLatestReadings = false;
      _loadingTotalEnergy = false;
    });

    if (id != null) {
      _fetchDataInSequence(id);
    }
  }

  // Fetch data in sequence: latest readings first, then total energy
  Future<void> _fetchDataInSequence(String deviceId) async {
    // First, fetch latest readings
    await _fetchLatestReadings(deviceId);

    // Then, fetch total energy in background
    _fetchTotalEnergy(deviceId);
  }

  Future<void> _fetchLatestReadings(String deviceId) async {
    setState(() {
      _loadingLatestReadings = true;
      _error = null;
    });

    try {
      // Get all data for the device
      final deviceRootRef = _database.ref('sensorData/$deviceId');
      final deviceRootSnap = await deviceRootRef.get();

      if (!deviceRootSnap.exists || deviceRootSnap.value == null) {
        if (mounted) {
          setState(() {
            _loadingLatestReadings = false;
            _error = 'No data yet for this device';
          });
        }
        return;
      }

      final rawDeviceMap = Map<String, dynamic>.from(
        deviceRootSnap.value as Map,
      );

      PowerData? latestReading;
      DateTime? latestDateTime;

      // Recursively search through all nested data to find the most recent entry
      void searchForLatestReading(dynamic data, [String path = '']) {
        if (data is Map) {
          final dataMap = Map<String, dynamic>.from(data);

          // Check if this is a leaf node (contains sensor data)
          if (dataMap.containsKey('timestamp') &&
              dataMap.containsKey('voltage') &&
              dataMap.containsKey('current')) {
            try {
              final pd = PowerData.fromFirebaseMap(dataMap);
              if (latestDateTime == null ||
                  pd.dateTime.isAfter(latestDateTime!)) {
                latestDateTime = pd.dateTime;
                latestReading = pd;
              }
            } catch (e) {
              print('Error parsing entry at $path: $e');
            }
          } else {
            // Continue searching in nested maps
            for (final key in dataMap.keys) {
              if (key != 'last_reset') {
                // Skip the reset timestamp
                searchForLatestReading(dataMap[key], '$path/$key');
              }
            }
          }
        }
      }

      // Start the recursive search
      searchForLatestReading(rawDeviceMap);

      if (mounted) {
        setState(() {
          _loadingLatestReadings = false;
          _current = latestReading;
          if (latestReading == null) {
            _error = 'No readings found';
          }
        });
      }
    } catch (e) {
      print('Error in _fetchLatestReadings: $e');
      if (mounted) {
        setState(() {
          _loadingLatestReadings = false;
          _error = 'Error fetching latest readings: $e';
        });
      }
    }
  }

  Future<void> _fetchTotalEnergy(String deviceId) async {
    setState(() {
      _loadingTotalEnergy = true;
    });

    try {
      // Read "last_reset" under sensorData/deviceId
      final resetRef = _database.ref('sensorData/$deviceId/last_reset');
      final resetSnap = await resetRef.get();
      DateTime? lastResetDateTime;
      if (resetSnap.exists && resetSnap.value != null) {
        final resetStr = resetSnap.value as String;
        try {
          lastResetDateTime = DateFormat('yyyy/MM/dd HH:mm:ss').parse(resetStr);
        } catch (_) {
          lastResetDateTime = null;
        }
      }

      // Get all device data
      final deviceRootRef = _database.ref('sensorData/$deviceId');
      final deviceRootSnap = await deviceRootRef.get();
      if (!deviceRootSnap.exists || deviceRootSnap.value == null) {
        if (mounted) {
          setState(() {
            _loadingTotalEnergy = false;
          });
        }
        return;
      }

      final rawDeviceMap = Map<String, dynamic>.from(
        deviceRootSnap.value as Map,
      );

      List<PowerData> filteredReadings = [];

      // Recursively collect all readings after reset time
      void collectReadings(dynamic data) {
        if (data is Map) {
          final dataMap = Map<String, dynamic>.from(data);

          // Check if this is a leaf node (contains sensor data)
          if (dataMap.containsKey('timestamp') &&
              dataMap.containsKey('energy')) {
            try {
              final pd = PowerData.fromFirebaseMap(dataMap);
              if (lastResetDateTime == null ||
                  pd.dateTime.isAfter(lastResetDateTime) ||
                  pd.dateTime.isAtSameMomentAs(lastResetDateTime)) {
                filteredReadings.add(pd);
              }
            } catch (e) {
              print('Error parsing reading for total energy: $e');
            }
          } else {
            // Continue searching in nested maps
            for (final key in dataMap.keys) {
              if (key != 'last_reset') {
                collectReadings(dataMap[key]);
              }
            }
          }
        }
      }

      // Collect all readings
      collectReadings(rawDeviceMap);

      // Sum energy (Wh)
      double totalSum = 0.0;
      for (final pd in filteredReadings) {
        totalSum += pd.energy;
      }

      if (mounted) {
        setState(() {
          _loadingTotalEnergy = false;
          _totalEnergySinceReset = totalSum;
        });
      }
    } catch (e) {
      print('Error in _fetchTotalEnergy: $e');
      if (mounted) {
        setState(() {
          _loadingTotalEnergy = false;
        });
      }
    }
  }

  double _calculateTieredCostIQD(double totalKWh) {
    double remaining = totalKWh;
    double cost = 0.0;

    final tier1 = remaining.clamp(0.0, 1500.0);
    cost += tier1 * 10;
    remaining -= tier1;
    if (remaining <= 0) return cost;

    final tier2 = remaining.clamp(0.0, 1500.0);
    cost += tier2 * 35;
    remaining -= tier2;
    if (remaining <= 0) return cost;

    final tier3 = remaining.clamp(0.0, 1000.0);
    cost += tier3 * 80;
    remaining -= tier3;
    if (remaining <= 0) return cost;

    cost += remaining * 120;
    return cost;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Energy Meter'),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Device',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddDeviceScreen()),
              );
              _loadStoredDevices();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadingDevices) ...[
              const Center(child: CircularProgressIndicator()),
            ] else if ((_error != null && _deviceIds.isEmpty)) ...[
              Center(
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ] else if (_deviceIds.isEmpty) ...[
              const Center(
                child: Text(
                  'No devices added.\nTap + to add a device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            ] else ...[
              // If exactly one stored device, display its ID
              if (_deviceIds.length == 1) ...[
                Text(
                  'Device: ${_deviceIds.first}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
              ] else ...[
                DropdownButtonFormField<String>(
                  value: _selectedDeviceId,
                  hint: const Text('Select a Device'),
                  isExpanded: true,
                  items:
                      _deviceIds
                          .map(
                            (id) =>
                                DropdownMenuItem(value: id, child: Text(id)),
                          )
                          .toList(),
                  onChanged: _onDeviceSelected,
                  decoration: const InputDecoration(
                    labelText: 'Device',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Expanded(child: _buildContent()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedDeviceId == null) {
      return const Center(child: Text('Please select a device.'));
    }

    final totalKWh = _totalEnergySinceReset / 1000;
    final costIQD = _calculateTieredCostIQD(totalKWh);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // First row: Current, Energy, Cost (IQD)
          Row(
            children: [
              Expanded(
                child: _buildCard(
                  Icons.electrical_services,
                  'Current (A)',
                  _loadingLatestReadings
                      ? null
                      : _current?.current.toStringAsFixed(3) ?? '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  Icons.battery_charging_full,
                  'Energy (Wh)',
                  _loadingLatestReadings
                      ? null
                      : _current?.energy.toStringAsFixed(1) ?? '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  Icons.attach_money,
                  'Cost (IQD)',
                  _loadingLatestReadings
                      ? null
                      : (_current != null ? costIQD.toStringAsFixed(0) : '--'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Second row: Voltage, Frequency, Power Factor
          Row(
            children: [
              Expanded(
                child: _buildCard(
                  Icons.flash_on,
                  'Voltage (V)',
                  _loadingLatestReadings
                      ? null
                      : _current?.voltage.toStringAsFixed(1) ?? '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  Icons.speed,
                  'Frequency (Hz)',
                  _loadingLatestReadings
                      ? null
                      : _current?.frequency.toStringAsFixed(1) ?? '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  Icons.list_alt,
                  'Power Factor',
                  _loadingLatestReadings
                      ? null
                      : _current?.powerFactor.toStringAsFixed(2) ?? '--',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          if (_current != null && !_loadingLatestReadings) ...[
            Text(
              'Last Update: ${DateFormat('HH:mm:ss').format(_current!.dateTime)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 16),
          ],

          // Total Energy Since Reset (Wh)
          _buildCard(
            Icons.timeline,
            'Total Energy Since Reset (Wh)',
            _loadingTotalEnergy
                ? null
                : _totalEnergySinceReset.toStringAsFixed(1),
          ),
          const SizedBox(height: 16),

          // Live Data Card (styled like other cards)
          _buildCard(
            Icons.sensors,
            'Live Data',
            null,
            isButton: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ScanPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    IconData icon,
    String label,
    String? value, {
    bool isButton = false,
    VoidCallback? onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: isButton ? Theme.of(context).primaryColor : null,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: isButton ? Theme.of(context).primaryColor : null,
                ),
              ),
              if (!isButton) ...[
                const SizedBox(height: 4),
                value == null
                    ? _buildShimmerEffect()
                    : Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerEffect() {
    return Container(
      width: 60,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [Color(0xFFE0E0E0), Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment(-1.0, 0.0),
          end: Alignment(1.0, 0.0),
        ),
      ),
      child: const SizedBox(),
    );
  }
}

/// Model class for PowerData
class PowerData {
  final double voltage;
  final double current;
  final double power;
  final double apparentPower;
  final double powerFactor;
  final double energy;
  final double frequency;
  final DateTime dateTime;

  PowerData({
    required this.voltage,
    required this.current,
    required this.power,
    required this.apparentPower,
    required this.powerFactor,
    required this.energy,
    required this.frequency,
    required this.dateTime,
  });

  factory PowerData.fromFirebaseMap(Map<String, dynamic> m) {
    return PowerData(
      voltage: (m['voltage'] as num).toDouble(),
      current: (m['current'] as num).toDouble(),
      power: (m['power'] as num).toDouble(),
      apparentPower: (m['power'] as num).toDouble(),
      powerFactor: (m['pf'] as num).toDouble(),
      energy: (m['energy'] as num).toDouble(),
      frequency: (m['frequency'] as num).toDouble(),
      dateTime: DateFormat(
        'yyyy/MM/dd HH:mm:ss',
      ).parse(m['timestamp'] as String),
    );
  }
}
