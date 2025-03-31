import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  // NEW: Controller for Device ID
  final _deviceIdController = TextEditingController();

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _submitConfiguration() async {
    if (_formKey.currentState!.validate()) {
      final ssid = _ssidController.text;
      final password = _passwordController.text;
      final provider = Provider.of<DeviceProvider>(context, listen: false);

      // Show loading or disable button if desired
      final success = await provider.configureAndAddDevice(ssid, password);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Device configured successfully! ESP32 restarting...',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            // Go to Home tab (assuming your DefaultTabController is set up)
            DefaultTabController.of(context).animateTo(0);
          }
        });
      } else if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Configuration failed: ${provider.errorMessage ?? "Unknown error"}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // NEW: Method to add a device by ID only, with validation
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

    final provider = Provider.of<DeviceProvider>(context, listen: false);

    try {
      // 1) Check if device exists in Firebase
      final exists = await provider.checkDeviceExists(deviceId);

      if (!exists) {
        // Device not found
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This device does not exist.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 2) If device does exist, proceed to add it
      final success = await provider.addDeviceById(deviceId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device added successfully by ID!'),
            backgroundColor: Colors.green,
          ),
        );
        // Optionally navigate or do other logic here
      } else if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to add device by ID: '
              '${provider.errorMessage ?? "Unknown error"}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // 3) If checkDeviceExists threw an error, interpret it as "no server connection"
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('There is no connection with the server.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Add New Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Card(
                color: Colors.amberAccent,
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'IMPORTANT:\n1. Connect your phone to the WiFi network named "device setup".\n'
                    '2. Then, enter your HOME WiFi credentials below.',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'Home WiFi Network Name (SSID)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the SSID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Home WiFi Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),

              if (deviceProvider.errorMessage != null &&
                  !deviceProvider.isLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Text(
                    'Error: ${deviceProvider.errorMessage}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),

              deviceProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save & Configure Device'),
                    onPressed: _submitConfiguration,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),

              const SizedBox(height: 40),

              // Divider with "OR" in the center
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 40),

              // A simple text field to accept the Device ID
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
