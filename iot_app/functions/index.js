const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.lampNotification = functions.database
  .ref("/lampu/last_event")
  .onWrite(async (change) => {
    // 1. Ambil data setelah perubahan
    const data = change.after.val();
    
    // Cegah error jika data dihapus (null)
    if (!data) return null;

    const text = data.text || "Perubahan status lampu";
    const mode = data.mode || "UNKNOWN";

    let title = "Smart Lamp";
    let body = text;

    // 2. Logika Penentuan Judul & Isi Notifikasi
    if (mode === "AUTO") {
      title = "⏰ Lampu Otomatis";
      body = text + " (Jadwal)";
    } else if (mode === "MANUAL_APP") {
      title = "📱 Kontrol Aplikasi";
      body = text + " via Aplikasi";
    } else if (mode === "MANUAL_SWITCH") {
      title = "🔘 Saklar Manual";
      body = text + " via Saklar";
    }

    try {
      // 3. Ambil daftar Token FCM dari Database
      const tokenSnapshot = await admin.database().ref("fcm_tokens").once("value");
      
      if (!tokenSnapshot.exists()) {
        console.log("Tidak ada token ditemukan.");
        return null;
      }

      const tokens = Object.keys(tokenSnapshot.val());
      
      // 4. Kirim Notifikasi ke semua perangkat terdaftar
      const response = await admin.messaging().sendToDevice(tokens, {
        notification: {
          title: title,
          body: body,
          sound: "default", // Tambahkan suara default
          clickAction: "FLUTTER_NOTIFICATION_CLICK" // Penting agar App terbuka saat diklik
        }
      });

      console.log(`Notifikasi berhasil dikirim ke ${tokens.length} perangkat.`);
      return response;

    } catch (error) {
      console.error("Gagal mengirim notifikasi:", error);
      return null;
    }
  });
