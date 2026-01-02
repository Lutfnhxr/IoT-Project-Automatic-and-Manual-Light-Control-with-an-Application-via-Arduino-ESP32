import 'package:firebase_database/firebase_database.dart';

class DBInit {
  static final db = FirebaseDatabase.instance.ref();

  static Future<void> init() async {
    final snapshot = await db.child("lampu").get();

    if (!snapshot.exists) {
      await db.set({
        "lampu": {
          "status": false,
          "mode": "MANUAL",
          "last_event": "Belum ada aktivitas",
          "time": "00:00"
        },
        "command": {
          "value": "NONE"
        },
        "schedule": {
          "enabled": false,
          "on": "17:45",
          "off": "03:30"
        }
      });
    }
  }
}
