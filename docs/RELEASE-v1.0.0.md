## TV Mirror v1.0.0: Android TV için AirPlay ekran yansıtma alıcısı

Mac ve iPhone'dan sistemin kendi **Ekran Yansıtma** menüsüyle Android TV'ye görüntü ve ses aktarır. Uygulama [jqssun/android-airplay-server](https://github.com/jqssun/android-airplay-server) (`c8defdd`, GPL-3.0) tabanlıdır.

### İmza
APK sabit bir release anahtarıyla imzalı (`CN=TV Mirror`). Sertifika SHA-256:
`ee1786a8d0eca389e65b973f35592038371e259edce9f0514eb370629af8cabf`
Sonraki sürümler de aynı anahtarla imzalanacağı için ayarlar korunarak üzerine kurulabilir (`adb install -r`). Bu sürüm eski CI derlemelerinin yerine kuruluyorsa bir kez kaldır-kur gerekir.

### Kurulum
```
./scripts/30-install.sh tvmirror.apk      # ya da: adb install -r tvmirror.apk
adb shell appops set io.github.fuzun45.tvmirror SYSTEM_ALERT_WINDOW allow
```
İkinci komut, TV açılışından sonra bağlantı geldiğinde görüntünün kendiliğinden ekrana gelmesi için gerekir. `30-install.sh` bu izni kendisi verir. Ayrıntılar için `docs/KURULUM.md`'ye bakın.

### Doğrulanmış cihaz: Vestel `shandao` (MediaTek m7632, Android 14)
| | sonuç |
|---|---|
| Uçtan uca gecikme | ~50–90 ms |
| Akıcılık (1080p) | gelen ≈ gösterilen, düşen kare 0 |
| Bağlan/kopar | 15/15 bağlandı, 15/15 koptu; eski kare kalmadı, crash yok |
| Bellek | 30 dk'da sızıntı yok (PSS ~40 MB, thread/FD sabit) |
| TV açılışı | sunucu otomatik başlıyor, bağlanınca görüntü kendiliğinden geliyor |

Bu TV'de görüntü katmanı GPU'da birleştirildiği için ekrana ulaşan kare sayısı en fazla ~25 fps. Bu yüzden varsayılan ayar **1080p / 30 fps**. Ayrıntılar `docs/PERFORMANS.md`'de.

### Bu upstream'e göre ne değişti
- Ayrı uygulama kimliği (`io.github.fuzun45.tvmirror`) ve "Salon TV" adı
- Oturum başında ve sonunda eski karenin temizlenmesi
- Video yüzeyinin servise bağlanınca yeniden iletilmesi
- `TvMirrorStats` ölçüm logları
- 1080p/30 varsayılanı

### Bilinen kısıtlar
- Netflix gibi DRM'li içeriği Apple, HDCP'siz alıcılara göndermez. Alıcı tarafında bunun çözümü yok.
- Hue Ambilight'ın "ekran" modu ile aynı anda kullanılmaz.

### Başka TV'lerde
Android TV / Google TV, Android 7.0 ve üzeri gerekir. Mac/iPhone "Ekran Yansıtma" menüsünü kullandığı için genel olarak çalışır, ancak yalnızca yukarıdaki TV'de ölçüldü.
- Daha güçlü cihazlarda ayarlardan **Resolution = AUTO** ve **Max FPS = 60** denenebilir.
- Aynı ağda birden fazla TV varsa her birine ayarlardan farklı bir ad verin.
