// lib/screens/electricity_cost_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

class ElectricityCostScreen extends StatelessWidget {
  const ElectricityCostScreen({Key? key}) : super(key: key);

  // Billing slabs
  static const double _thresholdKW = 1500.0;
  static const double _lowRateIQD = 10.0; // up to 1500 kWh
  static const double _highRateIQD = 35.0; // above 1500 kWh

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);

    // Total month-to-date consumption, in kWh
    final double usageKWh = deviceProvider.monthlyConsumption;

    // Determine which rate applies
    final bool isLowTier = usageKWh <= _thresholdKW;
    final double appliedRate = isLowTier ? _lowRateIQD : _highRateIQD;

    // Compute total cost for the month
    final double totalCostIQD = usageKWh * appliedRate;

    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Electricity Cost')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child:
            usageKWh > 0
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This Month\'s Usage:', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '${usageKWh.toStringAsFixed(2)} kWh',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 32),
                    Text('Applied Rate:', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '${appliedRate.toStringAsFixed(0)} IQD/kWh',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const Divider(height: 32),
                    Center(
                      child: Text(
                        'Total Cost:\n${totalCostIQD.toStringAsFixed(2)} IQD',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                  ],
                )
                : Center(
                  child: Text(
                    'No sufficient data to calculate monthly cost.\n'
                    'Please let the app collect at least two readings.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
      ),
    );
  }
}
