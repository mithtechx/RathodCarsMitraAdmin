import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_saver/file_saver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class _AppColors {
  static const Color primaryOrange = Color(0xFFFF6600);
  static const Color bgCream = Color(0xFFF9F6F0);
  static const Color textMuted = Color(0xFF757575);
  static const Color textDark = Color(0xFF212121);
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  bool _isLoading = false;

  List<Map<String, dynamic>> _pendingDrivers = [];
  List<Map<String, dynamic>> _approvedDriversList = [];
  List<Map<String, dynamic>> _approvedDriverRegistrations = [];
  List<Map<String, dynamic>> _rejectedDriversList = [];
  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _routePrices = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAllAdminData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------
  // FETCH ADMIN DATA
  // ---------------------------------------------------------

  Future<void> _fetchAllAdminData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final pendingRes = await _supabase
          .from('driver_registrations')
          .select()
          .eq('approval_status', 'pending')
          .order('created_at', ascending: false);

      final rejectedRes = await _supabase
          .from('driver_registrations')
          .select()
          .eq('approval_status', 'rejected')
          .order('created_at', ascending: false);

      final approvedRes = await _supabase
          .from('drivers')
          .select()
          .order('full_name', ascending: true);

      // Fetch original approved registration records.
      final approvedRegistrationsRes = await _supabase
          .from('driver_registrations')
          .select()
          .eq('approval_status', 'approved');

      final bookingsRes = await _supabase
          .from('bookings')
          .select()
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> routesRes = [];

      try {
        final res = await _supabase
            .from('route_prices')
            .select()
            .order('from_city', ascending: true);

        routesRes = List<Map<String, dynamic>>.from(res);
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _pendingDrivers = List<Map<String, dynamic>>.from(pendingRes);
        _rejectedDriversList = List<Map<String, dynamic>>.from(rejectedRes);
        _approvedDriversList = List<Map<String, dynamic>>.from(approvedRes);

        _approvedDriverRegistrations =
            List<Map<String, dynamic>>.from(approvedRegistrationsRes);

        _allBookings = List<Map<String, dynamic>>.from(bookingsRes);
        _routePrices = routesRes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching admin data: $e');

      if (!mounted) return;

      setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------
  // DOCUMENT DOWNLOAD (WEB + MOBILE)
  // ---------------------------------------------------------

  Future<void> _downloadDocument(String title, String imageUrl) async {
    try {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception('Invalid document URL.');
      }

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Could not download document (HTTP ${response.statusCode}).');
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final path = uri.path.toLowerCase();
      String extension = 'jpg';
      if (contentType.contains('png') || path.endsWith('.png')) {
        extension = 'png';
      } else if (contentType.contains('pdf') || path.endsWith('.pdf')) {
        extension = 'pdf';
      } else if (contentType.contains('webp') || path.endsWith('.webp')) {
        extension = 'webp';
      } else if (contentType.contains('jpeg') || path.endsWith('.jpeg') ||
          path.endsWith('.jpg')) {
        extension = 'jpg';
      }

      final safeTitle = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      await FileSaver.instance.saveFile(
  name: '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}',
  bytes: Uint8List.fromList(response.bodyBytes),
  fileExtension: extension,
  mimeType: MimeType.other,
);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title downloaded successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Opens WhatsApp with a pre-filled driver status message.
  // The admin must press Send inside WhatsApp.
  Future<void> _sendDriverStatusWhatsApp({
    required Map<String, dynamic> driver,
    required bool approved,
  }) async {
    String phone = (driver['whatsapp_number'] ??
            driver['phone_number'] ??
            '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');

    if (phone.length == 10) {
      phone = '91$phone';
    }

    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver WhatsApp number is not available.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final name = driver['full_name']?.toString().trim();
    final greetingName = (name == null || name.isEmpty) ? 'Driver' : name;
    final message = approved
        ? '''Hello $greetingName,

Your driver registration for Rathod Cars Mitra (RCM) has been approved.

Welcome to RCM! You can now proceed with the next steps and start receiving eligible trip assignments. Please keep your documents and vehicle details up to date.

Thank you,
Rathod Cars Mitra Team'''
        : '''Hello $greetingName,

Thank you for submitting your registration to Rathod Cars Mitra (RCM).

Unfortunately, we could not approve your application because some of the submitted documents or information are incomplete or insufficient. Please review the details, correct or replace the required documents/information, and submit your application again for review.

Thank you,
Rathod Cars Mitra Team''';

    final whatsappUri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    try {
      final launched = await launchUrl(
        whatsappUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open WhatsApp. Please check the number or app.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open WhatsApp: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // APPROVED DRIVER DETAILS
  // ---------------------------------------------------------

  Map<String, dynamic>? _getDriverRegistration(
      Map<String, dynamic> driver) {
    final phone = driver['phone_number']?.toString();

    for (final registration in _approvedDriverRegistrations) {
      if (registration['phone_number']?.toString() == phone) {
        return registration;
      }
    }

    return null;
  }

  void _showApprovedDriverDetails(Map<String, dynamic> driver) {
    final registration = _getDriverRegistration(driver);

    if (registration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration details not found for this driver.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final details = <String, String>{
      'Full Name': 'full_name',
      'Phone Number': 'phone_number',
      'WhatsApp Number': 'whatsapp_number',
      'Email': 'email',
      'License Number': 'license_number',
      'Vehicle Name': 'car_name',
      'Vehicle Number': 'car_number',
      'Vehicle Type': 'car_type',
      'Vehicle Category': 'car_category',
    };

    final documents = <String, String>{
      'Aadhaar Card': 'aadhaar_card_url',
      'Driving License': 'driving_license_url',
      'Car RC': 'car_rc_url',
      'Car Photo': 'car_photo_url',
    };

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.green,
                        child: Icon(
                          Icons.verified,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Driver Details',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'Personal & Vehicle Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  ...details.entries.map((entry) {
                    final value = registration[entry.value];

                    if (value == null ||
                        value.toString().trim().isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 16),
                  const Divider(),

                  const Text(
                    'Uploaded Documents & Images',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  ...documents.entries.map((document) {
                    final url =
                        registration[document.value]?.toString();

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            document.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),

                          const SizedBox(height: 10),

                          if (url == null || url.isEmpty)
                            const Text(
                              'No document uploaded.',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.contain,
                                loadingBuilder:
                                    (context, child, progress) {
                                  if (progress == null) return child;

                                  return const SizedBox(
                                    height: 200,
                                    child: Center(
                                      child:
                                          CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder:
                                    (context, error, stackTrace) {
                                  return const SizedBox(
                                    height: 120,
                                    child: Center(
                                      child: Text(
                                        'Unable to load document.\n'
                                        'Check its storage URL or access permissions.',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (url != null && url.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _downloadDocument(document.key, url),
                                icon: const Icon(Icons.download),
                                label: const Text('Download Document'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close Details'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------
  // DRIVER APPROVAL
  // ---------------------------------------------------------

  Future<void> _approveDriver(Map<String, dynamic> regData) async {
    try {
      await _supabase.from('drivers').upsert({
        'full_name': regData['full_name'],
        'phone_number': regData['phone_number'],
        'license_number': regData['license_number'],
        'vehicle_number': regData['car_number'],
        'vehicle_model': regData['car_name'],
        'vehicle_type': regData['car_type'] ?? 'Sedan',
        'is_on_duty': false,
      }, onConflict: 'phone_number');

      await _supabase
          .from('driver_registrations')
          .update({'approval_status': 'approved'})
          .eq('id', regData['id']);

      if (!mounted) return;

      await _sendDriverStatusWhatsApp(driver: regData, approved: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Driver ${regData['full_name']} approved successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );

      _fetchAllAdminData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approval Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectDriver(String id) async {
    try {
      final registration = _pendingDrivers.firstWhere(
        (driver) => driver['id'].toString() == id,
        orElse: () => <String, dynamic>{},
      );

      await _supabase
          .from('driver_registrations')
          .update({'approval_status': 'rejected'})
          .eq('id', id);

      if (registration.isNotEmpty) {
        await _sendDriverStatusWhatsApp(
          driver: registration,
          approved: false,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver application rejected.'),
          backgroundColor: Colors.orange,
        ),
      );

      _fetchAllAdminData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejection Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteActiveDriver(
      String driverId, String driverName) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Fleet Driver'),
        content: Text(
          'Are you sure you want to remove $driverName from active drivers?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(ctx);

              try {
                await _supabase
                    .from('drivers')
                    .delete()
                    .eq('id', driverId);

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Driver removed from fleet.'),
                    backgroundColor: Colors.green,
                  ),
                );

                _fetchAllAdminData();
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error removing driver: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showDocumentDialog(String title, String? imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: imageUrl == null || imageUrl.isEmpty
            ? const Text('No document image available.')
            : SizedBox(
                width: 520,
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (_, __, ___) =>
                        const SizedBox(
                          height: 120,
                          child: Center(child: Text('Failed to load image.')),
                        ),
                  ),
                ),
              ),
        actions: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () => _downloadDocument(title, imageUrl),
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // WHATSAPP MESSAGES
  // ---------------------------------------------------------

  // 1. Payment Verification WhatsApp Message
  Future<void> _sendPaymentVerifiedWhatsApp(
      Map<String, dynamic> booking) async {
    final passengerName =
        booking['passenger_name'] ?? 'Valued Passenger';
    final phoneRaw = booking['passenger_phone'] ?? '';

    String cleanPhone =
        phoneRaw.toString().replaceAll(RegExp(r'\D'), '');

    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final pnr = booking['pnr_number'] ?? 'RC-2026-BOOKING';
    final fromCity = booking['from_location'] ?? 'Buldhana';
    final toCity = booking['to_location'] ?? 'Pune';
    final travelDate = booking['travel_date'] ?? 'N/A';
    final utrNumber =
        booking['utr_number'] ?? booking['payment_utr'] ?? 'N/A';
    final advancePaid = booking['advance_amount'] ?? '300';

    final message = '''🌟 RATHOD CARS MITRA (RCM) - PAYMENT VERIFIED & RIDE CONFIRMED 🌟

Namaste $passengerName ji! 🙏
We are delighted to inform you that your advance payment (UTR: $utrNumber, Amount: ₹$advancePaid) has been successfully verified and approved by our finance team!

🟢 STATUS: PAYMENT VERIFIED & RIDE CONFIRMED

📋 BOOKING DETAILS:
• PNR / Booking Ref: $pnr
• Route: $fromCity ➔ $toCity
• Travel Date: $travelDate

🚗 WHAT'S NEXT?
Your booking is now confirmed! Our operations team is currently assigning a verified professional driver and vehicle for your journey. You will receive another update with complete driver and vehicle details shortly.

For any queries, contact our 24/7 central support at +91 8261039902. Thank you for choosing Rathod Cars Mitra! ✨''';

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = Uri.parse(
      'https://wa.me/$cleanPhone?text=$encodedMessage',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint(
        'Error launching payment verification WhatsApp: $e',
      );
    }
  }

  // 2. Driver Assigned WhatsApp Message
  Future<void> _sendDriverAssignedToPassengerWhatsApp(
    Map<String, dynamic> booking,
    Map<String, dynamic> driver,
  ) async {
    final passengerName =
        booking['passenger_name'] ?? 'Valued Passenger';
    final phoneRaw = booking['passenger_phone'] ?? '';

    String cleanPhone =
        phoneRaw.toString().replaceAll(RegExp(r'\D'), '');

    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final pnr = booking['pnr_number'] ?? 'RC-2026-BOOKING';
    final fromCity = booking['from_location'] ?? 'Buldhana';
    final toCity = booking['to_location'] ?? 'Pune';
    final travelDate = booking['travel_date'] ?? 'N/A';
    final departureTime = booking['time_slot'] ?? '09:00 AM';

    final List seatsList = booking['selected_seats'] ?? [];
    final seats = seatsList.isNotEmpty
        ? seatsList.join(', ')
        : (booking['seat_number'] ?? '1A');

    final driverName = driver['full_name'] ?? 'Assigned Driver';
    final driverPhone = driver['phone_number'] ?? 'N/A';
    final vehicleModel =
        driver['vehicle_model'] ?? driver['vehicle_type'] ?? 'Sedan';
    final vehicleNumber = driver['vehicle_number'] ?? 'N/A';

    final totalFare = booking['total_fare'] ?? '0';
    final advancePaid = booking['advance_amount'] ?? '300';

    final totalNum =
        double.tryParse(totalFare.toString()) ?? 0.0;
    final advanceNum =
        double.tryParse(advancePaid.toString()) ?? 300.0;

    final balanceDue = (totalNum > 0)
        ? (totalNum - advanceNum).toStringAsFixed(0)
        : '300';

    final message = '''🚗 RATHOD CARS MITRA (RCM) - DRIVER ALLOCATED FOR YOUR JOURNEY 🚗

Namaste $passengerName ji! 🙏
A dedicated professional driver and vehicle have been successfully assigned to your confirmed booking!

📋 YOUR TRIP SUMMARY:
• PNR / Booking Ref: $pnr
• Route: $fromCity ➔ $toCity
• Travel Date & Time: $travelDate at $departureTime
• Seat Number(s): $seats

🚘 ASSIGNED DRIVER & VEHICLE DETAILS:
• Driver Name: $driverName
• Driver Mobile Number: $driverPhone
• Vehicle Model: $vehicleModel
• Vehicle Number: $vehicleNumber

💵 FARE & BALANCE STRUCTURE:
• Total Trip Fare: ₹$totalFare
• Advance Paid Online: ₹$advancePaid
• Balance Due to Driver: ₹$balanceDue (payable in cash/UPI upon boarding)

📌 GUIDELINES:
1. Your driver will call you prior to departure to coordinate pickup.
2. Please be ready 10-15 minutes before departure.

Support: +91 8261039902. Have a safe journey with Rathod Cars Mitra! 🌟''';

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = Uri.parse(
      'https://wa.me/$cleanPhone?text=$encodedMessage',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('Error launching passenger WhatsApp: $e');
    }
  }

  // 3. Trip Sheet WhatsApp Message
  Future<void> _sendTripDetailsToDriverWhatsApp(
    Map<String, dynamic> booking,
    Map<String, dynamic> driver,
  ) async {
    final driverPhoneRaw = driver['phone_number'] ?? '';

    String cleanDriverPhone =
        driverPhoneRaw.toString().replaceAll(RegExp(r'\D'), '');

    if (cleanDriverPhone.length == 10) {
      cleanDriverPhone = '91$cleanDriverPhone';
    }

    final driverName = driver['full_name'] ?? 'Driver';
    final pnr = booking['pnr_number'] ?? 'RC-2026-BOOKING';
    final fromCity = booking['from_location'] ?? 'Buldhana';
    final toCity = booking['to_location'] ?? 'Pune';
    final travelDate = booking['travel_date'] ?? 'N/A';
    final departureTime = booking['time_slot'] ?? '09:00 AM';

    final List seatsList = booking['selected_seats'] ?? [];
    final seats = seatsList.isNotEmpty
        ? seatsList.join(', ')
        : (booking['seat_number'] ?? '1A');

    final passengerName = booking['passenger_name'] ?? 'Passenger';
    final passengerPhone = booking['passenger_phone'] ?? 'N/A';

    final totalFare = booking['total_fare'] ?? '0';
    final advancePaid = booking['advance_amount'] ?? '300';

    final totalNum =
        double.tryParse(totalFare.toString()) ?? 0.0;
    final advanceNum =
        double.tryParse(advancePaid.toString()) ?? 300.0;

    final balanceDue = (totalNum > 0)
        ? (totalNum - advanceNum).toStringAsFixed(0)
        : '300';

    final message = '''🚗 RATHOD CARS MITRA (RCM) - NEW TRIP ASSIGNED TO YOU 🚗

Namaste $driverName ji! 🙏
A verified booking has been assigned to your vehicle. Review your trip sheet below:

📋 TRIP & ROUTE DETAILS:
• PNR / Booking Ref: $pnr
• Route: $fromCity ➔ $toCity
• Travel Date & Time: $travelDate at $departureTime
• Seat(s) Booked: $seats

👤 PASSENGER CONTACT:
• Passenger Name: $passengerName
• Passenger Mobile: $passengerPhone

💵 COLLECTION DETAILS:
• Balance to Collect from Passenger: ₹$balanceDue (cash/UPI upon boarding)

Support: +91 8261039902''';

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = Uri.parse(
      'https://wa.me/$cleanDriverPhone?text=$encodedMessage',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('Error launching driver WhatsApp: $e');
    }
  }

  // ---------------------------------------------------------
  // PAYMENT VERIFICATION
  // ---------------------------------------------------------

  Future<void> _verifyPayment(
      Map<String, dynamic> booking) async {
    try {
      final bookingId = booking['id'].toString();

      await _supabase.from('bookings').update({
        'payment_status': 'verified',
        'booking_status': 'payment_verified',
      }).eq('id', bookingId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment verified successfully! Ride confirmed.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await _sendPaymentVerifiedWhatsApp(booking);

      _fetchAllAdminData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // DRIVER ASSIGNMENT
  // ---------------------------------------------------------

  Future<void> _assignDriverToBooking(
    Map<String, dynamic> booking,
    Map<String, dynamic> driver,
  ) async {
    try {
      final bookingId = booking['id'].toString();

      await _supabase.from('bookings').update({
        'driver_id': driver['id'],
        'driver_name': driver['full_name'],
        'driver_phone': driver['phone_number'],
        'vehicle_number': driver['vehicle_number'],
        'booking_status': 'assigned',
      }).eq('id', bookingId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Driver ${driver['full_name']} assigned successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await _sendDriverAssignedToPassengerWhatsApp(
        booking,
        driver,
      );

      _fetchAllAdminData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assignment Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // ROUTE PRICING
  // ---------------------------------------------------------

  void _showAddOrUpdateRouteDialog({
    Map<String, dynamic>? existingRoute,
  }) {
    final fromController = TextEditingController(
      text: existingRoute?['from_city'] ?? '',
    );

    final toController = TextEditingController(
      text: existingRoute?['to_city'] ?? '',
    );

    final priceController = TextEditingController(
      text: existingRoute?['fare']?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          existingRoute == null
              ? 'Add New Route & Fare'
              : 'Update Route Fare',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: fromController,
              decoration: const InputDecoration(
                labelText: 'From City (e.g., Buldhana)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: toController,
              decoration: const InputDecoration(
                labelText: 'To City (e.g., Pune)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Fare per Seat (₹)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _AppColors.primaryOrange,
            ),
            onPressed: () async {
              final from = fromController.text.trim();
              final to = toController.text.trim();
              final fare =
                  double.tryParse(priceController.text.trim()) ?? 0.0;

              if (from.isEmpty || to.isEmpty || fare <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please fill all fields correctly.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              try {
                if (existingRoute == null) {
                  await _supabase.from('route_prices').insert({
                    'from_city': from,
                    'to_city': to,
                    'fare': fare,
                  });
                } else {
                  await _supabase.from('route_prices').update({
                    'from_city': from,
                    'to_city': to,
                    'fare': fare,
                  }).eq('id', existingRoute['id']);
                }

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Route price saved successfully!',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );

                _fetchAllAdminData();
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error saving route: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Save Fare',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pendingPaymentBookings = _allBookings.where((b) {
      final pStatus = b['payment_status']?.toString().toLowerCase();
      final bStatus = b['booking_status']?.toString().toLowerCase();

      return pStatus == null ||
          pStatus == 'pending' ||
          bStatus == 'pending' ||
          bStatus == null;
    }).toList();

    final verifiedBookings = _allBookings.where((b) {
      final pStatus = b['payment_status']?.toString().toLowerCase();
      final bStatus = b['booking_status']?.toString().toLowerCase();

      return pStatus == 'verified' ||
          bStatus == 'payment_verified' ||
          bStatus == 'assigned' ||
          bStatus == 'accepted' ||
          bStatus == 'dispatched' ||
          bStatus == 'completed';
    }).toList();

    return Scaffold(
      backgroundColor: _AppColors.bgCream,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'RCM Admin Operations Panel',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchAllAdminData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _AppColors.primaryOrange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Driver Approvals & Fleet'),
            Tab(text: 'Verify Payments & Bookings'),
            Tab(text: 'Route Pricing & Fares'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: _AppColors.primaryOrange,
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // =================================================
                // TAB 1: DRIVER APPROVALS & FLEET
                // =================================================

                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Driver Applications',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _AppColors.textDark,
                        ),
                      ),

                      const SizedBox(height: 10),

                      _pendingDrivers.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'No pending driver approvals right now.',
                                style: TextStyle(
                                  color: _AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount: _pendingDrivers.length,
                              itemBuilder: (context, index) {
                                final driver = _pendingDrivers[index];

                                return Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 16,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            driver['full_name'] ?? 'Unknown',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color:
                                                    Colors.orange.shade300,
                                              ),
                                            ),
                                            child: Text(
                                              '⏳ Pending',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color:
                                                    Colors.orange.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 8),

                                      Text(
                                        'Phone: ${driver['phone_number']} • WhatsApp: ${driver['whatsapp_number'] ?? 'N/A'}\n'
                                        'Email: ${driver['email'] ?? 'N/A'}\n'
                                        'License: ${driver['license_number']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _AppColors.textMuted,
                                          height: 1.4,
                                        ),
                                      ),

                                      const SizedBox(height: 8),

                                      Text(
                                        'Vehicle: ${driver['car_name']} (${driver['car_number']}) • ${driver['car_type']} • ${driver['car_category']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.black87,
                                        ),
                                      ),

                                      const Divider(height: 20),

                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          ActionChip(
                                            label: const Text(
                                              'Aadhaar',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            onPressed: () =>
                                                _showDocumentDialog(
                                              'Aadhaar Card',
                                              driver['aadhaar_card_url'],
                                            ),
                                          ),
                                          ActionChip(
                                            label: const Text(
                                              'License',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            onPressed: () =>
                                                _showDocumentDialog(
                                              'Driving License',
                                              driver['driving_license_url'],
                                            ),
                                          ),
                                          ActionChip(
                                            label: const Text(
                                              'Car RC',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            onPressed: () =>
                                                _showDocumentDialog(
                                              'Car RC',
                                              driver['car_rc_url'],
                                            ),
                                          ),
                                          ActionChip(
                                            label: const Text(
                                              'Car Photo',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            onPressed: () =>
                                                _showDocumentDialog(
                                              'Car Photo',
                                              driver['car_photo_url'],
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              side: const BorderSide(
                                                color: Colors.red,
                                              ),
                                              shape:
                                                  RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () =>
                                                _rejectDriver(driver['id']),
                                            child: const Text(
                                              'Reject',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              shape:
                                                  RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () =>
                                                _approveDriver(driver),
                                            child: const Text(
                                              'Approve Driver',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                      const SizedBox(height: 24),

                      const Text(
                        'Approved Fleet Drivers (Active)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _AppColors.textDark,
                        ),
                      ),

                      const SizedBox(height: 10),

                      _approvedDriversList.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'No approved fleet drivers saved yet.',
                                style: TextStyle(
                                  color: _AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount: _approvedDriversList.length,
                              itemBuilder: (context, index) {
                                final activeDriver =
                                    _approvedDriversList[index];

                                return Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 12,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.green,
                                        child: Icon(
                                          Icons.verified,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),

                                      const SizedBox(width: 14),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              activeDriver['full_name'] ??
                                                  'Unknown Driver',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),

                                            const SizedBox(height: 4),

                                            Text(
                                              'Phone: ${activeDriver['phone_number'] ?? 'N/A'}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: _AppColors.textMuted,
                                              ),
                                            ),

                                            Text(
                                              'Vehicle: ${activeDriver['vehicle_model'] ?? 'N/A'} '
                                              '(${activeDriver['vehicle_number'] ?? 'N/A'})',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: _AppColors.textMuted,
                                              ),
                                            ),

                                            const SizedBox(height: 8),

                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _showApprovedDriverDetails(
                                                activeDriver,
                                              ),
                                              icon: const Icon(
                                                Icons.visibility,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'View Details',
                                              ),
                                              style:
                                                  OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    _AppColors.primaryOrange,
                                                side: const BorderSide(
                                                  color: _AppColors
                                                      .primaryOrange,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            _deleteActiveDriver(
                                          activeDriver['id'].toString(),
                                          activeDriver['full_name'] ??
                                              'this driver',
                                        ),
                                        tooltip: 'Remove Driver',
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),

                // =================================================
                // TAB 2: PAYMENT VERIFICATION & BOOKINGS
                // =================================================

                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.payment,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Step 1: Pending UTR & Payment Approvals (${pendingPaymentBookings.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _AppColors.textDark,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      pendingPaymentBookings.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'No pending payment verifications right now.',
                                style: TextStyle(
                                  color: _AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount: pendingPaymentBookings.length,
                              itemBuilder: (context, index) {
                                final booking =
                                    pendingPaymentBookings[index];

                                final utr = booking['utr_number'] ??
                                    booking['payment_utr'] ??
                                    'NOT PROVIDED';

                                final List seatsList =
                                    booking['selected_seats'] ?? [];

                                final seats = seatsList.isNotEmpty
                                    ? seatsList.join(', ')
                                    : (booking['seat_number'] ?? '1A');

                                return Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 16,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.orange.shade300,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'PNR: ${booking['pnr_number']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color:
                                                  _AppColors.primaryOrange,
                                            ),
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              '⏳ VERIFY PAYMENT',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                color: Colors.brown,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 8),

                                      Text(
                                        'Route: ${booking['from_location']} ➔ ${booking['to_location']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        'Travel Date: ${booking['travel_date']} (${booking['time_slot'] ?? '09:00 AM'}) • Seats: $seats',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _AppColors.textMuted,
                                        ),
                                      ),

                                      const SizedBox(height: 6),

                                      Text(
                                        'Passenger: ${booking['passenger_name']} (${booking['passenger_phone']})',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),

                                      const Divider(height: 16),

                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Payment UTR / Ref Number:',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  utr,
                                                  style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                const Text(
                                                  'Advance Amount:',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '₹${booking['advance_amount'] ?? 300}',
                                                  style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 14,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 16),

                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            padding:
                                                const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () =>
                                              _verifyPayment(booking),
                                          child: const Text(
                                            'Verify Payment & Confirm Ride (WhatsApp)',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                      const SizedBox(height: 28),

                      Row(
                        children: [
                          const Icon(
                            Icons.directions_car,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Step 2: Assign Driver for Verified Bookings (${verifiedBookings.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _AppColors.textDark,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      verifiedBookings.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'No verified bookings waiting for driver assignment.',
                                style: TextStyle(
                                  color: _AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              itemCount: verifiedBookings.length,
                              itemBuilder: (context, index) {
                                final booking = verifiedBookings[index];

                                final assignedDriverName =
                                    booking['driver_name'];

                                final assignedDriverId =
                                    booking['driver_id'];

                                Map<String, dynamic>? assignedDriverObj;

                                if (assignedDriverId != null) {
                                  try {
                                    assignedDriverObj =
                                        _approvedDriversList.firstWhere(
                                      (d) => d['id'] == assignedDriverId,
                                    );
                                  } catch (_) {}
                                }

                                return Container(
                                  margin: const EdgeInsets.only(
                                    bottom: 14,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'PNR: ${booking['pnr_number']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color:
                                                  _AppColors.primaryOrange,
                                            ),
                                          ),
                                          Text(
                                            '₹${booking['total_fare'] ?? 0}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 6),

                                      Text(
                                        '${booking['from_location']} ➔ ${booking['to_location']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),

                                      Text(
                                        'Travel Date: ${booking['travel_date']} (${booking['time_slot'] ?? '09:00 AM'})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _AppColors.textMuted,
                                        ),
                                      ),

                                      const SizedBox(height: 6),

                                      Text(
                                        'Passenger: ${booking['passenger_name']} (${booking['passenger_phone']})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _AppColors.textDark,
                                        ),
                                      ),

                                      const Divider(height: 16),

                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              assignedDriverName != null
                                                  ? 'Driver: $assignedDriverName'
                                                  : 'Driver: Not Assigned',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    assignedDriverName != null
                                                        ? Colors.green
                                                        : Colors.orange,
                                              ),
                                            ),
                                          ),

                                          DropdownButton<
                                              Map<String, dynamic>>(
                                            hint: const Text(
                                              'Assign Driver',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            items: _approvedDriversList
                                                .map((d) {
                                              return DropdownMenuItem<
                                                  Map<String, dynamic>>(
                                                value: d,
                                                child: Text(
                                                  d['full_name'] ?? 'Driver',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (selectedDriver) {
                                              if (selectedDriver != null) {
                                                _assignDriverToBooking(
                                                  booking,
                                                  selectedDriver,
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),

                                      if (assignedDriverObj != null) ...[
                                        const SizedBox(height: 10),

                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            style:
                                                OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  Colors.green.shade700,
                                              side: BorderSide(
                                                color:
                                                    Colors.green.shade300,
                                              ),
                                              shape:
                                                  RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () =>
                                                _sendTripDetailsToDriverWhatsApp(
                                              booking,
                                              assignedDriverObj!,
                                            ),
                                            icon: const Icon(
                                              Icons.send,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Send Trip Sheet to Driver (WhatsApp)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),

                // =================================================
                // TAB 3: ROUTE PRICING & FARES
                // =================================================

                Scaffold(
                  backgroundColor: _AppColors.bgCream,
                  floatingActionButton: FloatingActionButton.extended(
                    backgroundColor: _AppColors.primaryOrange,
                    onPressed: () => _showAddOrUpdateRouteDialog(),
                    icon: const Icon(
                      Icons.add,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Add Route Fare',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  body: _routePrices.isEmpty
                      ? const Center(
                          child: Text(
                            'No routes configured yet. Click below to add route fares.',
                            style: TextStyle(
                              color: _AppColors.textMuted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _routePrices.length,
                          itemBuilder: (context, index) {
                            final route = _routePrices[index];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${route['from_city']} ➔ ${route['to_city']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Standard Fare: ₹${route['fare']} / seat',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              _AppColors.primaryOrange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () =>
                                        _showAddOrUpdateRouteDialog(
                                      existingRoute: route,
                                    ),
                                  ),
                                ],
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