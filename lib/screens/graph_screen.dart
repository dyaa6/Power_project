// lib/screens/graph_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../providers/device_provider.dart';
import '../models/power_data.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({Key? key}) : super(key: key);

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  final List<String> _dataTypes = [
    'Voltage',
    'Current',
    'Power',
    'Apparent',
    'Power Factor',
    'Energy',
    'Frequency',
  ];
  String _selectedDataType = 'Voltage';
  late List<String> _dayOptions;
  String _selectedDay = 'All Days';

  // These fields can still be used if you want to persist zoom/pan state,
  // but we recompute them every build anyway.
  double _minX = 0;
  double _maxX = 1;

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final powerDataList = deviceProvider.powerDataList;
    _dayOptions = _buildDayOptions(powerDataList);

    return Scaffold(
      appBar: AppBar(title: const Text('Graphs')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildBody(deviceProvider),
      ),
    );
  }

  Widget _buildBody(DeviceProvider deviceProvider) {
    if (deviceProvider.selectedDevice == null) {
      return const Center(
        child: Text('Please select a device on the Home tab first.'),
      );
    }
    if (deviceProvider.isFirebaseLoading &&
        deviceProvider.powerDataList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (deviceProvider.errorMessage != null &&
        deviceProvider.powerDataList.isEmpty) {
      return Center(
        child: Text(
          'Error: ${deviceProvider.errorMessage}',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (deviceProvider.powerDataList.isEmpty) {
      return const Center(child: Text('No readings available yet.'));
    }

    final allData = deviceProvider.powerDataList;

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
                          (type) =>
                              DropdownMenuItem(value: type, child: Text(type)),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedDataType = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Data Type',
                  border: OutlineInputBorder(),
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
                          (day) =>
                              DropdownMenuItem(value: day, child: Text(day)),
                        )
                        .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedDay = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Select Day',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Expanded(child: _buildLineChart(allData)),
      ],
    );
  }

  List<String> _buildDayOptions(List<PowerData> data) {
    final uniqueDates = <String>{};
    for (final reading in data) {
      uniqueDates.add(DateFormat('yyyy-MM-dd').format(reading.dateTime));
    }
    final days = ['All Days', ...uniqueDates.toList()];
    if (!days.contains(_selectedDay)) _selectedDay = 'All Days';
    return days;
  }

  Widget _buildLineChart(List<PowerData> allData) {
    // 1. Filter by day
    List<PowerData> filtered = allData;
    if (_selectedDay != 'All Days') {
      filtered =
          allData
              .where(
                (rd) =>
                    DateFormat('yyyy-MM-dd').format(rd.dateTime) ==
                    _selectedDay,
              )
              .toList();
    }
    filtered.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (filtered.isEmpty) {
      return const Center(child: Text('No data for selected day.'));
    }

    // 2. Build spots
    final firstTime = filtered.first.dateTime.millisecondsSinceEpoch.toDouble();
    final spots =
        filtered
            .map(
              (rd) => FlSpot(
                rd.dateTime.millisecondsSinceEpoch.toDouble() - firstTime,
                _selectValue(rd, _selectedDataType),
              ),
            )
            .toList();

    // 3. Compute ranges
    _minX = spots.first.x;
    _maxX = spots.last.x;

    final yValues =
        filtered.map((rd) => _selectValue(rd, _selectedDataType)).toList();
    final minY = yValues.reduce((a, b) => a < b ? a : b);
    final maxY = yValues.reduce((a, b) => a > b ? a : b);

    // 4. Compute non-zero intervals
    final double xRange = _maxX - _minX;
    final double xInterval = xRange > 0 ? xRange / 4.0 : 1.0;

    final double yRange = maxY - minY;
    final double yInterval =
        yRange > 0 ? yRange / 4.0 : (maxY == 0.0 ? 1.0 : maxY / 4.0);

    // 5. Build the chart
    return LineChart(
      LineChartData(
        minX: _minX,
        maxX: _maxX,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yInterval,
              reservedSize: 45,
              getTitlesWidget:
                  (value, meta) => Text(
                    value.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 12),
                  ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                final dt = DateTime.fromMillisecondsSinceEpoch(
                  (firstTime + value).toInt(),
                );
                final dateFmt = DateFormat('MM-dd').format(dt);
                final timeFmt = DateFormat('HH:mm').format(dt);
                return _selectedDay == 'All Days'
                    ? Text(
                      '$dateFmt\n$timeFmt',
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    )
                    : Text(timeFmt, style: const TextStyle(fontSize: 10));
              },
            ),
          ),
          rightTitles: AxisTitles(),
          topTitles: AxisTitles(),
        ),
        gridData: FlGridData(show: true),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            bottom: BorderSide(color: Colors.black12),
            left: BorderSide(color: Colors.black12),
          ),
        ),
      ),
    );
  }

  double _selectValue(PowerData rd, String type) {
    switch (type) {
      case 'Voltage':
        return rd.voltage;
      case 'Current':
        return rd.current;
      case 'Power':
        return rd.power;
      case 'Apparent':
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
