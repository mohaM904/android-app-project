import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const SafeWalkApp());

class SafeWalkApp extends StatelessWidget {
  const SafeWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeWalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        cardTheme: const CardThemeData(
          elevation: 4,
          margin: EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        ),
      ),
      home: const SafeWalkHomePage(),
    );
  }
}

class SafeWalkHomePage extends StatefulWidget {
  const SafeWalkHomePage({super.key});

  @override
  State<SafeWalkHomePage> createState() => _SafeWalkHomePageState();
}

class _SafeWalkHomePageState extends State<SafeWalkHomePage> with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isWalking = false;
  bool _isPhoneInUse = false;
  bool _alertTriggered = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    // Listen to real sensors (Works on Mobile)
    accelerometerEventStream().listen((AccelerometerEvent event) {
      double acceleration = (event.x * event.x + event.y * event.y + event.z * event.z).abs();
      if (acceleration > 15.0 && !_isWalking) {
        setState(() => _isWalking = true);
        _checkUnsafeUsage();
      } else if (acceleration < 10.0 && _isWalking) {
        setState(() => _isWalking = false);
      }
    });

    gyroscopeEventStream().listen((GyroscopeEvent event) {
      bool inUse = event.z.abs() > 1.0;
      if (inUse != _isPhoneInUse) {
        setState(() => _isPhoneInUse = inUse);
        _checkUnsafeUsage();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _checkUnsafeUsage() {
    if (_isWalking && _isPhoneInUse && !_alertTriggered) {
      _triggerAlert();
    }
  }

  void _triggerAlert() {
    if (_alertTriggered) return;
    setState(() => _alertTriggered = true);
    _animationController.repeat(reverse: true);
    _triggerVibration();
    _playSound();
    _showSnackBar();
    
    // Auto-stop alert after 10 seconds (increased for testing)
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _alertTriggered) {
        _stopAlert();
      }
    });
  }

  void _stopAlert() {
    setState(() {
      _alertTriggered = false;
      // Also reset simulation switches so it doesn't immediately re-trigger
      _isWalking = false;
      _isPhoneInUse = false;
    });
    _animationController.stop();
    _animationController.reset();
    _audioPlayer.stop();
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  void _triggerVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 500);
    }
  }

  void _playSound() {
    _audioPlayer.play(AssetSource('alert.mp3'));
  }

  void _showSnackBar() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('⚠️ ALERT: Stop using your phone while walking!'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'STOP',
          textColor: Colors.white,
          onPressed: _stopAlert,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeWalk Security', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: _alertTriggered ? Colors.red : Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // 1. Main Status Display
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _alertTriggered ? _scaleAnimation.value : 1.0,
                    child: Card(
                      color: _alertTriggered ? Colors.red.shade100 : Colors.green.shade50,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(30.0),
                        child: Column(
                          children: [
                            Icon(
                              _alertTriggered ? Icons.warning_amber_rounded : Icons.shield_outlined,
                              size: 80,
                              color: _alertTriggered ? Colors.red : Colors.green,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _alertTriggered ? 'DANGER DETECTED' : 'SYSTEM SECURE',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: _alertTriggered ? Colors.red : Colors.green,
                              ),
                            ),
                            Text(
                              _alertTriggered ? 'Please stop walking!' : 'Keep staying safe',
                              style: TextStyle(color: _alertTriggered ? Colors.red : Colors.green.shade700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 20),
              
              // 2. Real-time Status Indicators
              Row(
                children: [
                  Expanded(
                    child: _buildStatusCard(
                      icon: Icons.directions_walk,
                      label: 'Walking',
                      isActive: _isWalking,
                      activeColor: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildStatusCard(
                      icon: Icons.phone_android,
                      label: 'In Use',
                      isActive: _isPhoneInUse,
                      activeColor: Colors.purple,
                    ),
                  ),
                ],
              ),

              const Divider(height: 40),

              // 3. Simulation Panel (Crucial for PC Testing)
              const Text("DEVELOPER TOOLS (Simulate Sensors)", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text("Simulate Walking"),
                      secondary: const Icon(Icons.run_circle_outlined),
                      value: _isWalking,
                      onChanged: (val) {
                        setState(() => _isWalking = val);
                        _checkUnsafeUsage();
                      },
                    ),
                    SwitchListTile(
                      title: const Text("Simulate Phone Looking"),
                      secondary: const Icon(Icons.remove_red_eye_outlined),
                      value: _isPhoneInUse,
                      onChanged: (val) {
                        setState(() => _isPhoneInUse = val);
                        _checkUnsafeUsage();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 4. Test / Stop Button
              SizedBox(
                width: double.infinity,
                child: _alertTriggered 
                  ? FilledButton.icon(
                      onPressed: _stopAlert,
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('STOP ALERT NOW'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _triggerAlert,
                      icon: const Icon(Icons.notification_important),
                      label: const Text('MANUAL ALERT TEST'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
              ),

              const SizedBox(height: 30),

              // 5. Safety Tips Section
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Safety Tips", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              _buildTip("Never look at your phone while crossing the street."),
              _buildTip("Keep one ear free from headphones to hear traffic."),
              _buildTip("Use the 'Do Not Disturb' mode while walking."),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.lightbulb, size: 20, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildStatusCard({required IconData icon, required String label, required bool isActive, required Color activeColor}) {
    return Card(
      color: isActive ? activeColor.withOpacity(0.1) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(icon, size: 40, color: isActive ? activeColor : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isActive ? activeColor : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              isActive ? 'ON' : 'OFF',
              style: TextStyle(fontSize: 10, color: isActive ? activeColor : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
