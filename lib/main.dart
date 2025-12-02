import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/api_service.dart';
import 'services/location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();

  // Check if service should be running and restart it if needed
  await _checkAndRestartService();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const LocusApp());
}

/// Checks if service was running before app was killed and restarts it
Future<void> _checkAndRestartService() async {
  final prefs = await SharedPreferences.getInstance();
  final shouldBeRunning = prefs.getBool('service_should_be_running') ?? false;
  final sessionId = prefs.getString('current_session_id');
  final endTime = prefs.getInt('session_end_time');

  if (shouldBeRunning && sessionId != null && endTime != null) {
    // Check if session is still valid
    if (DateTime.now().millisecondsSinceEpoch < endTime) {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        print('Restarting service after app relaunch...');
        await service.startService();
      }
    } else {
      // Session expired, clean up
      await prefs.remove('current_session_id');
      await prefs.remove('session_end_time');
      await prefs.setBool('service_should_be_running', false);
    }
  }
}

class LocusApp extends StatelessWidget {
  const LocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Locus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF3F3F46),
          surface: Color(0xFF18181B),
        ),
        useMaterial3: true,
      ),
      home: const LockScreen(),
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _enteredPin = '';
  bool _showError = false;
  static const String _correctPin = '281107';

  void _onKeyPressed(String key) {
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += key;
        _showError = false;
      });

      if (_enteredPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _showError = false;
      });
    }
  }

  void _verifyPin() {
    if (_enteredPin == _correctPin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SetupScreen()),
      );
    } else {
      setState(() {
        _showError = true;
        _enteredPin = '';
      });
    }
  }

  Widget _buildPinDot(int index) {
    final bool isFilled = index < _enteredPin.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 16,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFilled
            ? (_showError ? Colors.red : Colors.white)
            : Colors.transparent,
        border: Border.all(
          color: _showError ? Colors.red : Colors.grey[700]!,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildKeypadButton(String value, {bool isBackspace = false}) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.5,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isBackspace ? _onBackspace : () => _onKeyPressed(value),
              borderRadius: BorderRadius.circular(50),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF18181B),
                ),
                child: Center(
                  child: isBackspace
                      ? const Icon(
                          Icons.backspace_outlined,
                          color: Colors.white,
                          size: 24,
                        )
                      : Text(
                          value,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo/Title
              Image.asset('assets/locus.png', width: 80, height: 80),
              const SizedBox(height: 24),
              const Text(
                'LOCUS',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _showError ? 'Wrong PIN' : 'Enter PIN to continue',
                style: TextStyle(
                  fontSize: 14,
                  color: _showError ? Colors.red : Colors.grey,
                ),
              ),

              const SizedBox(height: 48),

              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) => _buildPinDot(index)),
              ),

              const Spacer(),

              // Keypad
              Column(
                children: [
                  Row(
                    children: [
                      _buildKeypadButton('1'),
                      _buildKeypadButton('2'),
                      _buildKeypadButton('3'),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKeypadButton('4'),
                      _buildKeypadButton('5'),
                      _buildKeypadButton('6'),
                    ],
                  ),
                  Row(
                    children: [
                      _buildKeypadButton('7'),
                      _buildKeypadButton('8'),
                      _buildKeypadButton('9'),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: SizedBox()), // Empty space
                      _buildKeypadButton('0'),
                      _buildKeypadButton('', isBackspace: true),
                    ],
                  ),
                ],
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// Setup Screen - First launch API URL & Permissions
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _urlController = TextEditingController();
  final ApiService _apiService = ApiService();
  int _currentStep = 0;
  bool _locationGranted = false;
  bool _backgroundLocationGranted = false;
  bool _notificationGranted = false;
  bool _batteryOptimizationDisabled = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final isSetupDone = prefs.getBool('setup_complete') ?? false;

    if (isSetupDone) {
      // Skip to home if already setup
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } else {
      // Load default URL
      final url = await _apiService.getBaseUrl();
      setState(() {
        _urlController.text = url;
      });
      _checkCurrentPermissions();
    }
  }

  Future<void> _checkCurrentPermissions() async {
    final locationStatus = await Permission.location.status;
    final backgroundStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;

    setState(() {
      _locationGranted = locationStatus.isGranted;
      _backgroundLocationGranted = backgroundStatus.isGranted;
      _notificationGranted = notificationStatus.isGranted;
      _batteryOptimizationDisabled = batteryStatus.isGranted;
    });
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    setState(() {
      _locationGranted = status.isGranted;
    });
  }

  Future<void> _requestBackgroundLocationPermission() async {
    final status = await Permission.locationAlways.request();
    setState(() {
      _backgroundLocationGranted = status.isGranted;
    });
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    setState(() {
      _notificationGranted = status.isGranted;
    });
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      setState(() {
        _batteryOptimizationDisabled = status.isGranted;
      });
    }
  }

  Future<void> _saveAndContinue() async {
    await _apiService.setBaseUrl(_urlController.text);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_complete', true);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // Header
              Image.asset('assets/locus.png', width: 60, height: 60),
              const SizedBox(height: 24),
              const Text(
                'Setup',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentStep == 0
                    ? 'Configure your server connection'
                    : 'Grant required permissions',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),

              const SizedBox(height: 48),

              // Steps
              Expanded(
                child: _currentStep == 0
                    ? _buildApiStep()
                    : _buildPermissionsStep(),
              ),

              // Navigation
              Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _currentStep--),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.grey[800]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Back'),
                        ),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _currentStep == 0
                            ? () => setState(() => _currentStep++)
                            : (_locationGranted ? _saveAndContinue : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: Colors.grey[800],
                          disabledForegroundColor: Colors.grey[600],
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _currentStep == 0 ? 'Next' : 'Complete Setup',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApiStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF18181B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[800]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cloud_outlined, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Server URL',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'http://your-server-ip:3000',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF09090B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Enter the URL where your Locus backend server is running. This is where location data will be sent.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsStep() {
    return Column(
      children: [
        _buildPermissionCard(
          icon: Icons.location_on_outlined,
          title: 'Location Access',
          description: 'Required to track device location',
          isGranted: _locationGranted,
          onRequest: _requestLocationPermission,
          isRequired: true,
        ),
        const SizedBox(height: 12),
        _buildPermissionCard(
          icon: Icons.location_searching,
          title: 'Background Location',
          description: 'Allow tracking when app is closed',
          isGranted: _backgroundLocationGranted,
          onRequest: _requestBackgroundLocationPermission,
          isRequired: false,
        ),
        const SizedBox(height: 12),
        _buildPermissionCard(
          icon: Icons.battery_saver_outlined,
          title: 'Disable Battery Optimization',
          description: 'Keeps tracking when app is killed',
          isGranted: _batteryOptimizationDisabled,
          onRequest: _requestBatteryOptimizationExemption,
          isRequired: false,
        ),
        const Spacer(),
        if (!_locationGranted)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Location permission is required to continue',
              style: TextStyle(fontSize: 13, color: Colors.red[400]),
            ),
          ),
      ],
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
    required bool isRequired,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? const Color(0xFF10B981).withOpacity(0.3)
              : Colors.grey[800]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isGranted
                  ? const Color(0xFF10B981).withOpacity(0.1)
                  : Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isGranted ? const Color(0xFF10B981) : Colors.grey,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (isRequired) ...[
                      const SizedBox(width: 6),
                      Text(
                        '*',
                        style: TextStyle(fontSize: 16, color: Colors.red[400]),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          if (isGranted)
            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24)
          else
            TextButton(
              onPressed: onRequest,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.grey[800],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Grant'),
            ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final TextEditingController _urlController = TextEditingController();

  bool _isTracking = false;
  String? _sessionId;
  int _durationHours = 12;
  String _deviceId = '...';
  String _statusMessage = 'Ready';
  late AnimationController _pulseController;

  // New UX state
  int? _sessionEndTime;
  String _remainingTime = '';
  int _queuedLocations = 0;
  bool _isOffline = false;
  double _lastAccuracy = 0;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadSettings();
    _checkPermissions();
    _getDeviceId();
    _checkActiveSession();

    // Start UI update timer
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemainingTime();
      _updateQueueStatus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _uiTimer?.cancel();
    super.dispose();
  }

  void _updateRemainingTime() {
    if (_sessionEndTime != null && _isTracking) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = _sessionEndTime! - now;

      if (remaining > 0) {
        final hours = (remaining / (1000 * 60 * 60)).floor();
        final minutes = ((remaining % (1000 * 60 * 60)) / (1000 * 60)).floor();
        final seconds = ((remaining % (1000 * 60)) / 1000).floor();

        setState(() {
          _remainingTime =
              '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        });
      } else {
        setState(() {
          _remainingTime = '00:00:00';
          _isTracking = false;
          _statusMessage = 'Session Expired';
        });
      }
    }
  }

  Future<void> _updateQueueStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('offline_location_queue') ?? [];
    final lastAcc = prefs.getDouble('last_accuracy') ?? 0;
    final isOffline = prefs.getBool('is_offline') ?? false;

    if (mounted) {
      setState(() {
        _queuedLocations = queue.length;
        _lastAccuracy = lastAcc;
        _isOffline = isOffline;
      });
    }
  }

  Future<void> _loadSettings() async {
    final url = await _apiService.getBaseUrl();
    setState(() {
      _urlController.text = url;
    });
  }

  Future<void> _saveSettings() async {
    await _apiService.setBaseUrl(_urlController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: Color(0xFF18181B),
        ),
      );
    }
  }

  Future<void> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String id = 'unknown';
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        id = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        id = iosInfo.identifierForVendor ?? 'unknown';
      }
    } catch (e) {
      print('Error getting device ID: $e');
    }
    if (mounted) {
      setState(() {
        _deviceId = id;
      });
    }
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
    ].request();
  }

  Future<void> _checkActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('current_session_id');
    final endTime = prefs.getInt('session_end_time');

    if (sessionId != null && endTime != null) {
      if (DateTime.now().millisecondsSinceEpoch < endTime) {
        setState(() {
          _isTracking = true;
          _sessionId = sessionId;
          _sessionEndTime = endTime;
          _statusMessage = 'Tracking Active';
        });
      } else {
        await prefs.remove('current_session_id');
        await prefs.remove('session_end_time');
      }
    }
  }

  Future<void> _startSession() async {
    if (_deviceId == 'unknown') await _getDeviceId();

    setState(() => _statusMessage = 'Initializing...');

    final result = await _apiService.startSession(_deviceId, _durationHours);

    if (result != null) {
      final sessionId = result['sessionId'];
      final endTime = result['endTime'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_session_id', sessionId);
      await prefs.setInt('session_end_time', endTime);
      await prefs.setBool('service_should_be_running', true);

      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        service.startService();
      }

      setState(() {
        _isTracking = true;
        _sessionId = sessionId;
        _sessionEndTime = endTime;
        _statusMessage = 'Tracking Active';
      });
    } else {
      setState(() => _statusMessage = 'Failed to start');
    }
  }

  Future<void> _stopSession() async {
    if (_sessionId != null) {
      await _apiService.stopSession(_sessionId!);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_session_id');
    await prefs.remove('session_end_time');
    await prefs.setBool('service_should_be_running', false);

    final service = FlutterBackgroundService();
    service.invoke("stopService");

    setState(() {
      _isTracking = false;
      _sessionId = null;
      _sessionEndTime = null;
      _remainingTime = '';
      _statusMessage = 'Session Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOCUS',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'SILENT TRACKER',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () => _showSettingsDialog(),
                  ),
                ],
              ),

              const Spacer(),

              // Main Status Card
              Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isTracking
                          ? const Color(0xFF10B981).withOpacity(0.3)
                          : Colors.white.withOpacity(0.05),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Pulse Animation
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isTracking)
                            FadeTransition(
                              opacity: _pulseController,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(
                                    0xFF10B981,
                                  ).withOpacity(0.2),
                                ),
                              ),
                            ),
                          Icon(
                            _isTracking
                                ? Icons.radar
                                : Icons.location_off_outlined,
                            size: 40,
                            color: _isTracking
                                ? const Color(0xFF10B981)
                                : Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _statusMessage.toUpperCase(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: _isTracking
                              ? const Color(0xFF10B981)
                              : Colors.grey,
                        ),
                      ),
                      // Remaining time countdown
                      if (_isTracking && _remainingTime.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _remainingTime,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 32,
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'REMAINING',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                      if (_sessionId != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _sessionId!.split('-')[0],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                      // Status indicators row
                      if (_isTracking) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // GPS Accuracy indicator
                            _buildStatusChip(
                              icon: Icons.gps_fixed,
                              label: _lastAccuracy > 0
                                  ? '±${_lastAccuracy.toStringAsFixed(0)}m'
                                  : '--',
                              color: _getAccuracyColor(_lastAccuracy),
                            ),
                            // Connection status
                            _buildStatusChip(
                              icon: _isOffline
                                  ? Icons.cloud_off
                                  : Icons.cloud_done,
                              label: _isOffline ? 'Offline' : 'Online',
                              color: _isOffline
                                  ? Colors.orange
                                  : const Color(0xFF10B981),
                            ),
                            // Queue indicator
                            if (_queuedLocations > 0)
                              _buildStatusChip(
                                icon: Icons.schedule,
                                label: '$_queuedLocations queued',
                                color: Colors.orange,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Controls
              if (!_isTracking) ...[
                const Text(
                  'DURATION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.grey[800],
                          thumbColor: Colors.white,
                          overlayColor: Colors.white.withOpacity(0.1),
                          trackHeight: 2,
                        ),
                        child: Slider(
                          value: _durationHours.toDouble(),
                          min: 1,
                          max: 24,
                          divisions: 23,
                          onChanged: (value) {
                            setState(() {
                              _durationHours = value.toInt();
                            });
                          },
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_durationHours}h',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'START TRACKING',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _stopSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27272A), // Zinc 800
                      foregroundColor: Colors.red[400],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: const Text(
                      'STOP TRACKING',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Device ID: ${_deviceId.length > 8 ? "${_deviceId.substring(0, 8)}..." : _deviceId}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[800]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'API Base URL',
                labelStyle: const TextStyle(color: Colors.grey),
                hintText: 'http://your-server-ip:3000',
                hintStyle: TextStyle(color: Colors.grey[800]),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy <= 0) return Colors.grey;
    if (accuracy <= 10) return const Color(0xFF10B981); // Excellent
    if (accuracy <= 30) return const Color(0xFF3B82F6); // Good
    if (accuracy <= 100) return Colors.orange; // Fair
    return Colors.red; // Poor
  }
}
