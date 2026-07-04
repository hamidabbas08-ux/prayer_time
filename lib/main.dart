import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:adhan/adhan.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void playAdhanAlarm() async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}

  final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/launcher_icon');
      
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
      
  await notificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'azan_channel_v10',
    'Official Azan Alarms',
    importance: Importance.max,
    priority: Priority.high,
    sound: RawResourceAndroidNotificationSound('azan'), 
    playSound: true,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await notificationsPlugin.show(
    100,
    'Prayer Time / وقتِ نماز',
    'It is time for prayer. Allaho Akbar.',
    platformChannelSpecifics,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  runApp(const PrayerTimeApp());
}

class PrayerTimeApp extends StatelessWidget {
  const PrayerTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prayer Time',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const PrayerTimeHomeScreen(),
    );
  }
}

class PrayerTimeHomeScreen extends StatefulWidget {
  const PrayerTimeHomeScreen({super.key});

  @override
  State<PrayerTimeHomeScreen> createState() => _PrayerTimeHomeScreenState();
}

class _PrayerTimeHomeScreenState extends State<PrayerTimeHomeScreen> {
  String locationStatus = "Fetching Location...";
  Map<String, String> prayerTimesMap = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initAutoLocationAndCalculations();
  }

  Future<void> _initAutoLocationAndCalculations() async {
    try {
      // 1. لوکیشن پرمیشن چیک اور ریکویسٹ
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _loadFallbackTimes("Permission Denied");
          return;
        }
      }

      // 2. آٹو نوٹیفیکیشن پرمیشن پاپ اپ (جدید اینڈرائیڈ کے لیے)
      final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();
      await notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      Position? position = await Geolocator.getLastKnownPosition();
      
      position ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

      _calculateTimesForPosition(position, "GPS Connected");

    } catch (e) {
      _loadFallbackTimes("Offline Mode");
    }
  }

  void _calculateTimesForPosition(Position position, String statusType) {
    final coordinates = Coordinates(position.latitude, position.longitude);
    final params = CalculationMethod.muslim_world_league.getParameters();
    params.madhab = Madhab.shafi; 

    final dateTime = DateTime.now();
    final prayerTimes = PrayerTimes(coordinates, DateComponents.from(dateTime), params);

    String formatTime(DateTime time) {
      int hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
      String minute = time.minute.toString().padLeft(2, '0');
      String period = time.hour >= 12 ? "PM" : "AM";
      return "$hour:$minute $period";
    }

    setState(() {
      locationStatus = "$statusType • Lat: ${position.latitude.toStringAsFixed(2)}, Lon: ${position.longitude.toStringAsFixed(2)}";
      prayerTimesMap = {
        "Fajr / فجر": formatTime(prayerTimes.fajr),
        "Shurooq / شروق": formatTime(prayerTimes.sunrise),
        "Dhuhr / ظہر": formatTime(prayerTimes.dhuhr),
        "Asr / عصر": formatTime(prayerTimes.asr),
        "Maghrib / مغرب": formatTime(prayerTimes.maghrib),
        "Isha / عشاء": formatTime(prayerTimes.isha),
      };
      isLoading = false;
    });

    _scheduleSystemAlarm(prayerTimes.timeForPrayer(prayerTimes.nextPrayer()) ?? dateTime.add(const Duration(hours: 2)));
  }

  void _loadFallbackTimes(String statusType) {
    Position fallbackPosition = Position(
      latitude: 24.21, longitude: 55.74, 
      timestamp: DateTime.now(), accuracy: 0, altitude: 0, 
      heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
    );
    _calculateTimesForPosition(fallbackPosition, "$statusType (Using Saved GPS)");
  }

  Future<void> _scheduleSystemAlarm(DateTime alarmTime) async {
    await AndroidAlarmManager.oneShotAt(
      alarmTime,
      1,
      playAdhanAlarm,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      alarmClock: true, 
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PRAYER TIMES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal, width: 1),
                    ),
                    child: Column(
                      children: [
                        const Text("CURRENT LOCATION", style: TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(locationStatus, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      children: [
                        _buildPrayerCard("Fajr / فجر", prayerTimesMap["Fajr / فجر"]!, Colors.indigo[900]!),
                        _buildPrayerCard("Shurooq / شروق", prayerTimesMap["Shurooq / شروق"]!, Colors.amber[800]!),
                        _buildPrayerCard("Dhuhr / ظہر", prayerTimesMap["Dhuhr / ظہر"]!, Colors.blue[700]!),
                        _buildPrayerCard("Asr / عصر", prayerTimesMap["Asr / عصر"]!, Colors.orange[900]!),
                        _buildPrayerCard("Maghrib / مغرب", prayerTimesMap["Maghrib / مغرب"]!, Colors.red[900]!),
                        _buildPrayerCard("Isha / عشاء", prayerTimesMap["Isha / عشاء"]!, Colors.blueGrey[900]!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPrayerCard(String title, String time, Color cardColor) {
    return Card(
      color: cardColor,
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(time, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
