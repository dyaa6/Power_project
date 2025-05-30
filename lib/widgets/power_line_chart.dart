// lib/widgets/power_line_chart.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/power_data.dart';

class PowerLineChart extends StatelessWidget {
  final List<PowerData> data;
  const PowerLineChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No data to chart.'));
    }

    // Convert to FlSpots: x = index, y = power (W)
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].power),
    ];

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    // Compute non-zero intervals as double
    final double rawXInterval = (maxX - minX) / 5.0;
    final double xInterval = rawXInterval <= 0 ? 1.0 : rawXInterval;

    final double rawYInterval = (maxY - minY) / 5.0;
    final double yInterval =
        rawYInterval <= 0 ? (maxY == 0.0 ? 1.0 : maxY / 5.0) : rawYInterval;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Reading #'),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                interval: xInterval, // now a double
                getTitlesWidget:
                    (value, meta) => Text(value.toInt().toString()),
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('Power (W)'),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                interval: yInterval, // also a double
                getTitlesWidget:
                    (value, meta) => Text(value.toStringAsFixed(0)),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
          gridData: FlGridData(show: true),
          borderData: FlBorderData(show: true),
        ),
      ),
    );
  }
}
