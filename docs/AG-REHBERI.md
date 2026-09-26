# Ağ Rehberi

## Özet

Vestel shandao TV ve Mac'in AirPlay yansıtması iyi çalışması için ağ ayarları önemlidir. Bu belgede Wi-Fi seçimi, kanallar, gecikmeler ve sorun giderme yer alır.

---

## TV Ağ Konfigürasyonu

### Baseline'dan (Tarih: 2026-09-26)

| Ayar | Değer |
|---|---|
| **5 GHz Kanal** | 5220 MHz (Kanal 44) |
| **Bant Genişliği** | 80 MHz |
| **Standart** | Wi-Fi 5 (802.11ac) |
| **RSSI** | −35 dBm (iyi sinyal) |
| **Link Hızı** | 780–866 Mbps |

### Öneriler

1. **5 GHz Tercih Et** (ortak 2.4 GHz BSSID yerine)
   - Daha az parazit, daha düşük gecikme
   - AirPlay veri akışı 5 GHz'te sorunsuzdur

2. **80 MHz Bant Genişliği** (40 MHz değil)
   - Kanal 44–48 (5 GHz), 149–165 (5 GHz)
   - 80 MHz bant genişliği mümkün ise seç

3. **Sinyal Kalitesi** (RSSI −30 dBm ile −60 dBm arası)
   - −35 dBm mükemmel
   - −60 dBm kabul edilebilir ama marginal
   - −70 dBm veya daha kötü: Yansıtma donabilir

4. **Aynı Ağda Mac ve TV** (ortak SSID)
   - Mac'in bağlı olduğu SSID ile TV'nin bağlı SSID aynı olmalı
   - 5 GHz BSSID'e tertip (farklı bir ağ-ID ile başka 2.4 GHz BSSID varsa, 5 GHz'yi seç)

---

## Mac Ağ Ayarları

### Wi-Fi Seçimi

System Settings → Wi-Fi:

- [ ] 5 GHz cihazını seç (genelde `...5G` veya `-5G` soneksi)
- [ ] TV'yle aynı SSID
- [ ] Otomatik kanal seçimine izin ver veya sabit 5 GHz kanal seç

### Kurulmuş Kanal Kontrolü (Opsiyonel)

```bash
# Mac'in bağlı olduğu kanal
/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep channel
```

Örnek çıktı:
```
channel: 44,80 (5220 MHz)
```

Kanalın TV'nin kanalı ile eşleştiğini doğrula.

### Teşhis

```bash
# Sinyali kontrol et
/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s
```

---

## Ping Test

Yansıtmadan önce bağlantıyı test et:

```bash
ping -c 50 192.168.1.104
```

**Beklenen çıktı** (baseline'dan):

| Metrik | Değer |
|---|---|
| **Min** | 2.6 ms |
| **Ortalama** | 14.9 ms |
| **Max** | 57.1 ms |
| **Stddev** | 17.9 ms |
| **Paket Kaybı** | %0 |

**Yorumlama**:

- ✓ < 30 ms ort → Çok iyi
- ✓ 30–50 ms ort → İyi
- ⚠ 50–100 ms ort → Kabul edilebilir ama jitter olabilir
- ✗ > 100 ms ort → Sorun; ağ sorununu çözmelisin

### Jitter Kaynakları (Mac'te)

Gözlemlenen jitter (stddev 17.9 ms):

- **macOS AWDL** (Airplay, Bluetooth, Wi-Fi Direkti) kanalına geçişi
- **Wi-Fi güç tasarrufu** — aktif Wi-Fi ajan olmadığında RF güç düşer

**Hafifletme**:

```bash
# Wi-Fi güç tasarrufu kapat (kalıcı olarak)
# System Settings → Wi-Fi → Advanced → Power Saving kapalı
# (Enerji tüketimi artar, gecikmeler sabitlenir)

# AWDL hava kiraz yönetimi (komut satırında)
airport_cli=/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport
sudo $airport_cli prefs RequireAdmin=NO
# (Bu hissiyatıdır; AWDL tamamen kontrol edilemez)
```

---

## Router Konfigürasyonu

### 5 GHz Ağını Ayarla

1. **İki Bant Modu**: Aktur (2.4 GHz + 5 GHz işleme izin verir)
   - Etiket: "Dual-Band"

2. **5 GHz Kanalını Sabitle**:
   - Kanał 44 (5220 MHz) veya 149 (5745 MHz)
   - Bant: 80 MHz
   - Not: 160 MHz bazı ülkelerde yasak, çoğu TV'de desteklemez

3. **2.4 GHz'i** (opsiyonel):
   - Eğer varsa kapal tutabilirsin veya TV'yi dışlayabilirsin
   - Çoğu yönlendiriciler iki cihazı aynı SSID'de bağlar ama client kanal seçebilir

### Güvenlik

- **WPA2** veya **WPA3** (WEP/Open değil)
- Güçlü parola (TV'yle aynı)

---

## Latency (Gecikme)

### Yapı

AirPlay yansıtmada ölçülen latency kaynakları:

```
iPhone/Mac (video kodlama)
    ↓ ~50 ms
    Ağ (paket aktarımı)
    ↓ ~10–50 ms (jitter)
    TV (dekodlama + ekran bekleme)
    ↓ ~40–60 ms (vsync senkronizasyonu)
Total: ~100–150 ms ortalama
```

### Baseline'dan Ölçülen

- **Mac → TV Ping**: ort 14.9 ms
- **Mac → TV → Ekran** (tam latency): ölçülmemiş ama ~100 ms tahmin

### Azaltma

- Yüksek kaliteli Wi-Fi 5 GHz (yukarıdaki ayarlar)
- Yakındaki engel-mentes yer (duvar, metal)
- Diğer yüksek bant cihazları kapatma (dosya indirmesi, videoğrafma vb.)

---

## Sorun Giderme

### Yansıtma Donuyor / Çok Kesintili

1. **Ping kontrolü yap**:
   ```bash
   ping -c 50 192.168.1.104
   ```
   - Max > 200 ms veya stddev > 50 ms ise ağ sorunu

2. **5 GHz kanalını kontrol et**:
   ```bash
   # Mac
   /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep channel
   
   # TV (ADB ile)
   adb shell wpa_cli signal_poll
   ```

3. **Router yakınında olmayı dene**:
   - Wi-Fi sinyal gücü (RSSI) kontrol et
   - İdeal: −35 dBm, kabul edilebilir: −60 dBm'ye kadar

4. **Wi-Fi güç tasarrufu** System Settings'te kapalı:
   - Wi-Fi → Advanced → Power Saving kapalı

5. **Kanal çakışması**:
   - Başka cihazlar 5 GHz kanal 44 veya 149'u kullanıyor mu?
   - `airport -s` ile yakındaki ağları kontrol et

### TV Bağlantısını Kaybediyor

1. **DHCP kiralama süresi**:
   ```bash
   adb shell getprop dhcp.wlan0.leasetime
   ```
   Düşük (< 1 saat) ise IP'yi yenileme sorunu olabilir.

2. **Sleep modu ayarları**:
   ```bash
   adb shell settings get global screen_off_timeout
   ```
   Ekran kapanmazsa WLAN tekrar bağlanmayabilir. `00-connect.sh` bağlantıyı yenilemez.

3. **Wi-Fi'yi yeniden başlat**:
   ```bash
   adb shell svc wifi disable && sleep 2 && adb shell svc wifi enable
   ```

### Ses / Video Senkronizasyonu Kapalı

Ağ jitter'ı ses/video senkronizasyonu hatasına neden olabilir:

- Ping jitter'ı 50 ms'nin üzerinde ise ağ bant genişliğini kontrol et
- Başka yüksek-bant cihazları kapatmayı dene

---

## Ethernet (İsteğe Bağlı, USB Dock Gerekli)

Bazı TV'ler USB Ethernet adaptörü destekler:

```bash
adb shell ip addr show
```

`eth0` varsa Ethernet bağlı. İşlev:

- Daha stabil, daha düşük gecikmeli
- Wi-Fi jitter'ını ortadan kaldırır
- Sorunlu Wi-Fi'de yedek

---

## IPv6 (Nadiren Sorun)

Baseline'da IPv4 (192.168.1.104) kullanılır. İpv6 etkinleştirilirse:

- mDNS çok ev sahiplikli adresleri liste alır (IPv4 + IPv6)
- Mac `Salon TV._airplay._tcp.local` çözümünde adresleri seçebilir
- Genelde sorun değil, ama `adb` IPv4'e sabitse karışabilir.

Çözüm: Gerekirse router'da IPv6'yı kapat veya test et.

---

## Referans

- [KURULUM.md](KURULUM.md) — İlk bağlantı
- [TEST-PROTOKOLU.md](TEST-PROTOKOLU.md) — Ağ ile ilgili testler
- **Apple AirPlay**: https://openairplay.github.io/
- **802.11ac (Wi-Fi 5)**: https://en.wikipedia.org/wiki/IEEE_802.11ac

