//esp32_service.dart
import 'dart:async';
import 'dart:convert'; // For utf8 decoding
import 'package:http/http.dart' as http;

// Service for communicating with the ESP32 over HTTP
class Esp32Service {
  final String _espBaseUrl = "http://192.168.4.1"; // ESP32 SoftAP IP

  // Gets the unique ID from the ESP32
  Future<String> getDeviceId() async {
    final url = Uri.parse('$_espBaseUrl/id');
    try {
      // Set a reasonable timeout
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // ESP32 sends ID as plain text
        return utf8.decode(response.bodyBytes).trim(); // Use utf8 decoding
      } else {
        throw Exception(
          'Failed to get Device ID: Status code ${response.statusCode}',
        );
      }
    } on TimeoutException {
      throw Exception(
        'Failed to get Device ID: Connection timed out. Is the ESP32 reachable at $_espBaseUrl?',
      );
    } catch (e) {
      print("Error getting Device ID: $e");
      // Re-throw a more user-friendly or specific exception if needed
      throw Exception(
        'Failed to get Device ID: ${e.toString()}. Ensure you are connected to the "device setup" WiFi.',
      );
    }
  }

  // Sends WiFi credentials to the ESP32
  Future<bool> sendCredentials(String ssid, String password) async {
    final url = Uri.parse('$_espBaseUrl/connect');
    try {
      // ESP32 expects form-urlencoded data for ssid and password arguments
      final response = await http
          .post(
            url,
            headers: {
              // Standard header for form data
              "Content-Type": "application/x-www-form-urlencoded",
            },
            // Encode arguments like a form submission
            body: {'ssid': ssid, 'password': password},
          )
          .timeout(
            const Duration(seconds: 15),
          ); // Longer timeout for save/restart

      if (response.statusCode == 200) {
        print(
          "Credentials sent successfully. ESP32 response: ${response.body}",
        );
        // ESP32 should respond with success message and restart
        return true;
      } else {
        print(
          "Failed to send credentials: Status ${response.statusCode}, Body: ${response.body}",
        );
        throw Exception(
          'Failed to send credentials: Status code ${response.statusCode}',
        );
      }
    } on TimeoutException {
      throw Exception(
        'Failed to send credentials: Connection timed out. Is the ESP32 reachable at $_espBaseUrl?',
      );
    } catch (e) {
      print("Error sending credentials: $e");
      throw Exception(
        'Failed to send credentials: ${e.toString()}. Ensure you are connected to the "device setup" WiFi.',
      );
    }
  }
}
