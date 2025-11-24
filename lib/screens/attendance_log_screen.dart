import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/attendance_provider.dart';
import '../models/attendance_model.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

class AttendanceLogScreen extends StatefulWidget {
  const AttendanceLogScreen({super.key});

  @override
  State<AttendanceLogScreen> createState() => _AttendanceLogScreenState();
}

class _AttendanceLogScreenState extends State<AttendanceLogScreen> {
  DateTime? _selectedDate;
  bool _isSyncing = false;

  void _showDatePicker() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedDate = null;
    });
  }

  Future<void> _syncRecords() async {
    setState(() => _isSyncing = true);

    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    final success = await provider.syncAllRecords();

    setState(() => _isSyncing = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Synced Successfully'
              : 'Sync failed. Please try again later.',
        ),
        backgroundColor: success ? AppTheme.accentGreen : AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<AttendanceModel> _getFilteredRecords(
      List<AttendanceModel> allRecords) {
    if (_selectedDate == null) {
      return allRecords;
    }

    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    return provider.getRecordsByDate(_selectedDate!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Log'),
        actions: [
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilter,
              tooltip: 'Clear Filter',
            ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showDatePicker,
            tooltip: 'Filter by Date',
          ),
        ],
      ),
      body: Consumer<AttendanceProvider>(
        builder: (context, provider, child) {
          final filteredRecords = _getFilteredRecords(provider.attendanceRecords);

          if (filteredRecords.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 80,
                    color: AppTheme.textGray.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedDate != null
                        ? 'No records for selected date'
                        : 'No attendance records yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.textGray,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedDate != null
                        ? 'Try selecting a different date'
                        : 'Start scanning to record attendance',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Summary Card
              if (_selectedDate != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.date_range,
                        color: AppTheme.primaryBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Filtered by Date',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.textGray,
                              ),
                            ),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(_selectedDate!),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${filteredRecords.length} records',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),

              // Records List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await provider.refresh();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredRecords.length,
                    itemBuilder: (context, index) {
                      final record = filteredRecords[index];
                      return _buildAttendanceCard(record);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<AttendanceProvider>(
        builder: (context, provider, child) {
          if (provider.unsyncedRecords.isEmpty) {
            return const SizedBox.shrink();
          }

          return FloatingActionButton.extended(
            onPressed: _isSyncing ? null : _syncRecords,
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.sync),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
            backgroundColor:
                _isSyncing ? AppTheme.textGray : AppTheme.primaryBlue,
          );
        },
      ),
    );
  }

  Widget _buildAttendanceCard(AttendanceModel record) {
    final isPresentStatus = record.status == AppConstants.statusPresent;
    final statusColor = isPresentStatus ? AppTheme.accentGreen : AppTheme.accentRed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Status Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isPresentStatus ? Icons.check_circle : Icons.cancel,
                color: statusColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        record.status,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      const Spacer(),
                      if (!record.synced)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentOrange.withOpacity(0.3),
                            ),
                          ),
                          child: const Text(
                            'Unsynced',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentOrange,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: AppTheme.textGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        record.beaconId,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: AppTheme.textGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${record.date} ${record.time}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.textGray,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.signal_cellular_alt,
                        size: 14,
                        color: AppTheme.textGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${record.rssi} dBm',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

