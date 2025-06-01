// scan.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'live.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({Key? key}) : super(key: key);

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final List<Map<String, dynamic>> _discoveredDevices = [];
  bool _isScanning = false;
  String _currentIp = "";
  int _scannedCount = 0;
  final mainColor = const Color(0xFF075E54);
  String _baseIp = "";
  bool _isCheckingStoredDevice = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _determineBaseIp();
    await _checkStoredDeviceAccess();
  }

  Future<void> _checkStoredDeviceAccess() async {
    setState(() {
      _isCheckingStoredDevice = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDeviceData = prefs.getString('stored_device');

      if (storedDeviceData != null) {
        final deviceInfo = json.decode(storedDeviceData);
        final storedIp = deviceInfo['ip'];
        final storedName = deviceInfo['name'];

        // Check if stored device is still accessible
        try {
          final response = await http
              .get(Uri.parse('http://$storedIp/identify'))
              .timeout(const Duration(milliseconds: 2000));

          if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            if (responseData['device'] == 'SEM') {
              // Stored device is accessible, redirect automatically
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            LivePage(title: storedName, ipAddress: storedIp),
                  ),
                );
                return;
              }
            }
          }
        } catch (e) {
          print('Stored device not accessible: $e');
          // Keep stored device even if not accessible
        }
      }
    } catch (e) {
      print('Error checking stored device: $e');
    }

    setState(() {
      _isCheckingStoredDevice = false;
    });
  }

  Future<void> _saveDevice(String ip, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceData = json.encode({
        'ip': ip,
        'name': name,
        'savedAt': DateTime.now().toIso8601String(),
      });
      await prefs.setString('stored_device', deviceData);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device "$name" saved successfully!'),
          backgroundColor: mainColor,
        ),
      );
    } catch (e) {
      print('Error saving device: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save device'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeStoredDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('stored_device');
    } catch (e) {
      print('Error removing stored device: $e');
    }
  }

  Future<String?> _getStoredDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDeviceData = prefs.getString('stored_device');
      if (storedDeviceData != null) {
        final deviceInfo = json.decode(storedDeviceData);
        return deviceInfo['name'];
      }
    } catch (e) {
      print('Error getting stored device name: $e');
    }
    return null;
  }

  Future<void> _determineBaseIp() async {
    try {
      for (NetworkInterface interface in await NetworkInterface.list()) {
        for (InternetAddress address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            final ipParts = address.address.split('.');
            if (ipParts.length == 4) {
              setState(() {
                _baseIp = "${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.";
              });
              print("Base IP: $_baseIp");
              return;
            }
          }
        }
      }
      setState(() {
        _baseIp = "192.168.1."; // Default fallback
        print("Could not determine local IP. Using default: $_baseIp");
      });
    } catch (e) {
      print("Error determining local IP: $e");
      setState(() {
        _baseIp = "192.168.1."; // Default fallback if an error occurs
      });
    }
  }

  Future<void> _scanNetwork() async {
    if (_baseIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine local network IP.')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
      _scannedCount = 0;
    });

    for (int i = 1; i <= 254; i++) {
      if (!_isScanning) break;

      setState(() {
        _currentIp = "$_baseIp$i";
        _scannedCount = i;
      });

      try {
        final response = await http
            .get(Uri.parse('http://$_currentIp/identify'))
            .timeout(const Duration(milliseconds: 500));

        if (response.statusCode == 200) {
          try {
            final deviceInfo = json.decode(response.body);
            if (deviceInfo['device'] == 'SEM') {
              setState(() {
                _discoveredDevices.add({
                  'ip': _currentIp,
                  'name': deviceInfo['name'],
                });
              });
            }
          } catch (e) {
            print('Error parsing response from $_currentIp: $e');
          }
        }
      } catch (e) {
        // Skip failed connections
        continue;
      }
    }

    setState(() {
      _isScanning = false;
      _currentIp = "";
    });
  }

  void _showDeviceOptions(String ip, String name) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Device: $name'),
          content: Text('IP: $ip\n\nWhat would you like to do?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to device without saving
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LivePage(title: name, ipAddress: ip),
                  ),
                );
              },
              child: const Text('Connect Only'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Save device and navigate
                await _saveDevice(ip, name);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LivePage(title: name, ipAddress: ip),
                  ),
                );
              },
              child: Text(
                'Save & Connect',
                style: TextStyle(color: mainColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        title: const Text(
          'Scan for SEM Devices',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_stored') {
                await _removeStoredDevice();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Stored device cleared'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            itemBuilder:
                (BuildContext context) => [
                  const PopupMenuItem<String>(
                    value: 'clear_stored',
                    child: Text('Clear Stored Device'),
                  ),
                ],
          ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<String?>(
            future: _getStoredDeviceName(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: mainColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: mainColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark, color: mainColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Saved Device: ${snapshot.data}',
                          style: TextStyle(
                            color: mainColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final storedDeviceData = prefs.getString(
                            'stored_device',
                          );
                          if (storedDeviceData != null) {
                            final deviceInfo = json.decode(storedDeviceData);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => LivePage(
                                      title: deviceInfo['name'],
                                      ipAddress: deviceInfo['ip'],
                                    ),
                              ),
                            );
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: mainColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (_isCheckingStoredDevice)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Checking stored device...'),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed:
                      (_isScanning || _isCheckingStoredDevice)
                          ? null
                          : _scanNetwork,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mainColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isScanning ? 'Scanning...' : 'Start Scan'),
                ),
                if (_isScanning)
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isScanning = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Stop'),
                  ),
              ],
            ),
          ),
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _scannedCount / 254,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(mainColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scanning: $_currentIp ($_scannedCount/254)',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          if (_discoveredDevices.isEmpty &&
              !_isScanning &&
              !_isCheckingStoredDevice)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No ESP32 devices found. Click "Start Scan" to search for devices.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = _discoveredDevices[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: Icon(Icons.devices, color: mainColor),
                    title: Text(
                      device['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('IP: ${device['ip']}'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      _showDeviceOptions(device['ip'], device['name']);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
