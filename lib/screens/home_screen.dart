// screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:power/screens/add_device_screen.dart';

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
  bool _loadingData = false;
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
    });

    try {
      final devices = await StorageService().loadDevices();
      _storedDevices = devices;
      _deviceIds = _storedDevices.map((d) => d.id).toList();

      if (_deviceIds.length == 1) {
        _selectedDeviceId = _deviceIds.first;
        await _fetchLatestAndTotal(_selectedDeviceId!);
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
    });

    if (id != null) {
      _fetchLatestAndTotal(id);
    }
  }

  Future<void> _fetchLatestAndTotal(String deviceId) async {
    setState(() {
      _loadingData = true;
      _error = null;
      _current = null;
      _totalEnergySinceReset = 0.0;
    });

    try {
      // 1) Read “last_reset” under sensorData/deviceId
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

      // 2) Read the device root to enumerate which “year” keys are there
      final deviceRootRef = _database.ref('sensorData/$deviceId');
      final deviceRootSnap = await deviceRootRef.get();
      if (!deviceRootSnap.exists || deviceRootSnap.value == null) {
        if (mounted) {
          setState(() {
            _loadingData = false;
            _current = null;
            _totalEnergySinceReset = 0.0;
            _error = 'No data yet for this device';
          });
        }
        return;
      }

      final rawDeviceMap = Map<String, dynamic>.from(
        deviceRootSnap.value as Map,
      );

      // 3) Gather all year‐keys (as ints), ignoring “last_reset”
      final yearKeys =
          rawDeviceMap.keys
              .where((k) => k != 'last_reset')
              .map((k) => int.tryParse(k))
              .where((v) => v != null)
              .map((v) => v!)
              .toList()
            ..sort();

      List<PowerData> filteredReadings = [];

      // 4) For each year that is >= lastReset.year, gather months→days→entries
      for (final year in yearKeys) {
        if (lastResetDateTime != null && year < lastResetDateTime.year) {
          continue;
        }
        final yearRef = _database.ref('sensorData/$deviceId/$year');
        final yearSnap = await yearRef.get();
        if (!yearSnap.exists || yearSnap.value == null) continue;

        final monthsMap = Map<String, dynamic>.from(yearSnap.value as Map);
        for (final monthKey in monthsMap.keys) {
          final monthIdx = int.tryParse(monthKey);
          if (monthIdx == null) continue;
          if (lastResetDateTime != null &&
              year == lastResetDateTime.year &&
              monthIdx < lastResetDateTime.month) {
            continue;
          }

          final monthRef = _database.ref(
            'sensorData/$deviceId/$year/$monthKey',
          );
          final monthSnap = await monthRef.get();
          if (!monthSnap.exists || monthSnap.value == null) continue;

          final daysMap = Map<String, dynamic>.from(monthSnap.value as Map);
          for (final dayKey in daysMap.keys) {
            final dayIdx = int.tryParse(dayKey);
            if (dayIdx == null) continue;
            if (lastResetDateTime != null &&
                year == lastResetDateTime.year &&
                monthIdx == lastResetDateTime.month &&
                dayIdx < lastResetDateTime.day) {
              continue;
            }

            final dayRef = _database.ref(
              'sensorData/$deviceId/$year/$monthKey/$dayKey',
            );
            final daySnap = await dayRef.get();
            if (!daySnap.exists || daySnap.value == null) continue;

            final entriesMap = Map<String, dynamic>.from(daySnap.value as Map);
            for (final entryKey in entriesMap.keys) {
              final entryVal = entriesMap[entryKey];
              if (entryVal is! Map) continue;
              final entryMap = Map<String, dynamic>.from(entryVal);
              try {
                final pd = PowerData.fromFirebaseMap(entryMap);
                if (lastResetDateTime != null &&
                    pd.dateTime.isBefore(lastResetDateTime)) {
                  continue;
                }
                filteredReadings.add(pd);
              } catch (_) {
                // ignore parse errors
              }
            }
          }
        }
      }

      // 5) Sort them, pick the latest, and sum energy (Wh)
      filteredReadings.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      final latest = filteredReadings.isNotEmpty ? filteredReadings.last : null;

      double totalSum = 0.0;
      for (final pd in filteredReadings) {
        totalSum += pd.energy;
      }

      if (mounted) {
        setState(() {
          _loadingData = false;
          _current = latest;
          _totalEnergySinceReset = totalSum;
          if (latest == null) {
            _error = 'No data since last reset';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingData = false;
          _error = 'Error fetching data: $e';
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
        actions: [
          // If you have a button to navigate to AddDeviceScreen:
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Device',
            onPressed: () async {
              // Push AddDeviceScreen directly, then reload on return
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
    if (_loadingData && _current == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _current == null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    final totalKWh = _totalEnergySinceReset / 1000;
    final costIQD = _calculateTieredCostIQD(totalKWh);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // First row: Current, Energy, Cost (IQD)
        Row(
          children: [
            Expanded(
              child: _buildCard(
                Icons.electrical_services,
                'Current (A)',
                _current?.current.toStringAsFixed(3) ?? '--',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCard(
                Icons.battery_charging_full,
                'Energy (Wh)',
                _current?.energy.toStringAsFixed(1) ?? '--',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCard(
                Icons.attach_money,
                'Cost (IQD)',
                _current != null ? costIQD.toStringAsFixed(0) : '--',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_current != null) ...[
          Text(
            'Last Update: ${DateFormat('HH:mm:ss').format(_current!.dateTime)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
        ],
        // Second row: Voltage, Frequency, Power Factor
        Row(
          children: [
            Expanded(
              child: _buildCard(
                Icons.flash_on,
                'Voltage (V)',
                _current?.voltage.toStringAsFixed(1) ?? '--',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCard(
                Icons.speed,
                'Frequency (Hz)',
                _current?.frequency.toStringAsFixed(1) ?? '--',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCard(
                Icons.list_alt,
                'Power Factor',
                _current?.powerFactor.toStringAsFixed(2) ?? '--',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row: Total Energy Since Reset (Wh)
        _buildCard(
          Icons.timeline,
          'Total Energy Since Reset (Wh)',
          _totalEnergySinceReset.toStringAsFixed(1),
        ),
      ],
    );
  }

  Widget _buildCard(IconData icon, String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
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
