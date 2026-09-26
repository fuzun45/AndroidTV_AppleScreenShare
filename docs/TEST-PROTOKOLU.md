# Test Protokolü ve Kabul Kriterleri

## Özet

Bu dokümanda yansıtmanın **kararlı ve kullanılabilir** olduğunu doğrulamak için adımlar ve kontrol listesi yer alır.

## Kabul Kriterleri ("Hatasız")

Aşağıdaki koşullar sağlanırsa sistemin hatasız çalıştığı kabul edilir:

| Ölçüm | Hedef |
|---|---|
| Mac yansıtması | 30–60 dakika sürekli, sorunsuz |
| iPhone yansıtması | 30–60 dakika sürekli, sorunsuz |
| Bağlantı/bağlantı kesme | 20 döngü, çökme yok |
| Soğuk başlangıç | 5 kez kapanıp açma, sorun yok |
| Dönerken / Uygulamalar arası geçiş | 10 kez, takılma yok |
| Çökme / ANR / Donmuş Kare | 0 olay |
| Bellek sızıntısı | LEAK.md PASS |
| Ses/Video senkronizasyonu | < ~100 ms sapma |
| Latency (gecikme) | < ~200 ms |

## Test Adımları

### Aşama 1: Kurulum (30 dakika)

Tamamlamadıysan [KURULUM.md](KURULUM.md) izle.

```bash
./scripts/00-connect.sh     # Bağlantı doğru mu?
./scripts/10-baseline.sh    # Cihaz yapısını kaydet
./scripts/30-install.sh     # APK kur
./scripts/40-verify.sh      # Sistem hazır mı?
```

Beklenen çıktı: 4 adımda hata olmaksızın tamamlanır.

### Aşama 2: Performans Ölçümü (90 dakika)

Mac'ten 1080p varsayılanı kullanarak:

#### Test 1: Mac Yansıtması — 30 dakika

```bash
# Terminal A: Ölçümü başlat
./scripts/50-perf-capture.sh "mac-30min" 1800

# Terminal B (ölçüm bekliyorken): iPhone/Mac'ten yansıtmayı aç
# Mac: Menü Çubuğu → Ekran Yansıtma → "Salon TV"
# veya
# iPhone: Kontrol Merkezi → Ekran Yansıtma → "Salon TV"

# Yansıtmanız boyunca aktif tutun:
# - Video oynat (YouTube, harita, vb.)
# - Sayfaları kaydır
# - Uygulamalar arası geç
# - Ekranı döndür (yatay ↔ dikey)
```

**Beklenen sonuçlar** (`out/perf-mac-30min/`):

| Metrik | Hedef |
|---|---|
| `in_fps` | ~25 fps |
| `presented` | ~25 fps |
| Kare kaybı | < %5 |
| HWC Comp Type | CLIENT (bilinen sınır) |
| CPU medyanı | < %40 |
| Kırılma | 0 |

#### Test 2: iPhone Yansıtması — 30 dakika

```bash
./scripts/50-perf-capture.sh "iphone-30min" 1800

# Terminal B: iPhone'dan yansıtmayı başlat
# Kontrol Merkezi → Ekran Yansıtma → "Salon TV"
```

**Beklenen sonuçlar**: Test 1 ile benzer.

#### Test 3: Bağlantı/Bağlantı Kesme Döngüleri (20x)

```bash
./scripts/60-soak.sh connect-cycles 20
```

Her döngü:
1. Yansıtmayı kapat
2. TV Mirror'ı yeniden başlat
3. Yansıtmayı tekrar aç

**Başarı kriterleri**:
- Hiç çökme / ANR (Application Not Responding)
- Hiç "stale frame" (donmuş kare)
- Loglar temiz (`out/soak-connect-cycles/SOAK.md`)

### Aşama 3: Soğuk Başlangıç (30 dakika)

```bash
./scripts/60-soak.sh boot-cycles 5
```

Her döngü:
1. TV'yi kapat
2. 30 saniye bekle
3. TV'yi aç
4. TV Mirror uygulamasını başlat
5. Yansıtmayı aç ve 30 saniye çalıştır

**Başarı kriterleri**: Çökme, ANR, latency sıçraması yok.

### Aşama 4: Bellek Sızıntısı (60+ dakika)

Senaryo seçin:

#### Senaryo A: Uzun Mac Yansıtması (Önerilen)

Terminal A: Ölçümü başlat
```bash
PHASE=mac ./scripts/65-leak-watch.sh 60 60
```

Terminal B: Yansıtmayı 60 dakika açık tut
```bash
# Mac'ten yansıtmayı başlat ve açık bırak
# (Ölçüm otomatik olarak kapanır)
```

**Beklenen sonuç**: `out/leak-mac/LEAK.md` — PASS

#### Senaryo B: Connect/Disconnect Döngüleri (Paralel)

Terminal A: Sızıntı izle
```bash
PHASE=cycles ./scripts/65-leak-watch.sh 60 30
```

Terminal B: Bağlantı döngüleri
```bash
./scripts/60-soak.sh connect-cycles 15
```

Terminal A ve B'nin bitmesini bekle.

**Beklenen sonuç**: `out/leak-cycles/LEAK.md` — PASS

#### Senaryo C: Boş Beklemede Uzun Süre (Opsiyonel)

Gece boyunca:
```bash
PHASE=idle ./scripts/65-leak-watch.sh 480 300
```

(480 dakika, 5 dakikalık aralıklarla örnek)

### Aşama 5: Ses/Video Senkronizasyonu (15 dakika)

YouTube'de 1-2 dakikalık video oynat (ses akarsı mükemmel):

```bash
./scripts/50-perf-capture.sh "sync-test" 120
```

Logları aç:

```bash
cat out/perf-sync-test/logcat-during.txt | grep -i 'TvMirrorStats\|latency\|sync\|jitter'
```

**Başarı kriterleri**:
- Ses ve görüntü kişisel olarak birlikte hareket ediyor
- Labda ölçülmüş latency < ~100 ms

## Sonuç Tablosu

Tüm testler tamamlandıktan sonra doldur:

| Test | Durum | Tarih | Notlar |
|---|---|---|---|
| Kurulum (40-verify) | PASS / FAIL | | |
| Mac 30 min (50-perf) | PASS / FAIL | | |
| iPhone 30 min (50-perf) | PASS / FAIL | | |
| Connect-cycles 20x (60-soak) | PASS / FAIL | | |
| Boot-cycles 5x (60-soak) | PASS / FAIL | | |
| Bellek sızıntısı (65-leak) | PASS / FAIL | | |
| A/V senkron | Tamam / Bekliyor | | |
| **Genel Sonuç** | **PASS / FAIL** | | |

## Sorun Bulunursa

Hatanın türünü belirle:

- **Çökme / ANR**: `out/*/crash-buffer-*.txt` ve logcat'te açıklama aç
- **Kare kaybı / Takılma**: `out/*/jank.txt` ve HWC type kontrol et (CLIENT = GPU, sınırlı)
- **Bellek sızıntısı**: `out/leak-*/LEAK.md` sorun kaynağını göster
- **Latency regresyonu**: `out/perf-*/logcat-*.txt` araştır

Bulunmuş sorunlar `devices/vestel-shandao/ISSUES.md` gibi bir dosyada kütüphane oluştur.

---

**Sonraki**: Performans ayrıntıları için [PERFORMANS.md](PERFORMANS.md) bak; güvenlik için [GUVENLIK.md](GUVENLIK.md).
