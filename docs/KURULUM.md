# Kurulum ve Başlangıç Rehberi

## Ön Gereksinimler

### Cihaz Gereksiyor
- **Vestel Android TV** (shandao, Android 14 API 34, MediaTek m7632)
- **TV'de Geliştirici Seçenekleri** etkinleştirmiş ve ağ hata ayıklaması (ADB) açık
- **IP Adres**: 192.168.1.104:5555 (Wi-Fi 5 GHz üzerinden)

### Mac Gereksiyor
- **adb** (Android Debug Bridge) kurulu: `/opt/homebrew/share/android-commandlinetools/platform-tools/adb`
  - Alternatif: ortam değişkeni `ADB` ile farklı konumu belirtin
- **Python 3** (ölçüm araçları için)
- **unzip** (APK artifact'ı açmak için)
- **Wi-Fi bağlantı**: Aynı 5 GHz ağında (önerilir) veya Ethernet

### iOS/iPadOS (Yansıtma için)
- Aynı Wi-Fi ağında bağlı iPhone veya iPad

## Depo Klonla

```bash
git clone https://github.com/fuzun45/AndroidTV_AppleScreenShare.git
cd AndroidTV_AppleScreenShare
```

> **Uyarı**: Bu depoyu iCloud senkronizasyonlu bir klasörde (örn. Desktop) açmayın. Mac'in iCloud git işlemleri zaman aşımı hatası verebilir. Bunun yerine `~/Developer` gibi lokal bir klasör kullanın.

## Bağlantı Kur

TV'yi bağlantı havuzunda yoksa ekle:

```bash
adb connect 192.168.1.104:5555
```

Bağlantıyı doğrula:

```bash
./scripts/00-connect.sh
```

Başarılı olursa cihaz bilgilerini (model, Android sürümü, API düzeyi vb.) yazdırır.

## Baseline Kopyası (İsteğe Bağlı)

TV'nin mevcut durumunu kaydet (bellek, ağ, decoder'lar vb.):

```bash
./scripts/10-baseline.sh
```

Çıktı: `out/baseline/BASELINE-SUMMARY.md`

## APK İndir ve Kur

### Seçenek 1: GitHub Actions Artifact'ından (Önerilen)

1. [GitHub Actions](https://github.com/fuzun45/AndroidTV_AppleScreenShare/actions) sayfasına git
2. En son başarılı `apk` workflow'unu aç
3. `tvmirror-<commit>` artifact'ını indir (ZIP dosyası)
4. Kur:

```bash
./scripts/30-install.sh /path/to/tvmirror-<commit>.zip
```

Script otomatik olarak:
- ZIP'i açar
- `tvmirror.apk`'yı bulur
- Eski APK'yı kaldırır (gerekirse)
- Yeni sürümü yükler
- Uygulamayı başlatır

> **Hata ayıklama İmzası**: GitHub Actions APK'ı (release keystore'u olmadan) hata ayıklama imzasıyla kaydeder. Eski sürümden güncelliyorsan ve imza farklıysa script kaldırıp yeniden kuracak.

### Seçenek 2: APK Dosyasını Doğrudan Kur

APK dosyası varsa:

```bash
./scripts/30-install.sh /path/to/tvmirror.apk
```

### Seçenek 3: Artifact Dizininden

ZIP'i açıp klasör adıyla kur:

```bash
./scripts/30-install.sh --from-artifact /path/to/tvmirror-<commit>/
```

### Seçenek 4: Downloads Klasöründen (Varsayılan)

APK yolu vermezsen script en yeni `tvmirror-*.zip`'i `~/Downloads/`'de arar:

```bash
./scripts/30-install.sh
```

## Sabit İmza Anahtarı (bir kez, önerilir)

CI'da `RELEASE_KEYSTORE_B64` secret'ı tanımlı değilse APK, her GitHub makinesinde yeniden üretilen bir debug anahtarıyla imzalanır. Bu durumda her güncellemede şunlar olur:
- `adb install -r` `INSTALL_FAILED_UPDATE_INCOMPATIBLE` hatası verir, kaldır-kur gerekir.
- Uygulama ayarları silinir.
- "Bağlanınca ekrana gel" izni (`SYSTEM_ALERT_WINDOW`) sıfırlanır. `30-install.sh` bu izni yeniden verir.

Anahtarı Mac'te bir kez üret ve GitHub'a secret olarak ekle:

```bash
keytool -genkeypair -keystore ~/tvmirror-release.jks -alias tvmirror \
  -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=TV Mirror"
base64 -i ~/tvmirror-release.jks | pbcopy   # panoya kopyalar
```

GitHub → depo → Settings → Secrets and variables → Actions → New repository secret:

| Ad | Değer |
|---|---|
| `RELEASE_KEYSTORE_B64` | panodaki base64 metin |
| `RELEASE_STORE_PASSWORD` | keytool'a verdiğin parola |
| `RELEASE_KEY_ALIAS` | `tvmirror` |
| `RELEASE_KEY_PASSWORD` | keytool'a verdiğin parola (anahtar parolası ayrı sorulmadıysa aynısı) |

- Sonraki ilk kurulumda bir kez daha kaldır-kur gerekir, çünkü imza değişiyor. Ondan sonraki tüm güncellemeler `adb install -r` ile ayarlar korunarak kurulur.
- `~/tvmirror-release.jks` dosyasını ve parolayı sakla; depoya ekleme.

## Kurulumu Doğrula

```bash
./scripts/40-verify.sh
```

Kontrol listesi:
- ✓ Paket yüklenmiş mi
- ✓ İşlem çalışıyor mu
- ✓ Port 7000 açık mı
- ✓ AirPlay hizmeti mDNS'de görünüyor mu
- ✓ TCP bağlantı başarılı mı

Başarısız olursa `scripts/70-capture-issue.sh` ile tanı yakalayabilirsin.

## Kullan

### Yansıtmayı Başlat

1. **iPhone/iPad**: Kontrol Merkezi → Ekran Yansıtma → **"Salon TV"** seç
2. **Mac**: Menü Çubuğu → Ekran Yansıtma → **"Salon TV"** seç

Varsayılan ayarlar:
- **Çözünürlük**: 1920x1080 (1080p)
- **Kare hızı**: En fazla 30 fps

### Ayarları Değiştir

TV Mirror uygulamasını aç (TV'de oturmak gerekli değil):

```bash
adb shell am start -n io.github.fuzun45.tvmirror/.MainActivity
```

**Çözünürlük** (Resolve) ayarı:
- `1920x1080` — 1080p (önerilen, 25 fps tavan)
- `3840x2160` — 4K (otomatik, 25 fps tavan, GPU compositor nedeniyle)

**Kare hızı** (FPS):
- Ağ ve GPU'ya göre otomatik ayarlanır
- El ile 30 fps'e kadar değiştirebilirsin

## Ayarları Sıfırla

Ayarlar uygulamada kayıtlı. Varsayılana dönmek için:

```bash
adb shell pm clear io.github.fuzun45.tvmirror
```

Ardından uygulamayı yeniden başlat.

## Kaldır

Uygulamayı TV'den kaldır:

```bash
adb shell pm uninstall io.github.fuzun45.tvmirror
```

ADB'yi kapat (güvenlik):

```bash
adb disconnect 192.168.1.104:5555
```

TV'de Geliştirici Seçenekleri → Ağ hata ayıklaması'nı kapat.

## Sorun Giderme

### Yansıtma Başlamıyor

1. iPhone/Mac'ten Kontrol Merkezi'nde "Salon TV"'yi görmüyor musun?
   - TV'de TV Mirror uygulamasını aç
   - Mac Wi-Fi'yi kapatıp aç
   - TV'yi yeniden başlat

2. Uygulamada tanı yakala:

```bash
./scripts/70-capture-issue.sh "baslama-sorunu"
```

Çıktı: `out/issue-baslama-sorunu/` (loglar, portlar, servisler)

### Kare Takılması / Donuş

Eski APK cachelenmiş olabilir. Temizle:

```bash
adb shell pm clear io.github.fuzun45.tvmirror
```

Ardından uygulamayı yeniden başlat.

### Netflix / DRM İçeriği Yansıtılamıyor

Apple, HDCP sertifikası olmayan AirPlay alıcılarına DRM korumalaşı içeriği göndermez. Bu bir TV Mirror sınırlaması değil, AirPlay protokolünün tasarımıdır. **Çözüm yok**.

---

**Sonraki adımlar**: Performans ve sızıntı testleri için [TEST-PROTOKOLU.md](TEST-PROTOKOLU.md) ve [PERFORMANS.md](PERFORMANS.md) bak.
