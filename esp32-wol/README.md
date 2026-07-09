# Shrimp WOL Aracısı (ESP32)

PC'nin bulunduğu yerel ağda sürekli açık kalan küçük bir ESP32. Shrimp (Mac) uzaktan
`ntfy.sh`'e "wake" yollar, ESP32 bunu duyar ve **yerelde** Wake-on-LAN magic packet
göndererek PC'yi uyandırır. Böylece PC kapalıyken bile, farklı ağdan/mobil bağlantıdan
uyandırma çalışır (WOL paketi internetten geçemez — bu yüzden yerel bir aracı şart).

## Neden gerekli?
WOL "magic packet" bir **Layer-2 broadcast**'idir; sadece PC ile **aynı yerel ağdan**
NIC'e ulaşır. Kapalı PC'de OS/Tailscale çalışmaz, dolayısıyla internetten yönlendirilen
paket ulaşamaz. ESP32 aracı, uzaktan gelen komutu (ntfy) alıp WOL'u **PC'nin yanında**
üretir.

## Akış
- **Evde (aynı ağ):** Shrimp doğrudan WOL broadcast yollar — ESP32'ye bile gerek yok.
- **Uzakta:** Shrimp → ntfy.sh (gizli konu) → ESP32 (abone) → yerelde WOL → PC uyanır.

## Kurulum
1. **Arduino IDE**'de ESP32 board paketini kur (Boards Manager → "esp32" by Espressif).
2. Kart: **ESP32 Dev Module** (ya da kartının modeli).
3. `shrimp_wol.ino` içinde **3 satırı** doldur:
   - `WIFI_SSID` — PC'nin bağlı olduğu WiFi adı
   - `WIFI_PASS` — WiFi şifresi
   - `NTFY_TOPIC` — Shrimp'in ürettiği **gizli** konu. Shrimp'te uyandırma kartının
     "başarısız" ekranında görünür; oradan kopyala. (Kimseyle paylaşma.)
   - `PC_MAC` — PC'nin **kalıcı (permanent)** MAC'i. Shrimp/agent bunu raporluyor
     (Shrimp PC kartında görünür). `xx, 0xEB, ...` biçiminde gir.
4. **Yükle** (Upload). Seri Monitör (115200 baud) durumu gösterir.
5. ESP32'yi PC ile **aynı ağa** bağlı ve **sürekli açık** tut (USB güç adaptörü yeter).

## LED
- Açılışta 3 kez yanıp söner.
- WiFi bağlıyken sabit yanar.
- WOL gönderince 8 kez hızlı yanıp söner.

## Güvenlik / gizlilik
- ntfy.sh ücretsiz ve hesapsız. Konu adı **gizli anahtar** gibidir — kimseyle paylaşma.
  (Bilen biri en fazla PC'ni uyandırabilir; Shrimp token'ı olmadan bağlanamaz.)
- Yalnızca "wake" metni gider; kişisel veri yok.
- İstersen kendi ntfy sunucunu barındırıp `NTFY_HOST`'u değiştir.

## Test
Kart açıkken PC'yi uykuya/kapat, sonra başka bir ağdan (mobil hotspot) Shrimp'i aç —
uyandırma kartı çıkar, ESP32 seri monitöründe ">>> WOL ... gonderildi" görünür, PC açılır.
