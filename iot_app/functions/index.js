const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.pushLampu = functions.database
  .ref("/lampu/last_event")
  .onWrite(async (change, context) => {
    const msg = change.after.val();
    
    // Jangan kirim notifikasi jika data dihapus atau pesan kosong
    if (!msg || msg === "") return null;

    // Ambil token FCM dari database
    const snap = await admin.database().ref("fcm_tokens").once("value");
    const tokensData = snap.val();
    
    if (!tokensData) {
      console.log("Tidak ada token ditemukan.");
      return null;
    }

    const tokens = Object.keys(tokensData);
    if (tokens.length === 0) return null;

    const payload = {
      notification: {
        title: "Smart Lamp",
        body: msg,
      },
    };

    try {
      const response = await admin.messaging().sendToDevice(tokens, payload);
      console.log("Notifikasi terkirim:", response.successCount);
    } catch (error) {
      console.error("Gagal mengirim notifikasi:", error);
    }
    
    return null;
  });