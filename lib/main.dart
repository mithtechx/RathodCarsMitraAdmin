import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_colors.dart';
import 'features/dashboard/admin_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
   url: 'https://hcqvtqjnhzqtoottogug.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhjcXZ0cWpuaHpxdG9vdHRvZ3VnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5MTM3NDQsImV4cCI6MjEwNjQ4OTc0NH0.W2Rz9l_8mKPeQzqIlXadaa4uWxtbG9Hni_n0vwEm1dY',
  );

  runApp(const RCMAdminApp());
}

class RCMAdminApp extends StatelessWidget {
  const RCMAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RCM Admin Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.bgCream,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const AdminDashboardScreen(),
    );
  }
}