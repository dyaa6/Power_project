// lib/screens/graph_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/power_data.dart';
import '../services/storage_service.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> with WidgetsBindingObserver {
  // ─── List of device IDs loaded from local storage ───
  List<String> _devices = [];
  bool _loadingDevices = true;
  String? _deviceError;

  // ─── Selected device ID (or null if none) ───
  String? _selectedDeviceId;

  // ─── Reading data for the selected device ───
  List<PowerData> _powerDataList = [];
  bool _loadingData = false;
  String? _dataError;

  // ─── Dropdowns for chart: data types and days ───
  final List<String> _dataTypes = [
    'Voltage',
    'Current',
    'Power',
    'Apparent Power',
    'Power Factor',
    'Energy',
    'Frequency',
  ];
  String _selectedDataType = 'Voltage';
  List<String> _dayOptions = ['All Days'];
  String _selectedDay = 'All Days';

  // ─── Chart axis bounds ───
  double _minX = 0;
  double _maxX = 1;

  // ─── Firebase instance with authentication ───
  late FirebaseDatabase _database;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFirebase();
    _loadStoredDevices();
  }

  void _initializeFirebase() {
    _database = FirebaseDatabase(
      databaseURL:
          'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    // Set authentication token if needed (uncomment if authentication is required)
    // _database.ref().authWithCustomToken('G7FMO4LjkSOHrs5Ms5it3aHKKfOsb57Z9SzP2e');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When coming back (e.g., after adding a device), reload stored devices
    if (state == AppLifecycleState.resumed) {
      _loadStoredDevices();
    }
  }

  /// Loads the list of device IDs from local storage
  Future<void> _loadStoredDevices() async {
    setState(() {
      _loadingDevices = true;
      _deviceError = null;
      _devices = [];
      _selectedDeviceId = null;
      _powerDataList = [];
      _dataError = null;
    });

    try {
      final storedDevices = await StorageService().loadDevices();
      _devices = storedDevices.map((d) => d.id).toList()..sort();

      // If exactly one device, auto-select it and begin loading data
      if (_devices.length == 1) {
        _selectedDeviceId = _devices.first;
        await _fetchPowerData(_selectedDeviceId!);
      }
    } catch (e) {
      _deviceError = 'Error loading stored devices: $e';
      _devices = [];
      _selectedDeviceId = null;
    }

    if (mounted) {
      setState(() {
        _loadingDevices = false;
      });
    }
  }

  /// Fetches all PowerData readings for a given deviceId
  Future<void> _fetchPowerData(String deviceId) async {
    setState(() {
      _loadingData = true;
      _dataError = null;
      _powerDataList = [];
    });

    try {
      print('Fetching data for device: $deviceId'); // Debug log

      // Read the device node from sensorData
      final deviceRef = _database.ref('sensorData/$deviceId');
      final deviceSnapshot = await deviceRef.get();

      if (!deviceSnapshot.exists || deviceSnapshot.value == null) {
        if (mounted) {
          setState(() {
            _loadingData = false;
            _dataError = 'No data available for device: $deviceId';
          });
        }
        return;
      }

      // Cast to Map to traverse the nested structure
      final deviceData = Map<String, dynamic>.from(deviceSnapshot.value as Map);
      final List<PowerData> tempReadings = [];

      print('Device data keys: ${deviceData.keys}'); // Debug log

      // Iterate through years -> months -> days -> entries
      deviceData.forEach((yearKey, yearValue) {
        if (yearValue is! Map) return;

        final yearData = Map<String, dynamic>.from(yearValue);
        final year = int.tryParse(yearKey);
        if (year == null) return;

        yearData.forEach((monthKey, monthValue) {
          if (monthValue is! Map) return;

          final monthData = Map<String, dynamic>.from(monthValue);
          final month = int.tryParse(monthKey);
          if (month == null) return;

          monthData.forEach((dayKey, dayValue) {
            if (dayValue is! Map) return;

            final dayData = Map<String, dynamic>.from(dayValue);
            final day = int.tryParse(dayKey);
            if (day == null) return;

            // Process each entry in the day
            dayData.forEach((entryKey, entryValue) {
              if (entryValue is! Map) return;

              try {
                final entryMap = Map<String, dynamic>.from(entryValue);

                // Parse the timestamp and convert to DateTime
                if (entryMap.containsKey('timestamp') &&
                    entryMap['timestamp'] is String) {
                  final timestampStr = entryMap['timestamp'] as String;
                  try {
                    final parsedDateTime = DateFormat(
                      'yyyy/MM/dd HH:mm:ss',
                    ).parse(timestampStr);

                    // Create PowerData object with proper field mapping
                    final powerData = PowerData(
                      voltage: (entryMap['voltage'] as num?)?.toDouble() ?? 0.0,
                      current: (entryMap['current'] as num?)?.toDouble() ?? 0.0,
                      power: (entryMap['power'] as num?)?.toDouble() ?? 0.0,
                      apparentPower: _calculateApparentPower(
                        (entryMap['voltage'] as num?)?.toDouble() ?? 0.0,
                        (entryMap['current'] as num?)?.toDouble() ?? 0.0,
                      ),
                      powerFactor: (entryMap['pf'] as num?)?.toDouble() ?? 0.0,
                      energy: (entryMap['energy'] as num?)?.toDouble() ?? 0.0,
                      frequency:
                          (entryMap['frequency'] as num?)?.toDouble() ?? 0.0,
                      timestamp: parsedDateTime.millisecondsSinceEpoch,
                    );

                    tempReadings.add(powerData);
                  } catch (e) {
                    print('Error parsing timestamp: $timestampStr, Error: $e');
                  }
                }
              } catch (e) {
                print('Error processing entry: $e');
              }
            });
          });
        });
      });

      // Sort readings by timestamp
      tempReadings.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      print('Total readings loaded: ${tempReadings.length}'); // Debug log

      if (mounted) {
        setState(() {
          _loadingData = false;
          _powerDataList = tempReadings;
          if (_powerDataList.isEmpty) {
            _dataError = 'No valid readings found for this device.';
          } else {
            _dataError = null;
          }
        });
      }
    } catch (e) {
      print('Error fetching power data: $e'); // Debug log
      if (mounted) {
        setState(() {
          _loadingData = false;
          _powerDataList = [];
          _dataError = 'Error fetching data: $e';
        });
      }
    }
  }

  /// Calculate apparent power from voltage and current
  double _calculateApparentPower(double voltage, double current) {
    return voltage * current;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Power Consumption Graphs'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(padding: const EdgeInsets.all(16.0), child: _buildBody()),
    );
  }

  Widget _buildBody() {
    // 1) If still loading the list of devices:
    if (_loadingDevices) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading devices...'),
          ],
        ),
      );
    }

    // 2) If error occurred when loading devices:
    if (_deviceError != null && _devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Error: $_deviceError',
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _loadStoredDevices, child: Text('Retry')),
          ],
        ),
      );
    }

    // 3) If no stored devices exist at all:
    if (_devices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.device_unknown, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No devices added yet.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Please add a device first to view graphs.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 4) If exactly one device, auto-select and hide dropdown:
    if (_devices.length == 1) {
      if (_selectedDeviceId != _devices.first) {
        _selectedDeviceId = _devices.first;
        _fetchPowerData(_selectedDeviceId!);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.electrical_services, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Device: ${_devices.first}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildDataSection()),
        ],
      );
    }

    // 5) More than one device: show dropdown to pick one
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              value: _selectedDeviceId,
              hint: const Text('Select Device'),
              isExpanded: true,
              items:
                  _devices
                      .map(
                        (id) => DropdownMenuItem<String>(
                          value: id,
                          child: Row(
                            children: [
                              Icon(Icons.electrical_services, size: 20),
                              SizedBox(width: 8),
                              Text(id),
                            ],
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (id) {
                if (id != null && id != _selectedDeviceId) {
                  setState(() {
                    _selectedDeviceId = id;
                    _powerDataList.clear();
                    _dataError = null;
                  });
                  _fetchPowerData(id);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Device',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.devices),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildDataSection()),
      ],
    );
  }

  /// Shows data‐type/day‐filter dropdowns and the line chart (or errors/messages)
  Widget _buildDataSection() {
    // 1) If no device is selected (only possible when >1 device and none chosen):
    if (_selectedDeviceId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Please select a device to view its data.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 2) If still loading the data for this device:
    if (_loadingData) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading power data...'),
          ],
        ),
      );
    }

    // 3) If error occurred and no readings:
    if (_dataError != null && _powerDataList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Error: $_dataError',
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (_selectedDeviceId != null) {
                  _fetchPowerData(_selectedDeviceId!);
                }
              },
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    // 4) If there are no readings at all:
    if (_powerDataList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No readings available yet.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Data will appear here once your device starts sending readings.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 5) Build day‐filter dropdown options now that data is loaded:
    _dayOptions = _buildDayOptions(_powerDataList);

    // 6) Show data‐type + day dropdowns, then the chart:
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedDataType,
                items:
                    _dataTypes
                        .map(
                          (type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedDataType = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Data Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.analytics),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedDay,
                items:
                    _dayOptions
                        .map(
                          (day) => DropdownMenuItem<String>(
                            value: day,
                            child: Text(day),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedDay = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Select Day',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Data summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Total Readings',
                  '${_powerDataList.length}',
                  Icons.data_usage,
                ),
                _buildStatItem('Date Range', _getDateRange(), Icons.date_range),
                _buildStatItem(
                  'Latest Reading',
                  _getLatestReading(),
                  Icons.access_time,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(child: _buildLineChart(_powerDataList)),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  String _getDateRange() {
    if (_powerDataList.isEmpty) return 'N/A';
    final first = DateFormat('MM/dd').format(
      DateTime.fromMillisecondsSinceEpoch(_powerDataList.first.timestamp),
    );
    final last = DateFormat('MM/dd').format(
      DateTime.fromMillisecondsSinceEpoch(_powerDataList.last.timestamp),
    );
    return '$first - $last';
  }

  String _getLatestReading() {
    if (_powerDataList.isEmpty) return 'N/A';
    return DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(_powerDataList.last.timestamp),
    );
  }

  /// Builds a sorted list of unique "yyyy-MM-dd" dates from the data.
  List<String> _buildDayOptions(List<PowerData> data) {
    final uniqueDates = <String>{};
    for (final reading in data) {
      uniqueDates.add(
        DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.fromMillisecondsSinceEpoch(reading.timestamp)),
      );
    }
    final days = ['All Days', ...uniqueDates.toList()..sort()];
    if (!days.contains(_selectedDay)) {
      _selectedDay = 'All Days';
    }
    return days;
  }

  /// Constructs a LineChart of the filtered data.
  Widget _buildLineChart(List<PowerData> allData) {
    // 1) Filter by day if needed:
    List<PowerData> filtered = allData;
    if (_selectedDay != 'All Days') {
      filtered =
          allData
              .where(
                (rd) =>
                    DateFormat('yyyy-MM-dd').format(
                      DateTime.fromMillisecondsSinceEpoch(rd.timestamp),
                    ) ==
                    _selectedDay,
              )
              .toList();
    }
    filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No data for selected day.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 2) Build FlSpot list - FIXED: Using DateTime.millisecondsSinceEpoch properly
    final firstTime = filtered.first.timestamp.toDouble();
    final spots =
        filtered
            .map(
              (rd) => FlSpot(
                rd.timestamp.toDouble() - firstTime,
                _selectValue(rd, _selectedDataType),
              ),
            )
            .toList();

    // 3) Compute x & y bounds
    _minX = spots.first.x;
    _maxX = spots.last.x;

    final yValues =
        filtered.map((rd) => _selectValue(rd, _selectedDataType)).toList();
    final minY = yValues.reduce((a, b) => a < b ? a : b);
    final maxY = yValues.reduce((a, b) => a > b ? a : b);

    // Add some padding to y-axis
    final yPadding = (maxY - minY) * 0.1;
    final adjustedMinY = minY - yPadding;
    final adjustedMaxY = maxY + yPadding;

    // 4) Compute intervals
    final xRange = _maxX - _minX;
    final xInterval = xRange > 0 ? xRange / 5.0 : 1.0;

    final yRange = adjustedMaxY - adjustedMinY;
    final yInterval =
        yRange > 0
            ? yRange / 5.0
            : (adjustedMaxY == 0.0 ? 1.0 : adjustedMaxY / 5.0);

    // 5) Return the LineChart
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_selectedDataType ${_selectedDay != 'All Days' ? 'for $_selectedDay' : 'Overview'}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: _minX,
                  maxX: _maxX,
                  minY: adjustedMinY,
                  maxY: adjustedMaxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: filtered.length <= 20,
                        getDotPainter:
                            (spot, percent, barData, index) =>
                                FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.blue,
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: yInterval,
                        reservedSize: 50,
                        getTitlesWidget:
                            (value, meta) => Text(
                              _formatYAxisValue(value, _selectedDataType),
                              style: const TextStyle(fontSize: 11),
                            ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: xInterval,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          // FIXED: Properly construct DateTime from milliseconds
                          final dt = DateTime.fromMillisecondsSinceEpoch(
                            (firstTime + value).toInt(),
                          );
                          final dateFmt = DateFormat('MM-dd').format(dt);
                          final timeFmt = DateFormat('HH:mm').format(dt);
                          return _selectedDay == 'All Days'
                              ? Text(
                                '$dateFmt\n$timeFmt',
                                style: const TextStyle(fontSize: 9),
                                textAlign: TextAlign.center,
                              )
                              : Text(
                                timeFmt,
                                style: const TextStyle(fontSize: 10),
                              );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    drawHorizontalLine: true,
                    getDrawingHorizontalLine:
                        (value) => FlLine(
                          color: Colors.grey.withOpacity(0.3),
                          strokeWidth: 1,
                        ),
                    getDrawingVerticalLine:
                        (value) => FlLine(
                          color: Colors.grey.withOpacity(0.3),
                          strokeWidth: 1,
                        ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatYAxisValue(double value, String dataType) {
    switch (dataType) {
      case 'Voltage':
        return '${value.toStringAsFixed(0)}V';
      case 'Current':
        return '${value.toStringAsFixed(1)}A';
      case 'Power':
      case 'Apparent Power':
        return '${value.toStringAsFixed(0)}W';
      case 'Power Factor':
        return value.toStringAsFixed(2);
      case 'Energy':
        return '${value.toStringAsFixed(1)}kWh';
      case 'Frequency':
        return '${value.toStringAsFixed(1)}Hz';
      default:
        return value.toStringAsFixed(1);
    }
  }

  /// Returns the chosen numeric field from a PowerData instance.
  double _selectValue(PowerData rd, String type) {
    switch (type) {
      case 'Voltage':
        return rd.voltage;
      case 'Current':
        return rd.current;
      case 'Power':
        return rd.power;
      case 'Apparent Power':
        return rd.apparentPower;
      case 'Power Factor':
        return rd.powerFactor;
      case 'Energy':
        return rd.energy;
      case 'Frequency':
        return rd.frequency;
      default:
        return 0.0;
    }
  }
}
