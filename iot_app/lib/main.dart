import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'smart_lamp_channel', 
    'Smart Lamp Notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  await localNotif
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotif.initialize(const InitializationSettings(android: androidInit));

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: Colors.amber),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference db = FirebaseDatabase.instance.ref();
  
  bool status = false;
  String mode = "-";
  String time = "Syncing...";
  String startStr = "17:45";
  String endStr = "03:30";
  List<Map<dynamic, dynamic>> logs = [];
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _listenToFirebase();
  }

  void _clearLogs() {
    db.child("logs").remove();
  }

  Future<void> _triggerNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails('smart_lamp_channel', 'Smart Lamp Notifications', importance: Importance.max, priority: Priority.high);
    await localNotif.show(DateTime.now().millisecond, title, body, const NotificationDetails(android: androidDetails));
  }

  void _listenToFirebase() {
    db.child("lampu").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          status = data["status"] ?? false;
          mode = data["mode"] ?? "-";
          time = data["time"] ?? "-";
        });
      }
    });

    db.child("settings").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          startStr = data["startTime"] ?? "17:45";
          endStr = data["endTime"] ?? "03:30";
        });
      }
    });

    db.child("logs").limitToLast(1).onChildAdded.listen((event) {
      final logData = event.snapshot.value as Map?;
      if (logData != null && !_isInitialLoad) {
          _triggerNotification("Update Lampu", "${logData['event']} via ${logData['mode']}");
      }
    });

    Future.delayed(const Duration(seconds: 2), () => _isInitialLoad = false);

    db.child("logs").limitToLast(20).onValue.listen((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map && mounted) {
        final List<Map<dynamic, dynamic>> tempLogs = [];
        data.forEach((key, value) => tempLogs.add(Map<dynamic, dynamic>.from(value as Map)));
        tempLogs.sort((a, b) => (b["time"] ?? "").compareTo(a["time"] ?? ""));
        setState(() => logs = tempLogs);
      } else {
        setState(() => logs = []);
      }
    });
  }

  void _sendCommand(String cmd) => db.child("command/value").set(cmd);

  Future<void> _changeTime(String key) async {
    TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      String formatted = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      db.child("settings/$key").set(formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/bg.jpeg"), fit: BoxFit.cover)),
        child: Container(
          color: Colors.black.withOpacity(0.75),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 15),
                  _buildHeader(),
                  const SizedBox(height: 25), 
                  _buildMainBulb(), 
                  const SizedBox(height: 25), 
                  _buildScheduleCard(),
                  const SizedBox(height: 20), 
                  _buildControlButtons(),
                  const SizedBox(height: 15), 
                  _buildLogHeader(),
                  _buildLogList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(children: [
      const Text("IOT SMART LAMP", style: TextStyle(letterSpacing: 3, fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(time, style: const TextStyle(fontSize: 10, color: Colors.white38)),
    ]);
  }

  Widget _buildMainBulb() {
    return Column(children: [
      Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status 
                  ? Colors.amber.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.05),
              boxShadow: status ? [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 10,
                )
              ] : [],
            ),
          ),
          Icon(
            Icons.lightbulb_rounded, 
            size: 80, 
            color: status 
                ? Colors.amber.withOpacity(0.9) 
                : Colors.white.withOpacity(0.1)
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        status ? "Light is On" : "Light is Off", 
        style: TextStyle(
          fontSize: 26, 
          fontWeight: FontWeight.w900,
          color: status ? Colors.white : Colors.white38
        )
      ),
    ]);
  }

  Widget _buildScheduleCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05), 
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.05))
      ),
      child: Column(
        children: [
          const Text("SET AUTOMATIC SCHEDULE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 2)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _timeItem("POWER ON SCHEDULE", startStr, "startTime"),
              const Icon(Icons.arrow_forward_ios, color: Colors.white10, size: 14),
              _timeItem("POWER OFF SCHEDULE", endStr, "endTime"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeItem(String label, String val, String key) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
      Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      SizedBox(
        height: 26,
        child: TextButton(
          onPressed: () => _changeTime(key),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white10, 
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
          ),
          child: const Text("Change", style: TextStyle(fontSize: 9, color: Colors.amber)),
        ),
      ),
    ]);
  }

  Widget _buildControlButtons() {
    return Row(children: [
      Expanded(
        child: SizedBox(
          height: 45,
          child: ElevatedButton(
            onPressed: () => _sendCommand("OFF"), 
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.05),
              elevation: 0,
            ),
            child: const Text("OFF", style: TextStyle(color: Colors.white70))
          ),
        )
      ),
      const SizedBox(width: 15),
      Expanded(
        child: SizedBox(
          height: 45,
          child: ElevatedButton(
            onPressed: () => _sendCommand("ON"), 
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.withOpacity(0.8), 
              foregroundColor: Colors.black,
            ), 
            child: const Text("ON", style: TextStyle(fontWeight: FontWeight.bold))
          ),
        )
      ),
    ]);
  }

  Widget _buildLogHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Row(
          children: [
            Icon(Icons.history, size: 14, color: Colors.white38),
            SizedBox(width: 8),
            Text("ACTIVITY LOG", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1)),
          ],
        ),
        TextButton(
          onPressed: _clearLogs, 
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          // HAPUS 'const' di sini karena .withOpacity bukan konstanta
          child: Text(
            "Clear Activity", 
            style: TextStyle(
              color: Colors.redAccent.withOpacity(0.8), 
              fontSize: 10, 
              fontWeight: FontWeight.bold
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogList() {
    return Expanded(
      child: logs.isEmpty 
      ? const Center(child: Text("No records", style: TextStyle(color: Colors.white10, fontSize: 12)))
      : ListView.builder(
          itemCount: logs.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, i) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(Icons.circle, size: 6, color: logs[i]["event"].toString().contains("ON") ? Colors.amber.withOpacity(0.7) : Colors.white24),
            title: Text(logs[i]["event"] ?? "-", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            subtitle: Text(logs[i]["time"] ?? "-", style: const TextStyle(fontSize: 9, color: Colors.white38)),
            trailing: Text(logs[i]["mode"] ?? "-", style: TextStyle(fontSize: 9, color: Colors.amber.withOpacity(0.7), fontWeight: FontWeight.bold)),
          ),
        ),
    );
  }
}
