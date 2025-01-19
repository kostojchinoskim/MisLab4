import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/exam_model.dart';
import '../widgets/widget_location_picker.dart';
import 'location.dart';

class CalendarScreen extends StatefulWidget {
  final Function(bool) onThemeToggle;

  CalendarScreen({required this.onThemeToggle});
  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  LatLng? _selectedLocation;
  Map<DateTime, List<Exam>> _events = {};
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  Set<String> notifiedExams = Set();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _startLocationMonitoring();
  }

  Future<void> _initializeNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'reminder_channel',
      'Location Reminders',
      description: 'Notifications for location-based reminders',
      importance: Importance.high,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
    flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }
  }

  void _startLocationMonitoring() async {
    bool locationPermissionGranted = await _checkLocationPermission();
    if (!locationPermissionGranted) return;

    Timer.periodic(Duration(minutes: 1), (timer) {
      _checkLocationReminders();
    });
  }

  Future<bool> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkLocationReminders() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    LatLng userLocation = LatLng(position.latitude, position.longitude);

    _events.forEach((date, exams) {
      for (var exam in exams) {
        if (exam.isLocationReminderEnabled) {
          final distance = Geolocator.distanceBetween(
            userLocation.latitude,
            userLocation.longitude,
            exam.latitude,
            exam.longitude,
          );

          if (distance <= 500 && !notifiedExams.contains(exam.name)) {
            _showNotification(exam.name, exam.location);
            notifiedExams.add(exam.name);
          }
        }
      }
    });
  }

  void _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Location Reminders',
      channelDescription: 'Notifications for location-based reminders',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  void _addExam() {
    if (_selectedDay == null) return;

    TextEditingController nameController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool isLocationReminderEnabled = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Add a new exam"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: "Subject Name",
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (pickedTime != null) {
                        setState(() {
                          selectedTime = pickedTime;
                        });
                      }
                    },
                    icon: Icon(Icons.access_time),
                    label: Text("Pick a time"),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final selectedLocation = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LocationPickerWidget(),
                        ),
                      );
                      if (selectedLocation != null) {
                        setState(() {
                          _selectedLocation = selectedLocation;
                        });
                      }
                    },
                    icon: Icon(Icons.location_on),
                    label: Text("Pick Location"),
                  ),
                  SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Activate location reminder'),
                    value: isLocationReminderEnabled,
                    onChanged: (value) {
                      setState(() {
                        isLocationReminderEnabled = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty &&
                        _selectedLocation != null) {
                      setState(() {
                        final exam = Exam(
                          name: nameController.text,
                          location:
                          "${_selectedLocation!.latitude}, ${_selectedLocation!.longitude}",
                          dateTime: DateTime(
                            _selectedDay!.year,
                            _selectedDay!.month,
                            _selectedDay!.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          ),
                          latitude: _selectedLocation!.latitude,
                          longitude: _selectedLocation!.longitude,
                          isLocationReminderEnabled: isLocationReminderEnabled,
                        );
                        _events[_selectedDay!] = (_events[_selectedDay!] ?? [])
                          ..add(exam);
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEventList() {
    if (_selectedDay == null) {
      return Center(child: Text('Select a date to view events.'));
    }

    final events = _events[_selectedDay] ?? [];
    if (events.isEmpty) {
      return Center(child: Text('No exams scheduled for this day.'));
    }

    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final exam = events[index];
        return Card(
          margin: EdgeInsets.symmetric(vertical: 8.0),
          child: ListTile(
            title: Text(exam.name),
            subtitle: Text(
              '${exam.location} | ${exam.dateTime.hour}:${exam.dateTime.minute}',
            ),
            trailing: Icon(Icons.map, color: Colors.indigo),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LocationScreen(exam: exam),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Exam Calendar'),
        centerTitle: true,
        actions:[
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: (){
              widget.onThemeToggle(!isDarkMode);
            },
          )
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            calendarStyle: CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              defaultTextStyle: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge!.color,
              ),
              weekendTextStyle: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge!.color?.withOpacity(0.6),
              ),
            ),
            headerStyle: HeaderStyle(
              titleTextStyle: TextStyle(
                color: Theme.of(context).textTheme.titleLarge!.color,
              ),
              formatButtonTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            eventLoader: (day) {
              return _events[day] ?? [];
            },
            calendarFormat: _calendarFormat,
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
          ),
          Expanded(child: _buildEventList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExam,
        child: Icon(Icons.add),
      ),
    );
  }
}
