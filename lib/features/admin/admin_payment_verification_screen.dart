import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';

class AdminPaymentVerificationScreen extends StatefulWidget {
  const AdminPaymentVerificationScreen({super.key});

  @override
  State<AdminPaymentVerificationScreen> createState() =>
      _AdminPaymentVerificationScreenState();
}

class _AdminPaymentVerificationScreenState
    extends State<AdminPaymentVerificationScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingBookings = [];
  List<Map<String, dynamic>> _confirmedBookings = [];
  List<Map<String, dynamic>> _rejectedBookings = [];

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('bookings')
          .select()
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> allBookings =
          List<Map<String, dynamic>>.from(response);

      setState(() {
        _pendingBookings = allBookings
            .where((b) => b['payment_status'] == 'pending_verification')
            .toList();
        _confirmedBookings = allBookings
            .where((b) => b['payment_status'] == 'verified')
            .toList();
        _rejectedBookings = allBookings
            .where((b) => b['payment_status'] == 'rejected')
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading bookings: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPaymentVerifiedWhatsApp(Map<String, dynamic> booking) async {
    final passengerName = booking['passenger_name'] ?? booking['full_name'] ?? 'Valued Passenger';
    final phoneRaw = booking['passenger_phone'] ?? booking['phone_number'] ?? booking['mobile'] ?? '';
    
    String cleanPhone = phoneRaw.toString().replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final pnr = booking['pnr_number'] ?? booking['pnr'] ?? 'RC-2026-BOOKING';
    final fromCity = booking['from_location'] ?? booking['from_city'] ?? 'Buldhana';
    final toCity = booking['to_location'] ?? booking['to_city'] ?? 'Pune';
    final travelDate = booking['travel_date'] ?? 'N/A';
    final departureTime = booking['time_slot'] ?? booking['departure_time'] ?? '09:00 AM';
    final vehicleType = booking['vehicle_type'] ?? booking['vehicle_category'] ?? 'Sedan';
    final List seatsList = booking['selected_seats'] ?? [];
    final seats = seatsList.isNotEmpty ? seatsList.join(', ') : (booking['seat_number'] ?? '1A');
    
    final totalFare = booking['total_fare'] ?? booking['total_price'] ?? '0';
    final advancePaid = booking['advance_amount'] ?? booking['advance_paid'] ?? '300';
    
    final totalNum = double.tryParse(totalFare.toString()) ?? 0.0;
    final advanceNum = double.tryParse(advancePaid.toString()) ?? 300.0;
    final balanceDue = (totalNum > 0) ? (totalNum - advanceNum).toStringAsFixed(0) : '300';

    final utrNumber = booking['utr_number'] ?? booking['utr'] ?? 'N/A';

    final message = '''🚗 RATHOD CARS MITRA (RCM) - OFFICIAL BOOKING CONFIRMATION 🚗

Namaste $passengerName ji! 🙏
Thank you for choosing Rathod Cars Mitra for your upcoming travel. We are thrilled to have you on board!

Your advance payment has been successfully VERIFIED & APPROVED ✅. Your seat is now locked in. Below are your complete journey and payment details:

📋 BOOKING & TRIP SUMMARY:
• PNR / Booking Ref: $pnr
• Route: $fromCity ➔ $toCity
• Travel Date: $travelDate
• Departure Time: $departureTime
• Vehicle Type: $vehicleType
• Seat Number(s): $seats

💵 FARE & PAYMENT BREAKDOWN:
• Total Trip Fare: Rs. $totalFare
• Advance Paid (Online): Rs. $advancePaid
• Balance Due to Driver: Rs. $balanceDue (to be paid in cash/UPI upon boarding)
• UTR / Payment Ref: $utrNumber

🚘 WHAT HAPPENS NEXT?
Our admin team is currently assigning your dedicated professional driver and vehicle. You will receive a second WhatsApp notification containing your Driver's Name, Mobile Number, and Car Number shortly before departure.

📌 Important Guidelines:
1. Please arrive at the pickup point at least 10 minutes prior to departure.
2. Keep a valid Government ID proof handy during travel.

For any immediate assistance or queries, feel free to call or WhatsApp our 24/7 support line at +91 8261039902.

Have a safe, comfortable, and wonderful journey with Rathod Cars Mitra! 🌟''';

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp URL.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching WhatsApp: $e')),
      );
    }
  }

  Future<void> _updateBookingStatus({
    required Map<String, dynamic> booking,
    required String paymentStatus,
    required String bookingStatus,
    String? rejectionReason,
  }) async {
    try {
      final bookingId = booking['id'].toString();
      final updates = {
        'payment_status': paymentStatus,
        'booking_status': bookingStatus,
        'updated_at': DateTime.now().toIso8601String(),
        if (rejectionReason != null) 'rejection_reason': rejectionReason,
      };

      await _supabase.from('bookings').update(updates).eq('id', bookingId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paymentStatus == 'verified'
                ? 'Booking Approved & Confirmed!'
                : 'Booking Rejected.',
          ),
          backgroundColor:
              paymentStatus == 'verified' ? Colors.green : Colors.red,
        ),
      );

      // If approved, trigger the detailed WhatsApp message automatically
      if (paymentStatus == 'verified') {
        await _sendPaymentVerifiedWhatsApp(booking);
      }

      _fetchBookings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  void _showRejectDialog(Map<String, dynamic> booking) {
    final reasonController = TextEditingController();
    final bookingId = booking['id'].toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter reason for rejecting this payment (e.g., UTR not received/invalid):'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Rejection Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _updateBookingStatus(
                booking: booking,
                paymentStatus: 'rejected',
                bookingStatus: 'cancelled',
                rejectionReason: reasonController.text.trim().isEmpty
                    ? 'Invalid UTR'
                    : reasonController.text.trim(),
              );
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      appBar: AppBar(
        title: const Text('Admin - Booking & UTR Approvals'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBookings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Pending (${_pendingBookings.length})'),
            Tab(text: 'Verified (${_confirmedBookings.length})'),
            Tab(text: 'Rejected (${_rejectedBookings.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by PNR, Phone, Name, or UTR...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBookingList(_pendingBookings, isPending: true),
                      _buildBookingList(_confirmedBookings),
                      _buildBookingList(_rejectedBookings),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingList(List<Map<String, dynamic>> list, {bool isPending = false}) {
    final filteredList = list.where((b) {
      final pnr = (b['pnr_number'] ?? '').toString().toLowerCase();
      final phone = (b['passenger_phone'] ?? '').toString().toLowerCase();
      final name = (b['passenger_name'] ?? '').toString().toLowerCase();
      final utr = (b['utr_number'] ?? '').toString().toLowerCase();

      return pnr.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          name.contains(_searchQuery) ||
          utr.contains(_searchQuery);
    }).toList();

    if (filteredList.isEmpty) {
      return const Center(
        child: Text('No bookings found.', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final booking = filteredList[index];
        final List selectedSeats = booking['selected_seats'] ?? [];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PNR: ${booking['pnr_number']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPending
                            ? Colors.orange.shade100
                            : booking['payment_status'] == 'verified'
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        booking['payment_status'].toString().toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isPending
                              ? Colors.orange.shade900
                              : booking['payment_status'] == 'verified'
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Text('Passenger: ${booking['passenger_name']} (${booking['passenger_phone']})'),
                Text('Route: ${booking['from_location']} ➔ ${booking['to_location']}'),
                Text('Date & Time: ${booking['travel_date']} | ${booking['time_slot']}'),
                Text('Seats (${selectedSeats.length}): ${selectedSeats.join(', ')}'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SelectableText(
                        'UTR: ${booking['utr_number'] ?? 'N/A'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                      ),
                      Text('Advance: ₹${booking['advance_amount']}'),
                    ],
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _showRejectDialog(booking),
                          icon: const Icon(Icons.cancel, size: 18),
                          label: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          onPressed: () => _updateBookingStatus(
                            booking: booking,
                            paymentStatus: 'verified',
                            bookingStatus: 'confirmed',
                          ),
                          icon: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                          label: const Text('Approve', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}