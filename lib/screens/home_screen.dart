import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

// Firebase configuration
const DB_URL =
    'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app';
const AUTH = 'G7FMO4LjkSOHrs5Ms5it3m1aHKKfOsb57Z9SzP2e';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double costPerKWh = 0.20;
  final FirebaseDatabase _database = FirebaseDatabase(databaseURL: DB_URL);
  StreamSubscription<DatabaseEvent>? _dataSub;

  List<String> _devices = [];
  String? _selectedDevice;

  bool _loadingDevices = true;
  bool _loadingData = false;
  String? _error;

  List<PowerData> _readings = [];
  PowerData? _current;
  bool _showTable = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initFirebase();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initFirebase() async {
    await Firebase.initializeApp();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() {
      _loadingDevices = true;
      _error = null;
    });
    try {
      final ref = _database.ref('sensorData');
      final snap = await ref.get();
      if (snap.exists && snap.value != null) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        _devices = map.keys.toList();
      } else {
        _devices = [];
      }
    } catch (e) {
      _error = 'Failed to load devices';
    }
    setState(() {
      _loadingDevices = false;
    });
  }

  void _onDeviceSelected(String? id) {
    if (_selectedDevice == id) return;
    _cancelSubscription();
    setState(() {
      _selectedDevice = id;
      _readings.clear();
      _current = null;
      _error = null;
    });
    if (id != null) _listenToData(id);
  }

  void _listenToData(String deviceId) {
    setState(() => _loadingData = true);
    final ref = _database.ref('sensorData/$deviceId');
    _dataSub = ref.onValue.listen(
      (event) {
        setState(() {
          _loadingData = false;
          _error = null;
          _readings = [];
        });
        if (event.snapshot.exists && event.snapshot.value != null) {
          final raw = Map<String, dynamic>.from(event.snapshot.value as Map);
          raw.forEach((year, yMap) {
            final months = Map<String, dynamic>.from(yMap as Map);
            months.forEach((month, mMap) {
              final days = Map<String, dynamic>.from(mMap as Map);
              days.forEach((day, dMap) {
                final entries = Map<String, dynamic>.from(dMap as Map);
                entries.forEach((key, val) {
                  final entry = Map<String, dynamic>.from(val as Map);
                  try {
                    final pd = PowerData.fromFirebaseMap(entry);
                    _readings.add(pd);
                  } catch (_) {}
                });
              });
            });
          });
          _readings.sort((a, b) => a.dateTime.compareTo(b.dateTime));
          setState(() {
            _current = _readings.isNotEmpty ? _readings.last : null;
          });
        } else {
          setState(() {
            _error = 'No data yet';
            _readings.clear();
            _current = null;
          });
        }
      },
      onError: (_) {
        setState(() {
          _loadingData = false;
          _error = 'Error listening to data';
        });
      },
    );
  }

  void _cancelSubscription() {
    _dataSub?.cancel();
    _dataSub = null;
  }

  @override
  void dispose() {
    _cancelSubscription();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Energy Meter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadingDevices)
              const Center(child: CircularProgressIndicator())
            else if (_error != null && _devices.isEmpty)
              Center(
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else ...[
              DropdownButtonFormField<String>(
                value: _selectedDevice,
                hint: const Text('Select a Device'),
                isExpanded: true,
                items:
                    _devices
                        .map(
                          (id) => DropdownMenuItem(value: id, child: Text(id)),
                        )
                        .toList(),
                onChanged: _onDeviceSelected,
                decoration: const InputDecoration(
                  labelText: 'Device',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(child: _buildContent()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedDevice == null)
      return const Center(child: Text('Please select a device.'));
    if (_loadingData && _readings.isEmpty)
      return const Center(child: CircularProgressIndicator());
    if (_error != null && _readings.isEmpty)
      return Center(
        child: Text(
          'Error: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  'Cost',
                  _current != null
                      ? '\$${(_current!.energy / 1000 * costPerKWh).toStringAsFixed(2)}'
                      : '--',
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
          ElevatedButton(
            onPressed: () => setState(() => _showTable = !_showTable),
            child: Text(_showTable ? 'Hide Readings' : 'Show All Readings'),
          ),
          if (_showTable) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('V')),
                  DataColumn(label: Text('A')),
                  DataColumn(label: Text('W')),
                  DataColumn(label: Text('VA')),
                  DataColumn(label: Text('PF')),
                  DataColumn(label: Text('Wh')),
                  DataColumn(label: Text('Hz')),
                ],
                rows:
                    _readings.map((r) {
                      final date = DateFormat('yyyy-MM-dd').format(r.dateTime);
                      final time = DateFormat('HH:mm:ss').format(r.dateTime);
                      return DataRow(
                        cells: [
                          DataCell(Text(date)),
                          DataCell(Text(time)),
                          DataCell(Text(r.voltage.toStringAsFixed(1))),
                          DataCell(Text(r.current.toStringAsFixed(3))),
                          DataCell(Text(r.power.toStringAsFixed(1))),
                          DataCell(Text(r.apparentPower.toStringAsFixed(1))),
                          DataCell(Text(r.powerFactor.toStringAsFixed(2))),
                          DataCell(Text(r.energy.toStringAsFixed(1))),
                          DataCell(Text(r.frequency.toStringAsFixed(1))),
                        ],
                      );
                    }).toList(),
              ),
            ),
          ],
        ],
      ),
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

// Model class for PowerData (add in ../models/power_data.dart)
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
