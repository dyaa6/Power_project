// graph_screen.dart
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
  // Example data types to show in the dropdown
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

  // “All Days” or each unique date from the data
  late List<String> _dayOptions;
  String _selectedDay = 'All Days';

  // Used to keep track of min and max on the X-axis
  double _minX = 0;
  double _maxX = 1;

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final powerDataList = deviceProvider.powerDataList;

    // Build the day dropdown options
    _dayOptions = _buildDayOptions(powerDataList);

    return Scaffold(
      appBar: AppBar(title: const Text('Graphs')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildBody(context, deviceProvider),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DeviceProvider deviceProvider) {
    // 1. Ensure a device is selected
    if (deviceProvider.selectedDevice == null) {
      return const Center(
        child: Text('Please select a device on the Home tab first.'),
      );
    }

    // 2. If data is still loading or empty
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

    // 3. We have data: show dropdowns + line chart
    final List<PowerData> allData = deviceProvider.powerDataList;

    return Column(
      children: [
        Row(
          children: [
            // Data Type Dropdown
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<String>(
                value: _selectedDataType,
                items:
                    _dataTypes.map((type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedDataType = value;
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Data Type',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Day Dropdown
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<String>(
                value: _selectedDay,
                items:
                    _dayOptions.map((day) {
                      return DropdownMenuItem<String>(
                        value: day,
                        child: Text(day),
                      );
                    }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedDay = value;
                    });
                  }
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

  /// Build the day dropdown options from the data.
  /// "All Days" plus each unique date (yyyy-MM-dd).
  List<String> _buildDayOptions(List<PowerData> data) {
    final uniqueDates = <String>{};
    for (final reading in data) {
      final dateStr = DateFormat('yyyy-MM-dd').format(reading.dateTime);
      uniqueDates.add(dateStr);
    }

    final days = ['All Days', ...uniqueDates.toList()];

    // If the current selection is not in the list (device changed, etc.), reset
    if (!days.contains(_selectedDay)) {
      _selectedDay = 'All Days';
    }
    return days;
  }

  /// Build the FLChart line chart using the filtered data
  Widget _buildLineChart(List<PowerData> allData) {
    // 1. Filter data by day if needed
    List<PowerData> filteredData = allData;
    if (_selectedDay != 'All Days') {
      filteredData =
          allData.where((rd) {
            final dateStr = DateFormat('yyyy-MM-dd').format(rd.dateTime);
            return dateStr == _selectedDay;
          }).toList();
    }

    // Sort by ascending time
    filteredData.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // 2. Convert to List<FlSpot>
    final spots = <FlSpot>[];
    if (filteredData.isNotEmpty) {
      final firstTime =
          filteredData.first.dateTime.millisecondsSinceEpoch.toDouble();
      // Build spots and transform time => offset from firstTime
      for (var rd in filteredData) {
        final double x =
            rd.dateTime.millisecondsSinceEpoch.toDouble() - firstTime;
        final double y = _selectValue(rd, _selectedDataType);
        spots.add(FlSpot(x, y));
      }
    }

    // 3. Determine min/max for the X axis
    if (spots.isNotEmpty) {
      _minX = spots.first.x;
      _maxX = spots.last.x;
    } else {
      _minX = 0;
      _maxX = 1;
    }

    // 4. Create a single line for the selected data type
    final line = LineChartBarData(
      spots: spots,
      isCurved: true,
      dotData: FlDotData(show: true),
      belowBarData: BarAreaData(show: false),
    );

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (
            LineChartBarData barData,
            List<int> spotIndexes,
          ) {
            // Show a vertical line & highlight the touched spot
            return spotIndexes.map((index) {
              return TouchedSpotIndicatorData(
                FlLine(color: Colors.grey, strokeWidth: 1),
                FlDotData(show: true),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                final dt = _xToDateTime(spot.x, filteredData);
                final timeStr = DateFormat('HH:mm:ss').format(dt);
                return LineTooltipItem(
                  '$timeStr\n${spot.y.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
        minX: _minX,
        maxX: _maxX,
        titlesData: FlTitlesData(
          // Increase left Titles width
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45, // <-- more horizontal space for large labels
              getTitlesWidget: (value, meta) {
                // Format how the vertical axis labels appear
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(),
          topTitles: AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (_maxX - _minX) / 4, // e.g. 4 intervals
              getTitlesWidget: (value, meta) {
                final dt = _xToDateTime(value, filteredData);
                // Show short time if single day, or date+time if multiple days
                final dayStr = DateFormat('MM-dd').format(dt);
                final timeStr = DateFormat('HH:mm').format(dt);
                if (_selectedDay == 'All Days') {
                  // Show date + time
                  return Text(
                    '$dayStr\n$timeStr',
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                  );
                } else {
                  // Show time only
                  return Text(timeStr, style: const TextStyle(fontSize: 10));
                }
              },
            ),
          ),
        ),
        gridData: FlGridData(show: true),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            bottom: BorderSide(color: Colors.black12),
            left: BorderSide(color: Colors.black12),
            right: BorderSide.none,
            top: BorderSide.none,
          ),
        ),
        lineBarsData: [line],
      ),
    );
  }

  /// Extract numeric value from PowerData based on the selected data type
  double _selectValue(PowerData rd, String dataType) {
    switch (dataType) {
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

  /// Convert x-axis double back to a DateTime for labels & tooltips
  DateTime _xToDateTime(double x, List<PowerData> filteredData) {
    if (filteredData.isEmpty) {
      return DateTime.now();
    }
    final firstTime =
        filteredData.first.dateTime.millisecondsSinceEpoch.toDouble();
    final realTimeMs = firstTime + x;
    return DateTime.fromMillisecondsSinceEpoch(realTimeMs.toInt());
  }
}
