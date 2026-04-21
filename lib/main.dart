import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const SafeWalkApp());

class SafeWalkApp extends StatelessWidget {
  const SafeWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeWalk Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          primary: const Color(0xFF0D47A1),
          secondary: const Color(0xFF00C853),
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
  final AudioPlayer _sirenPlayer = AudioPlayer();
  final TextEditingController _contactController = TextEditingController();
  
  bool _isWalking = false;
  bool _isPhoneInUse = false;
  bool _alertTriggered = false;
  bool _isSirenOn = false;
  bool _sosSent = false;
  
  List<String> _trustedNumbers = [];
  Timer? _walkTimer;
  int _secondsRemaining = 0;
  bool _isTimerActive = false;
  double _sliderValue = 300; 
  
  late AnimationController _alertAnimationController;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _alertAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    userAccelerometerEventStream().listen((event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (magnitude > 2.5 != _isWalking) {
        setState(() => _isWalking = magnitude > 2.5);
        if (_isWalking) _checkUnsafeUsage();
      }
    });

    accelerometerEventStream().listen((event) {
      bool tilted = event.y > 3.0 && event.y < 9.0;
      if (tilted != _isPhoneInUse) {
        setState(() => _isPhoneInUse = tilted);
        if (tilted) _checkUnsafeUsage();
      }
    });
  }

  @override
  void dispose() {
    _alertAnimationController.dispose();
    _walkTimer?.cancel();
    _audioPlayer.dispose();
    _sirenPlayer.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _trustedNumbers = prefs.getStringList('trusted_numbers') ?? [];
    });
  }

  Future<void> _addContact(String number) async {
    String formatted = number.trim().replaceAll(' ', '');
    if (formatted.isEmpty) return;
    if (!formatted.startsWith('+') && formatted.length == 9) formatted = "+237$formatted";
    if (_trustedNumbers.length >= 5) { _showError("Max 5 contacts allowed"); return; }

    final prefs = await SharedPreferences.getInstance();
    if (!_trustedNumbers.contains(formatted)) {
      setState(() {
        _trustedNumbers.add(formatted);
        _contactController.clear();
      });
      await prefs.setStringList('trusted_numbers', _trustedNumbers);
    }
  }

  Future<void> _removeContact(String number) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _trustedNumbers.remove(number));
    await prefs.setStringList('trusted_numbers', _trustedNumbers);
  }

  void _toggleSiren() async {
    setState(() => _isSirenOn = !_isSirenOn);
    if (_isSirenOn) {
      _sirenPlayer.setReleaseMode(ReleaseMode.loop);
      await _sirenPlayer.play(AssetSource('alert.mp3'));
      Vibration.vibrate(pattern: [500, 500], repeat: 0);
    } else {
      await _sirenPlayer.stop();
      Vibration.cancel();
    }
  }

  Future<void> _sendSafeCheckIn() async {
    if (_trustedNumbers.isEmpty) { _showContactSheet(); return; }
    try {
      Position position = await _determinePosition();
      String mapLink = "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
      String message = "✅ I AM SAFE: Just checking in to let you know I've arrived safely. Location: $mapLink";
      String recipients = _trustedNumbers.join(',');
      Uri url = Uri.parse("sms:$recipients?body=${Uri.encodeComponent(message)}");
      if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) { _showError("Check-in failed: Enable location services."); }
  }

  void _startTimer(int seconds) {
    _cancelTimer();
    setState(() { _secondsRemaining = seconds; _isTimerActive = true; });
    _walkTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _cancelTimer();
        _sendSOS(method: 'sms'); 
      }
    });
  }

  void _cancelTimer() { _walkTimer?.cancel(); setState(() => _isTimerActive = false); }

  Future<void> _viewOnMap() async {
    try {
      Position position = await _determinePosition();
      final url = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) { _showError(e.toString()); }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw 'Location services are disabled.';
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) throw 'Location permissions permanently denied';
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _sendSOS({required String method}) async {
    if (_trustedNumbers.isEmpty) { _showError("Add contacts first!"); _showContactSheet(); return; }
    try {
      Position position = await _determinePosition();
      String mapLink = "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
      String message = "🚨 I NEED HELP! SafeWalk Pro alert. My location: $mapLink";
      
      setState(() => _sosSent = true);
      _checkUnsafeUsage(); 

      if (method == 'whatsapp') {
        // WhatsApp Contact Picker allows selecting multiple people manually
        Uri url = Uri.parse("whatsapp://send?text=${Uri.encodeComponent(message)}");
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else {
          // Fallback to web link if uri scheme fails
          Uri webUrl = Uri.parse("https://wa.me/?text=${Uri.encodeComponent(message)}");
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        String recipients = _trustedNumbers.join(',');
        Uri url = Uri.parse("sms:$recipients?body=${Uri.encodeComponent(message)}");
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) { _showError("Error: Ensure GPS is on."); }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _checkUnsafeUsage() {
    if ((_isWalking && _isPhoneInUse) || _sosSent) {
      if (!_alertTriggered) {
        setState(() => _alertTriggered = true);
        _alertAnimationController.repeat(reverse: true);
        _audioPlayer.setReleaseMode(ReleaseMode.loop);
        _audioPlayer.play(AssetSource('alert.mp3'));
        Vibration.vibrate(pattern: [0, 500, 200, 500], repeat: 0);
      }
    }
  }

  void _stopAlert() {
    setState(() {
      _alertTriggered = false;
      _isWalking = false;
      _isPhoneInUse = false;
      _sosSent = false;
      _isSirenOn = false;
    });
    _alertAnimationController.stop();
    _audioPlayer.stop();
    _sirenPlayer.stop();
    Vibration.cancel();
  }

  String _formatDuration(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return minutes > 0 ? "${minutes}m ${seconds}s" : "${seconds}s";
  }

  void _showSOSOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Emergency SOS", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("Select method to alert your contacts", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(child: _sosOptionTile(icon: Icons.sms, label: "SMS (All)", color: Colors.red.shade700, onTap: () { Navigator.pop(ctx); _sendSOS(method: 'sms'); })),
                const SizedBox(width: 15),
                Expanded(child: _sosOptionTile(icon: Icons.message, label: "WHATSAPP", color: Colors.green.shade600, onTap: () { Navigator.pop(ctx); _sendSOS(method: 'whatsapp'); })),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sosOptionTile({required IconData icon, required String label, required Color color, required VoidCallback onTap, bool isFullWidth = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.blue.shade900, Colors.grey.shade100]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSafetyStatus(),
                      const SizedBox(height: 15),
                      if (_alertTriggered || _sosSent || _isSirenOn) _buildStopButton(),
                      const SizedBox(height: 10),
                      _buildSensorStatusCard(),
                      const SizedBox(height: 25),
                      _buildBigSOSButton(),
                      const SizedBox(height: 30),
                      _buildToolbox(),
                      const SizedBox(height: 25),
                      _buildTimerCard(),
                      const SizedBox(height: 20),
                      _buildMapButton(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showContactSheet,
        label: Text(_trustedNumbers.isEmpty ? "No Contacts" : "${_trustedNumbers.length} Contacts Active"),
        icon: const Icon(Icons.people),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue.shade900,
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SafeWalk Pro", style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
              Text("Active Protection System", style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          IconButton(onPressed: _showContactSheet, icon: const Icon(Icons.settings, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildSafetyStatus() {
    bool isProtected = _trustedNumbers.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: isProtected ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isProtected ? Icons.verified : Icons.error, color: isProtected ? Colors.greenAccent : Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Text(isProtected ? "SYSTEM ARMED" : "SYSTEM DISARMED", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStopButton() {
    return FadeTransition(
      opacity: _alertAnimationController,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        child: ElevatedButton.icon(
          onPressed: _stopAlert,
          icon: const Icon(Icons.security_update_good, size: 28),
          label: const Text("STOP ALARM & RESET", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 8,
          ),
        ),
      ),
    );
  }

  Widget _buildSensorStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statusWidget(Icons.directions_run, _isWalking, "Walking"),
            _statusWidget(Icons.phonelink_ring, _isPhoneInUse, "In Use"),
          ],
        ),
      ),
    );
  }

  Widget _buildBigSOSButton() {
    return GestureDetector(
      onTap: _showSOSOptions,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Colors.red.shade900, Colors.red.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), spreadRadius: 8, blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 60),
              SizedBox(height: 5),
              Text("SOS", style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900)),
              Text("PRESS FOR HELP", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("SAFETY TOOLBOX", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _toolCard(_isSirenOn ? "STOP SIREN" : "PANIC SIREN", _isSirenOn ? Icons.volume_up : Icons.volume_off, _isSirenOn ? Colors.orange : Colors.blue, _toggleSiren)),
            const SizedBox(width: 15),
            Expanded(child: _toolCard("I AM SAFE", Icons.check_circle, Colors.green, _sendSafeCheckIn)),
          ],
        ),
      ],
    );
  }

  Widget _toolCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.av_timer, color: Colors.blueGrey),
                const SizedBox(width: 10),
                const Text("Safety Journey Timer", style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!_isTimerActive) Text(_formatDuration(_sliderValue.toInt()), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            if (!_isTimerActive)
              Column(
                children: [
                  Slider(value: _sliderValue, min: 10, max: 3600, divisions: 359, label: _formatDuration(_sliderValue.toInt()), onChanged: (v) => setState(() => _sliderValue = v)),
                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("10s", style: TextStyle(fontSize: 10, color: Colors.grey)), Text("1h", style: TextStyle(fontSize: 10, color: Colors.grey))]),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: () => _startTimer(_sliderValue.toInt()), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("START TRACKING", style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              )
            else
              _activeTimerUI(),
          ],
        ),
      ),
    );
  }

  Widget _activeTimerUI() {
    return Column(
      children: [
        Text(_formatDuration(_secondsRemaining), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.red)),
        const Text("AUTO-SMS ON EXPIRY", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
        TextButton(onPressed: _cancelTimer, child: const Text("CANCEL TRACKING", style: TextStyle(color: Colors.grey))),
      ],
    );
  }

  Widget _buildMapButton() {
    return InkWell(
      onTap: _viewOnMap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade900]), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(alignment: Alignment.center, children: [Container(width: 45, height: 45, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle)), const Icon(Icons.location_on, color: Colors.redAccent, size: 28)]),
            const SizedBox(width: 20),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("VIEW ACTUAL LOCATION", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), Text("Live GPS Tracking Active", style: TextStyle(color: Colors.white54, fontSize: 11))]),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _statusWidget(IconData icon, bool active, String label) {
    return Column(children: [Icon(icon, color: active ? Colors.blue : Colors.grey.shade300, size: 35), Text(label, style: TextStyle(color: active ? Colors.blue : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))]);
  }

  void _showContactSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (context, setSheetState) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 25, right: 25, top: 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Emergency Contacts", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Your safety net in Cameroon", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.all(15),
              child: TextField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(hintText: "Enter 9-digit number", prefixText: "+237 ", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 32), onPressed: () async { if (_contactController.text.isNotEmpty) { await _addContact(_contactController.text); setSheetState(() {}); } })),
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: _trustedNumbers.isEmpty ? const Padding(padding: EdgeInsets.all(20), child: Text("No contacts added.")) : ListView.builder(shrinkWrap: true, itemCount: _trustedNumbers.length, itemBuilder: (context, index) {
                final num = _trustedNumbers[index];
                return ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(num), trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () async { await _removeContact(num); setSheetState(() {}); }));
              }),
            ),
            const SizedBox(height: 30),
          ],
        ),
      )),
    );
  }
}
