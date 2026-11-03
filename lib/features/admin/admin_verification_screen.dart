import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';

class AdminDriverApprovalsWidget extends StatefulWidget {
  const AdminDriverApprovalsWidget({super.key});

  @override
  State<AdminDriverApprovalsWidget> createState() => _AdminDriverApprovalsWidgetState();
}

class _AdminDriverApprovalsWidgetState extends State<AdminDriverApprovalsWidget> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingDrivers = [];

  @override
  void initState() {
    super.initState();
    _fetchPendingDrivers();
  }

  Future<void> _fetchPendingDrivers() async {
    setState(() => _isLoading = true);
    try {
      // Fetch registrations where approval status is pending
      final response = await _supabase
          .from('driver_registrations')
          .select()
          .eq('approval_status', 'pending')
          .order('created_at', ascending: false);

      setState(() {
        _pendingDrivers = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching pending drivers: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _approveDriver(Map<String, dynamic> regData) async {
    try {
      // 1. Insert into the active 'drivers' table so they can log in
      await _supabase.from('drivers').insert({
        'full_name': regData['full_name'],
        'phone_number': regData['phone_number'],
        'password': regData['password'] ?? '123456', // Default fallback password if empty
        'license_number': regData['license_number'],
        'vehicle_number': regData['car_number'],
        'vehicle_model': regData['car_name'],
        'vehicle_type': regData['car_type'] ?? 'Sedan',
        'is_on_duty': false,
      });

      // 2. Update status in 'driver_registrations'
      await _supabase
          .from('driver_registrations')
          .update({'approval_status': 'approved'})
          .eq('id', regData['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Driver ${regData['full_name']} approved successfully!'), backgroundColor: Colors.green),
      );
      
      _fetchPendingDrivers(); // Refresh list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error approving driver: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectDriver(String id) async {
    try {
      await _supabase
          .from('driver_registrations')
          .update({'approval_status': 'rejected'})
          .eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver application rejected.'), backgroundColor: Colors.orange),
      );
      _fetchPendingDrivers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error rejecting driver: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showDocumentDialog(String title, String? imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: imageUrl == null || imageUrl.isEmpty
            ? const Text('No document image uploaded.')
            : Image.network(
                imageUrl,
                errorBuilder: (context, error, stackTrace) => const Text('Could not load image.'),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    if (_pendingDrivers.isEmpty) {
      return const Center(
        child: Text(
          'No pending driver approvals found.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingDrivers.length,
      itemBuilder: (context, index) {
        final driver = _pendingDrivers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    driver['full_name'] ?? 'Unknown Driver',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Text(
                      '⏳ Pending Approval',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Phone: ${driver['phone_number']} • WhatsApp: ${driver['whatsapp_number'] ?? 'N/A'}\nEmail: ${driver['email'] ?? 'N/A'}\nLicense: ${driver['license_number']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Vehicle: ${driver['car_name']} (${driver['car_number']}) • ${driver['car_type']} • ${driver['car_category']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
              ),
              const Divider(height: 20),
              
              // Document links row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Aadhaar', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showDocumentDialog('Aadhaar Card', driver['aadhaar_card_url']),
                  ),
                  ActionChip(
                    label: const Text('License', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showDocumentDialog('Driving License', driver['driving_license_url']),
                  ),
                  ActionChip(
                    label: const Text('Car RC', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showDocumentDialog('Car RC', driver['car_rc_url']),
                  ),
                  ActionChip(
                    label: const Text('Car Photo', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showDocumentDialog('Car Photo', driver['car_photo_url']),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Approve / Reject actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _rejectDriver(driver['id']),
                    child: const Text('Reject', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _approveDriver(driver),
                    child: const Text('Approve Driver', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}