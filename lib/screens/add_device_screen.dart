// screens/add_device_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device.dart';
import '../services/storage_service.dart';
import '../services/esp32_service.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceIdController = TextEditingController();

  final StorageService _storageService = StorageService();
  final Esp32Service _esp32Service = Esp32Service();
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _submitConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    try {
      // 1. Ask ESP32 for its generated device ID
      final deviceId = await _esp32Service.getDeviceId();
      if (deviceId.isEmpty) throw Exception("Empty Device ID from ESP32.");

      // 2. Send home-WiFi credentials to ESP32
      final sent = await _esp32Service.sendCredentials(ssid, password);
      if (!sent) throw Exception("ESP32 did not accept credentials.");

      // 3. Load existing devices from local storage
      final existingDevices = await _storageService.loadDevices();
      final alreadyAdded = existingDevices.any((d) => d.id == deviceId);

      if (!alreadyAdded) {
        // 4. Append new Device to local list & save
        final newDevice = Device(id: deviceId, name: null);
        existingDevices.add(newDevice);
        await _storageService.saveDevices(existingDevices);
      }
      // 5. Show success and pop
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device configured successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addDeviceById() async {
    final deviceId = _deviceIdController.text.trim();
    if (deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Device ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      // 1. Check Firebase if this device ID exists under /sensorData
      final ref = _database.ref('/sensorData/$deviceId');
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This device does not exist.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 2. Load existing devices from local storage
      final existingDevices = await _storageService.loadDevices();
      final alreadyAdded = existingDevices.any((d) => d.id == deviceId);
      if (!alreadyAdded) {
        // 3. Append new Device to local list & save
        final newDevice = Device(id: deviceId, name: null);
        existingDevices.add(newDevice);
        await _storageService.saveDevices(existingDevices);
      }

      // 4. Show success and pop
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to reach server.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                color: Colors.amberAccent,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'IMPORTANT:\n'
                    '1. Connect to the ESP32 setup network.\n'
                    '2. Then enter your home Wi-Fi credentials below.',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'Home Wi-Fi SSID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                validator:
                    (v) =>
                        v == null || v.isEmpty ? 'Please enter the SSID' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null && !_isLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Error: $_errorMessage',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save & Configure'),
                    onPressed: _submitConfiguration,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
              const SizedBox(height: 40),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 40),
              TextFormField(
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.devices_other),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _addDeviceById,
                child: const Text('Add Device by ID'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
