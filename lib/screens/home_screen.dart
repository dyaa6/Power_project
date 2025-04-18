// home_screen.dart
import 'package:flutter/material.dart';
import 'package:power/screens/add_device_screen.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date/time formatting

import '../providers/device_provider.dart';
import '../models/device.dart';
import '../models/power_data.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
        return Scaffold(
          appBar: AppBar(title: const Text('Smart Energy Mitter')),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildBody(context, deviceProvider),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, DeviceProvider deviceProvider) {
    // 1. Initial Loading
    if (deviceProvider.isLoading && deviceProvider.devices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. No Devices Case
    if (deviceProvider.devices.isEmpty) {
      return _buildNoDevices(context);
    }

    // 3. We have devices; show dropdown and data
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceSelector(context, deviceProvider),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        _buildDeviceData(context, deviceProvider),
      ],
    );
  }

  /// Shown when there are no devices in the provider
  Widget _buildNoDevices(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'There are no linked devices.',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Device'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddDeviceScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Drop-down to select which device is currently being viewed
  Widget _buildDeviceSelector(
    BuildContext context,
    DeviceProvider deviceProvider,
  ) {
    return DropdownButtonFormField<Device>(
      value: deviceProvider.selectedDevice,
      hint: const Text('Select a Device'),
      isExpanded: true,
      items:
          deviceProvider.devices.map((Device device) {
            return DropdownMenuItem<Device>(
              value: device,
              child: Text(device.name),
            );
          }).toList(),
      onChanged: (Device? newValue) {
        if (newValue != null) {
          deviceProvider.selectDevice(newValue);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Current Device',
        border: OutlineInputBorder(),
      ),
    );
  }

  /// Main widget to show the data (now a table of multiple readings)
  Widget _buildDeviceData(BuildContext context, DeviceProvider deviceProvider) {
    // If no device is selected, show prompt
    if (deviceProvider.selectedDevice == null) {
      return const Center(child: Text('Please select a device.'));
    }

    // If still loading Firebase data AND we have no stored readings
    if (deviceProvider.isFirebaseLoading &&
        deviceProvider.powerDataList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Check for errors
    if (deviceProvider.errorMessage != null &&
        deviceProvider.powerDataList.isEmpty) {
      return Center(
        child: Text(
          'Error: ${deviceProvider.errorMessage}',
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }

    // If we have no readings yet
    if (deviceProvider.powerDataList.isEmpty) {
      return const Center(child: Text('No readings available yet.'));
    }

    // We have a list of readings to display
    final List<PowerData> readings = deviceProvider.powerDataList;

    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // Horizontal scroll
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical, // Nested vertical scroll
            child: DataTable(
              // Tighter spacing for minimum column widths
              columnSpacing: 12,
              horizontalMargin: 8,
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('V')), // VOLTAGE
                DataColumn(label: Text('A')), // CURRENT
                DataColumn(label: Text('W')), // POWER
                DataColumn(label: Text('VA')), //APPERANT
                DataColumn(label: Text('PF')), //POWER FACTOR
                DataColumn(label: Text('Wh')), //ENERGY
                DataColumn(label: Text('Hz')), //FREQ.
              ],
              rows:
                  readings.map((reading) {
                    final dateStr = DateFormat(
                      'yyyy-MM-dd',
                    ).format(reading.dateTime);
                    final timeStr = DateFormat(
                      'HH:mm:ss',
                    ).format(reading.dateTime);

                    return DataRow(
                      cells: [
                        DataCell(Text(dateStr)),
                        DataCell(Text(timeStr)),
                        DataCell(Text(reading.voltage.toStringAsFixed(1))),
                        DataCell(Text(reading.current.toStringAsFixed(3))),
                        DataCell(Text(reading.power.toStringAsFixed(1))),
                        DataCell(
                          Text(reading.apparentPower.toStringAsFixed(1)),
                        ),
                        DataCell(Text(reading.powerFactor.toStringAsFixed(2))),
                        DataCell(Text(reading.energy.toStringAsFixed(1))),
                        DataCell(Text(reading.frequency.toStringAsFixed(1))),
                      ],
                    );
                  }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
