// home.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ESP32Data {
  final String voltage;
  final String current;
  final String power;
  final String energy;
  final String frequency;
  final String powerFactor;
  final String reserved;
  final String message;
  final String deviceId;

  ESP32Data({
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    required this.frequency,
    required this.powerFactor,
    required this.reserved,
    required this.message,
    required this.deviceId,
  });

  factory ESP32Data.fromString(String data) {
    final parts = data.split('#');
    if (parts.length >= 9) {
      return ESP32Data(
        voltage: parts[0],
        current: parts[1],
        power: parts[2],
        energy: parts[3],
        frequency: parts[4],
        powerFactor: parts[5],
        reserved: parts[6],
        message: parts[7],
        deviceId: parts[8],
      );
    }
    throw Exception('Invalid data format');
  }
}

class LivePage extends StatefulWidget {
  final String title;
  final String ipAddress;

  const LivePage({Key? key, required this.title, required this.ipAddress})
    : super(key: key);

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  Timer? _timer;
  ESP32Data? _currentData;
  bool _isConnected = false;
  String _errorMessage = '';
  int _updateCount = 0;
  final mainColor = const Color(0xFF075E54);

  @override
  void initState() {
    super.initState();
    _startDataFetching();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startDataFetching() {
    _timer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      _fetchData();
    });
  }

  void _stopDataFetching() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchData() async {
    try {
      final response = await http
          .get(Uri.parse('http://${widget.ipAddress}/state'))
          .timeout(const Duration(milliseconds: 1000));

      if (response.statusCode == 200) {
        setState(() {
          _currentData = ESP32Data.fromString(response.body);
          _isConnected = true;
          _errorMessage = '';
          _updateCount++;
        });
      } else {
        setState(() {
          _isConnected = false;
          _errorMessage = 'HTTP Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _errorMessage = 'Connection Error: ${e.toString()}';
      });
    }
  }

  Widget _buildDataCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: mainColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _timer != null ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                if (_timer != null) {
                  _stopDataFetching();
                } else {
                  _startDataFetching();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isConnected ? Colors.green : Colors.red,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected
                      ? 'Connected to ${widget.ipAddress}'
                      : 'Disconnected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Update Counter
          Container(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Updates: $_updateCount | Refresh Rate: 900ms',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),

          // Error Message
          if (_errorMessage.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Data Display
          Expanded(
            child:
                _currentData != null
                    ? ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        _buildDataCard(
                          'Voltage',
                          '${_currentData!.voltage} V',
                          Icons.electrical_services,
                        ),
                        _buildDataCard(
                          'Current',
                          '${_currentData!.current} A',
                          Icons.flash_on,
                        ),
                        _buildDataCard(
                          'Power',
                          '${_currentData!.power} W',
                          Icons.power,
                        ),
                        _buildDataCard(
                          'Energy',
                          '${_currentData!.energy} kWh',
                          Icons.battery_charging_full,
                        ),
                        _buildDataCard(
                          'Frequency',
                          '${_currentData!.frequency} Hz',
                          Icons.waves,
                        ),
                        _buildDataCard(
                          'Power Factor',
                          _currentData!.powerFactor,
                          Icons.analytics,
                        ),
                        _buildDataCard(
                          'Device ID',
                          _currentData!.deviceId,
                          Icons.device_hub,
                        ),
                      ],
                    )
                    : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Waiting for data...'),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
