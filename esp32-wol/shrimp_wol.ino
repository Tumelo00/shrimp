/*
 * Shrimp WOL Aracisi — ESP32 (WROOM, ntfy relay + WiFiManager)
 * Ilk acilista "Shrimp-WOL-Setup" WiFi'ini yayinlar; telefondan baglanip
 * ev WiFi'ini girersin (sifre ESP'de kalir). Sonra ntfy'i dinler, "wake"
 * gelince yerelde Wake-on-LAN gonderir → PC uyanir.
 */
#include <WiFi.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <WiFiManager.h>   // tzapu/WiFiManager

// ---- Kullaniciya ozel (Shrimp uygulamasi uretir / flash sirasinda enjekte eder) ----
// NTFY_TOPIC: Shrimp'in urettigi gizli konu (uygulamada uyandirma kartinda gorunur).
const char* NTFY_TOPIC = "shrimp-wol-DEGISTIR-GIZLI-KONU";
const char* NTFY_HOST  = "ntfy.sh";
// PC_MAC: PC'nin KALICI (permanent) MAC'i — Shrimp/agent raporluyor. Ornek biciminde degistir.
uint8_t     PC_MAC[6]  = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
// ------------------------------------------------------------------------------------

const int LED_PIN = 2;
WiFiUDP udp;

void blink(int n, int ms) { for (int i=0;i<n;i++){digitalWrite(LED_PIN,HIGH);delay(ms);digitalWrite(LED_PIN,LOW);delay(ms);} }

void sendWOL() {
  uint8_t pkt[102];
  for (int i=0;i<6;i++) pkt[i]=0xFF;
  for (int i=1;i<=16;i++) memcpy(&pkt[i*6], PC_MAC, 6);
  IPAddress bcast(255,255,255,255);
  IPAddress ip=WiFi.localIP(), mask=WiFi.subnetMask();
  IPAddress sub(ip[0]|~mask[0], ip[1]|~mask[1], ip[2]|~mask[2], ip[3]|~mask[3]);
  for (int r=0;r<3;r++){
    udp.beginPacket(bcast,9); udp.write(pkt,102); udp.endPacket();
    udp.beginPacket(bcast,7); udp.write(pkt,102); udp.endPacket();
    udp.beginPacket(sub,9);   udp.write(pkt,102); udp.endPacket();
    delay(60);
  }
  Serial.println(">>> WOL magic packet gonderildi (PC uyandiriliyor)");
  blink(8,60);
}

void listenNtfy() {
  WiFiClientSecure client; client.setInsecure();
  Serial.printf("ntfy baglaniliyor: %s/%s\n", NTFY_HOST, NTFY_TOPIC);
  if (!client.connect(NTFY_HOST, 443)) { Serial.println("ntfy baglanamadi, tekrar"); delay(3000); return; }
  client.print(String("GET /")+NTFY_TOPIC+"/raw HTTP/1.1\r\nHost: "+NTFY_HOST+
               "\r\nUser-Agent: shrimp-wol-esp32\r\nConnection: keep-alive\r\n\r\n");
  while (client.connected()) { String l=client.readStringUntil('\n'); if (l=="\r"||l.length()==0) break; }
  Serial.println("ntfy dinleniyor (Shrimp'ten 'wake' bekleniyor)");
  String buf=""; unsigned long last=millis();
  while (client.connected() && WiFi.status()==WL_CONNECTED) {
    while (client.available()) {
      buf += (char)client.read();
      if (buf.length()>512) buf = buf.substring(buf.length()-64);
      if (buf.indexOf("wake")>=0) { sendWOL(); buf=""; }
      last = millis();
    }
    delay(30);
    if (millis()-last > 540000UL) { Serial.println("stream sessiz, yenileniyor"); break; }
  }
  client.stop();
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  delay(300);
  Serial.println("\n=== Shrimp WOL Aracisi (ESP32/ntfy) ===");
  blink(3,120);
  WiFiManager wm;
  wm.setConfigPortalBlocking(true);
  wm.setConfigPortalTimeout(0);   // kaydedilene kadar 'Shrimp-WOL-Setup' AP'si acik kalir
  Serial.println("WiFi kurulumu: telefondan 'Shrimp-WOL-Setup' agina baglan, ev WiFi'ini gir.");
  if (!wm.autoConnect("Shrimp-WOL-Setup")) { Serial.println("WiFi baglanamadi, yeniden"); delay(1000); ESP.restart(); }
  Serial.print("WiFi tamam. IP: "); Serial.println(WiFi.localIP());
  digitalWrite(LED_PIN, HIGH);
}

void loop() {
  if (WiFi.status()!=WL_CONNECTED) { digitalWrite(LED_PIN,LOW); WiFi.reconnect(); delay(2500); return; }
  listenNtfy();
  delay(1500);
}
