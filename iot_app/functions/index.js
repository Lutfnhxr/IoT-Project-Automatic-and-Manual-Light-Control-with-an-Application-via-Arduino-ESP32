const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.lampNotification = functions.database
  .ref("/lampu/status")
  .onUpdate(async (change) => {
    const after = change.after.val(); // Status sekarang (true/false)
    const before = change.before.val(); // Status sebelumnya

    // 1. Hanya kirim jika status benar-benar berubah (mencegah loop/notif ganda)
    if (after === before) return null;

    const title = after ? "💡 Light ON" : "🌑 Light OFF";
    const body = after ? "The Smart Lamp system detects the Light is ON." : "The Smart Lamp system detects the Light is OFF.";

    try {
      // 2. Ambil semua token perangkat yang terdaftar di database
      const tokenSnapshot = await admin.database().ref("fcm_tokens").once("value");
      if (!tokenSnapshot.exists()) {
        console.log("No device tokens found in /fcm_tokens");
        return null;
      }

      const tokens = Object.keys(tokenSnapshot.val());

      // 3. Susun pesan notifikasi dengan standar modern (V1 SDK)
      const message = {
        tokens: tokens,
        notification: {
          title: title,
          body: body,
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            // Channel ID harus sama persis dengan di AndroidManifest & main.dart
            channelId: "smart_lamp_channel", 
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        // Agar notifikasi muncul juga di iOS jika nantinya dikembangkan
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      };

      // 4. Kirim ke semua perangkat sekaligus
      const response = await admin.messaging().sendEachForMulticast(message);
      
      console.log(`Successfully sent ${response.successCount} notifications.`);
      
      // Opsional: Bersihkan token yang sudah tidak aktif (expired)
      if (response.failureCount > 0) {
        console.log(`${response.failureCount} tokens failed.`);
      }

      return null;
    } catch (error) {
      console.error("Error sending notification:", error);
      return null;
    }
  });
