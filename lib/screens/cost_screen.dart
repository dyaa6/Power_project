// lib/screens/electricity_cost_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device.dart';
import '../services/storage_service.dart';

class ElectricityCostScreen extends StatefulWidget {
  const ElectricityCostScreen({super.key});

  @override
  State<ElectricityCostScreen> createState() => _ElectricityCostScreenState();
}

class _ElectricityCostScreenState extends State<ElectricityCostScreen> {
  final StorageService _storageService = StorageService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // ─── Loaded from StorageService ─────────────────────────────────────────────
  List<Device> _devices = [];
  Device? _selectedDevice;
  bool _isLoadingDevices = true;

  // ─── Months available under selected device ─────────────────────────────────
  List<String> _monthKeys = []; // each in "YYYY-MM" format
  String? _selectedMonthKey;
  bool _isLoadingMonths = false;

  // ─── After selecting a month, these will be populated ──────────────────────
  Map<int, double> _dailyConsumption = {}; // dayNumber → consumptionInKWh
  final Map<int, double> _dailyCost = {}; // dayNumber → costInIQD
  double _totalConsumption = 0;
  double _totalCost = 0;
  double _totalElectricityHours = 0; // New: total electricity hours
  String? _firstTierExceedDate; // e.g. "2025/05/20"
  bool _isLoadingMonthData = false;

  // ─── Tier constants for easy modification ──────────────────────────────────
  static const List<TierConfig> _tiers = [
    TierConfig(limit: 1500, rate: 10),
    TierConfig(limit: 3000, rate: 35),
    TierConfig(limit: 4000, rate: 80),
    TierConfig(limit: double.infinity, rate: 120),
  ];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    // Clean up resources if needed
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoadingDevices = true;
    });

    try {
      final saved = await _storageService.loadDevices();
      // Filter out any devices that have no non‐empty ID
      _devices = saved.where((d) => d.id.isNotEmpty).toList();

      if (_devices.length == 1) {
        // Auto‐select the single device and hide dropdown
        _selectedDevice = _devices.first;
        await _loadAvailableMonths();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل الأجهزة: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDevices = false;
        });
      }
    }
  }

  Future<void> _loadAvailableMonths() async {
    if (_selectedDevice == null) return;

    setState(() {
      _isLoadingMonths = true;
      _monthKeys = [];
      _selectedMonthKey = null;
      _clearMonthData();
    });

    try {
      final deviceId = _selectedDevice!.id;
      final ref = _database.ref('sensorData/$deviceId');

      final snapshot = await ref.get();
      if (!snapshot.exists) {
        setState(() {
          _isLoadingMonths = false;
        });
        return;
      }

      final months = <String>[];

      // Extract all year-month combinations
      for (final yearSnap in snapshot.children) {
        final yearKey = yearSnap.key;
        if (yearKey == null) continue;

        for (final monthSnap in yearSnap.children) {
          final monthKey = monthSnap.key;
          if (monthKey == null) continue;
          months.add('$yearKey-$monthKey');
        }
      }

      // Sort chronologically (YYYY-MM format sorts correctly lexicographically)
      months.sort(
        (a, b) => b.compareTo(a),
      ); // Descending order (most recent first)

      if (mounted) {
        setState(() {
          _monthKeys = months;
          _isLoadingMonths = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل الأشهر: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoadingMonths = false;
        });
      }
    }
  }

  void _clearMonthData() {
    _dailyConsumption.clear();
    _dailyCost.clear();
    _totalConsumption = 0;
    _totalCost = 0;
    _totalElectricityHours = 0;
    _firstTierExceedDate = null;
  }

  Future<void> _onDeviceChanged(Device? newDevice) async {
    if (newDevice == null || _selectedDevice?.id == newDevice.id) return;

    setState(() {
      _selectedDevice = newDevice;
      _monthKeys.clear();
      _selectedMonthKey = null;
      _clearMonthData();
    });

    await _loadAvailableMonths();
  }

  Future<void> _onMonthChanged(String? newMonthKey) async {
    if (newMonthKey == null || _selectedMonthKey == newMonthKey) return;

    setState(() {
      _selectedMonthKey = newMonthKey;
      _clearMonthData();
    });

    await _loadMonthDataAndCompute();
  }

  Future<void> _loadMonthDataAndCompute() async {
    if (_selectedDevice == null || _selectedMonthKey == null) return;

    setState(() {
      _isLoadingMonthData = true;
      _clearMonthData();
    });

    try {
      final deviceId = _selectedDevice!.id;
      final parts = _selectedMonthKey!.split('-');
      final year = parts[0];
      final month = parts[1];

      final monthRef = _database.ref('sensorData/$deviceId/$year/$month');
      final monthSnap = await monthRef.get();

      if (!monthSnap.exists) {
        if (mounted) {
          setState(() {
            _isLoadingMonthData = false;
          });
        }
        return;
      }

      // Process daily data
      final dailyData = <int, double>{};

      for (final daySnap in monthSnap.children) {
        final dayKey = daySnap.key;
        if (dayKey == null) continue;

        final dayNum = int.tryParse(dayKey);
        if (dayNum == null) continue;

        final consumption = _calculateDayConsumption(daySnap);
        dailyData[dayNum] = consumption;
      }

      // Calculate electricity hours for the entire month
      _totalElectricityHours = await _calculateMonthElectricityHours(monthSnap);

      // Calculate costs and totals
      _calculateCostsAndTotals(dailyData, year, month);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل بيانات الشهر: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMonthData = false;
        });
      }
    }
  }

  // New method to calculate electricity hours for the entire month
  Future<double> _calculateMonthElectricityHours(DataSnapshot monthSnap) async {
    double totalHours = 0;
    int totalReadings = 0;
    int validTimestamps = 0;

    for (final daySnap in monthSnap.children) {
      final dayKey = daySnap.key;
      if (dayKey == null) continue;

      // Method 1: Try to get timestamps and calculate based on gaps
      final timestamps = <DateTime>[];
      final recordKeys = <String>[];

      for (final record in daySnap.children) {
        totalReadings++;
        final recordKey = record.key;
        if (recordKey != null) {
          recordKeys.add(recordKey);
        }

        // Try different timestamp field names
        dynamic timestampValue =
            record.child('timestamp').value ??
            record.child('time').value ??
            record.child('ts').value ??
            record.child('datetime').value;

        if (timestampValue != null) {
          final timestamp = _parseTimestamp(timestampValue);
          if (timestamp != null) {
            timestamps.add(timestamp);
            validTimestamps++;
          }
        }
      }

      // Method 1: If we have valid timestamps, use time-based calculation
      if (timestamps.length >= 2) {
        timestamps.sort();

        for (int i = 1; i < timestamps.length; i++) {
          final timeDiff =
              timestamps[i].difference(timestamps[i - 1]).inMinutes;

          // If difference is 5 minutes or less, electricity was available
          if (timeDiff <= 5 && timeDiff > 0) {
            totalHours += timeDiff / 60.0;
          }
        }
      }
      // Method 2: If no timestamps, estimate based on reading frequency
      else if (recordKeys.isNotEmpty) {
        // Try to parse timestamps from record keys (if they contain time info)
        final keyTimestamps = <DateTime>[];

        for (final key in recordKeys) {
          // Check if key looks like a timestamp
          final timestamp = _parseTimestampFromKey(key);
          if (timestamp != null) {
            keyTimestamps.add(timestamp);
          }
        }

        if (keyTimestamps.length >= 2) {
          keyTimestamps.sort();

          for (int i = 1; i < keyTimestamps.length; i++) {
            final timeDiff =
                keyTimestamps[i].difference(keyTimestamps[i - 1]).inMinutes;

            if (timeDiff <= 5 && timeDiff > 0) {
              totalHours += timeDiff / 60.0;
            }
          }
        }
        // Method 3: Fallback - assume regular intervals
        else {
          // If we have readings but no timestamps, estimate
          // Assume readings every 5 minutes when electricity is available
          final estimatedHours = (recordKeys.length * 5) / 60.0;
          totalHours += estimatedHours;
        }
      }
    }

    // Debug information
    print('Total readings: $totalReadings');
    print('Valid timestamps: $validTimestamps');
    print('Calculated hours: $totalHours');

    // If we still have zero hours but have readings, use alternative method
    if (totalHours == 0 && totalReadings > 0) {
      // Alternative: Calculate based on total readings
      // Assume each reading represents 5 minutes of electricity
      totalHours = (totalReadings * 5) / 60.0;
      print('Using fallback calculation: $totalHours hours');
    }

    return totalHours;
  }

  // Helper method to parse timestamp from record keys
  DateTime? _parseTimestampFromKey(String key) {
    try {
      // Try to parse if key is a timestamp
      final timestamp = int.tryParse(key);
      if (timestamp != null) {
        if (timestamp > 1000000000000) {
          // Milliseconds
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        } else if (timestamp > 1000000000) {
          // Seconds
          return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        }
      }

      // Try to parse as date string
      return DateTime.tryParse(key);
    } catch (e) {
      return null;
    }
  }

  // Helper method to parse timestamp from various formats
  DateTime? _parseTimestamp(dynamic timestampValue) {
    try {
      if (timestampValue is int) {
        // Unix timestamp (seconds or milliseconds)
        if (timestampValue > 1000000000000) {
          // Milliseconds
          return DateTime.fromMillisecondsSinceEpoch(timestampValue);
        } else if (timestampValue > 1000000000) {
          // Seconds
          return DateTime.fromMillisecondsSinceEpoch(timestampValue * 1000);
        }
      } else if (timestampValue is double) {
        final intValue = timestampValue.toInt();
        if (intValue > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(intValue);
        } else if (intValue > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(intValue * 1000);
        }
      } else if (timestampValue is String) {
        // Try parsing as number first
        final numValue = int.tryParse(timestampValue);
        if (numValue != null) {
          if (numValue > 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(numValue);
          } else if (numValue > 1000000000) {
            return DateTime.fromMillisecondsSinceEpoch(numValue * 1000);
          }
        }

        // Try parsing as ISO string or other date formats
        return DateTime.tryParse(timestampValue);
      }
    } catch (e) {
      // Handle parsing errors gracefully
      print('Error parsing timestamp: $timestampValue, Error: $e');
    }
    return null;
  }

  double _calculateDayConsumption(DataSnapshot daySnap) {
    double minEnergy = double.infinity;
    double maxEnergy = double.negativeInfinity;

    for (final record in daySnap.children) {
      final energyValue = record.child('energy').value;
      if (energyValue == null) continue;

      final energy = _parseDouble(energyValue);
      if (energy < minEnergy) minEnergy = energy;
      if (energy > maxEnergy) maxEnergy = energy;
    }

    if (minEnergy == double.infinity || maxEnergy == double.negativeInfinity) {
      return 0.0;
    }

    return (maxEnergy - minEnergy).abs();
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  void _calculateCostsAndTotals(
    Map<int, double> dailyData,
    String year,
    String month,
  ) {
    _dailyConsumption = Map.from(dailyData);

    // Calculate daily costs
    for (final entry in dailyData.entries) {
      _dailyCost[entry.key] = _calculateTieredCost(entry.value);
    }

    // Calculate monthly totals
    _totalConsumption = dailyData.values.fold(
      0.0,
      (sum, consumption) => sum + consumption,
    );
    _totalCost = _calculateTieredCost(_totalConsumption);

    // Find first tier exceed date
    _findFirstTierExceedDate(dailyData, year, month);
  }

  void _findFirstTierExceedDate(
    Map<int, double> dailyData,
    String year,
    String month,
  ) {
    final sortedDays = dailyData.keys.toList()..sort();
    double runningTotal = 0;

    for (final day in sortedDays) {
      runningTotal += dailyData[day]!;
      if (runningTotal > 1500) {
        final dayStr = day.toString().padLeft(2, '0');
        _firstTierExceedDate = '$year/$month/$dayStr';
        break;
      }
    }
  }

  /// Optimized tiered cost calculation using configuration
  double _calculateTieredCost(double units) {
    double cost = 0;
    double remainingUnits = units;
    double previousLimit = 0;

    for (final tier in _tiers) {
      final tierCapacity = tier.limit - previousLimit;
      final unitsInThisTier =
          remainingUnits > tierCapacity ? tierCapacity : remainingUnits;

      cost += unitsInThisTier * tier.rate;
      remainingUnits -= unitsInThisTier;

      if (remainingUnits <= 0) break;
      previousLimit = tier.limit;
    }

    return cost;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تكلفة الكهرباء'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child:
            _isLoadingDevices
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                  onRefresh: _loadDevices,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDeviceSelector(),
                        const SizedBox(height: 16),
                        _buildMonthSelector(),
                        const SizedBox(height: 24),
                        if (_selectedMonthKey != null) ...[
                          if (_isLoadingMonthData)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else ...[
                            _buildSummaryCard(),
                            const SizedBox(height: 16),
                            _buildDailyDataTable(),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildDeviceSelector() {
    if (_devices.length <= 1) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'اختر الجهاز',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Device>(
              value: _selectedDevice,
              hint: const Text('اختر جهازًا'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items:
                  _devices.map((device) {
                    return DropdownMenuItem<Device>(
                      value: device,
                      child: Text(
                        device.name.isNotEmpty == true
                            ? device.name
                            : device.id,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
              onChanged: _onDeviceChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    if (_isLoadingMonths) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_monthKeys.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'لا توجد بيانات للجهاز المحدد',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'اختر الشهر',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedMonthKey,
              hint: const Text('اختر شهراً'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items:
                  _monthKeys.map((monthKey) {
                    final parts = monthKey.split('-');
                    final year = parts[0];
                    final month = parts[1];
                    final display = '$month/$year';

                    return DropdownMenuItem<String>(
                      value: monthKey,
                      child: Text(display),
                    );
                  }).toList(),
              onChanged: _onMonthChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildPeriodRow(),
              const Divider(height: 24),
              _buildSummaryRow(
                'الاستهلاك الكلي',
                '${_totalConsumption.toStringAsFixed(2)} kWh',
                Icons.flash_on,
                Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildSummaryRow(
                'الكلفة الكلية',
                '${_totalCost.toStringAsFixed(0)} IQD',
                Icons.monetization_on,
                Colors.green,
              ),
              const SizedBox(height: 12),
              _buildSummaryRow(
                'عدد ساعات تجهيز الكهرباء',
                '${_totalElectricityHours.toStringAsFixed(1)} ساعة',
                Icons.electrical_services,
                Colors.blue,
              ),
              if (_firstTierExceedDate != null) ...[
                const SizedBox(height: 12),
                _buildSummaryRow(
                  'تجاوز حد 1500 وحدة في',
                  _firstTierExceedDate!,
                  Icons.warning,
                  Colors.red,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.left,
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _buildPeriodRow() {
    final parts = _selectedMonthKey!.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final monthStr = parts[1];

    final lastDay = DateTime(year, month + 1, 0).day;
    final from = '${parts[0]}/$monthStr/01';
    final to = '${parts[0]}/$monthStr/${lastDay.toString().padLeft(2, '0')}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.calendar_today, color: Colors.blue.shade600, size: 20),
        const SizedBox(width: 8),
        Text(
          'الفترة: $from – $to',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _buildDailyDataTable() {
    if (_dailyConsumption.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'لا توجد بيانات يومية للشهر المحدد',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'البيانات اليومية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20, // Reduced from default (56)
                headingRowColor: WidgetStateProperty.resolveWith(
                  (states) => Colors.grey.shade100,
                ),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                dataTextStyle: const TextStyle(fontSize: 14),
                columns: const [
                  DataColumn(
                    label: Text('اليوم', textAlign: TextAlign.center),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('الاستهلاك (kWh)', textAlign: TextAlign.center),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('التكلفة (IQD)', textAlign: TextAlign.center),
                    numeric: true,
                  ),
                ],
                rows: _buildDailyRows(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DataRow> _buildDailyRows() {
    final sortedDays = _dailyConsumption.keys.toList()..sort();

    return sortedDays.map((day) {
      final consumption = _dailyConsumption[day] ?? 0.0;
      final cost = _dailyCost[day] ?? 0.0;

      return DataRow(
        cells: [
          DataCell(Center(child: Text(day.toString().padLeft(2, '0')))),
          DataCell(Center(child: Text(consumption.toStringAsFixed(2)))),
          DataCell(Center(child: Text(cost.toStringAsFixed(0)))),
        ],
      );
    }).toList();
  }
}

// Helper class for tier configuration
class TierConfig {
  final double limit;
  final double rate;

  const TierConfig({required this.limit, required this.rate});
}
