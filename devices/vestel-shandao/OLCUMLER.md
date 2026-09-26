# Vestel `shandao` — yansıtma ölçümleri

Her satır `scripts/50-perf-capture.sh` ile alındı (requested → received → decoded → presented).

## M1 — upstream varsayılanları, Mac, 2026-09-26 (120 sn, YouTube)

| req | recv | codec / decoder | in_fps | dec_fps | presented | video Comp Type | missed Δ |
|---|---|---|---|---|---|---|---|
| 3840x2160@60 | 3840x2160 | H.264 / `OMX.MS.AVC.Decoder` | 40.3 | 40.3 | NA¹ | NA¹ | 1 |

- Ses: AAC-ELD
- Uygulama CPU medyanı: %25 (tek çekirdek ölçeği)
- PSS: 86 → 61 MB, tepe 86 MB
- Swap: 120 sn'de pswpout +15.5k sayfa (~60 MB)
- RSSI: −38 ile −35 arası

Kullanıcı gözlemi:
- Görüntü ve ses geldi, YouTube hafif kastı.
- iPhone yansıtması çalıştı (X, YouTube).
- Mac'ten Netflix yansıtılamadı.

Yorum:
- `Resolution = AUTO` panelin 4K'sını istiyor. Mac 4K **H.264** gönderiyor ve ~40 fps'te kalıyor.
- in = dec: TV decoder'ı gelen her kareyi çözüyor. Darboğaz gönderici tarafında (4K H.264 kodlama) ya da akış düzensizliğinde.
- HEVC pazarlık edilmedi; sebep log'dan doğrulanacak.
- Netflix: Apple, DRM'li içeriği HDCP sertifikası olmayan AirPlay alıcılarına göndermiyor. Alıcı tarafında çözümü yok.

¹ Ölçüm aracı alıcının SurfaceView katmanını adıyla bulamadı; seçici düzeltiliyor.

## M2: upstream GL hattı, Mac, AUTO, 2026-09-26 13:28 (120 sn)

| req | recv | codec / decoder | in_fps | dec_fps | presented | video Comp Type | missed Δ |
|---|---|---|---|---|---|---|---|
| 3840x2160@60 | 3840x2160 | H.264 / `OMX.MS.AVC.Decoder` | 43 | 43 | NA² | **CLIENT** | 0 |

- Seçilen katman: `SurfaceView[io.github.fuzun45.tvmirror/io.github.jqssun.airplay.MainActivity](BLAST)#55162`
- Uygulamanın ana penceresi de CLIENT.
- CPU medyanı %32.5; PSS 62–69 MB; swap-out 0.

**Karar (plan adım 6):** Video katmanı GPU kompozisyonunda. Hue projesinde bu TV'de videoyu çökerten mekanizmanın aynısı. Codec çıkışı doğrudan SurfaceView'a verilecek (`perf(receiver)` commit'i) ve aynı ölçüm tekrarlanacak.

² `jank.py` katman adını adb shell'e tırnaksız verdiği için `--latency` veri döndürmedi; düzeltildi.

## M3 / M4: cb2c07a (doğrudan çıkış denemesi), Mac, 2026-09-26 13:49–13:57

| ölçüm | req | recv | in | dec | presented | ham jank | video Comp |
|---|---|---|---|---|---|---|---|
| M3 AUTO | 3840x2160@60 | 3840x2160 H.264 | 39.9 | 38.95 | **27.6** | %3.7 | CLIENT |
| M4 1080p | 1920x1080@60 | 1920x1080 H.264 | 25.9 | 25.9 | **25.7** | %7.0³ | CLIENT |

- **4K:** decode edilen karelerin ~%30'u ekrana ulaşmıyor. 4K'daki kasmanın ölçülmüş kaynağı bu.
- **1080p:** gelen = çözülen = sunulan. Kare kaybı yok; Mac'in ~26 fps göndermesi 25 fps'lik YouTube içeriğinden kaynaklanıyor.

**M4 SF katman dökümü (video katmanı):**
- tampon 1920x1088, contentCrop 1920x1080, dönüşüm SCALE (y 0.9926)
- dataspace `0x8c10000` (BT709 / SMPTE170M / FULL range)
- SF `DEVICE` istiyor, HWC `CLIENT` döndürüyor; displayFrame 3840x2160
- Tampon decoder'ın 1088 hizalı YUV çıkışı, yani **doğrudan çıkış çalışıyor**. Log yalnızca başlangıçtaki `output=gl` satırını gösteriyor; yüzey geçişi eski APK'da loglanmıyordu.
- HWC'nin katmanı reddetme sebebi araştırılıyor. Hipotezler: full range, üstteki tam ekran pencere, 1088 ölçeği. İlk adım referans olarak YouTube katmanıyla karşılaştırma.

³ 25 fps içerik 60 Hz'te 2/3 vsync ile gösterildiği için ham metrik düzgün akışı da takılma sayıyor. İçerik temposuna göre hesap eklendi.

## M5: 97d3486 (1080p varsayılan, doğrudan çıkış), Mac, ~49 fps içerik, 2026-09-26 14:26

| req | recv | in | dec | presented | output | kullanıcı |
|---|---|---|---|---|---|---|
| 1920x1080@60 | 1920x1080 H.264 | 49.2 | 49.2 | **24.8** | direct | **4–5 sn gecikme** |

- **Tavan:** HWC video katmanını CLIENT yaptıkça SF her kareyi GPU'da 3840x2160 hedefte birleştiriyor. Bu çözünürlükten bağımsız olarak ~25 fps ile sınırlı. M4 kayıpsız görünüyordu, çünkü içerik zaten 25 fps'ti.
- **Gecikme (regresyon):** doğrudan yolda kareler ekran yüzeyinde FIFO sıraya giriyor ve decoder beklediği için gecikme birikiyor. `1dd51c9` ile gösterilmeyi bekleyen kare sayısı en fazla 2'yle sınırlandı.
- 2 dakikada ~74 MB swap-out: yansıtma sırasında bellek baskısı var.
- 60 fps için video katmanının DEVICE (donanım düzlemi) olması şart. Sıradaki denemeler: renk aralığı deneyi, ardından tünelli oynatma.

## M6: renk aralığı deneyi (97d3486 + range=limited), Mac, 1080p, 2026-09-26 14:40

| in | dec | presented | dataspace | HWC |
|---|---|---|---|---|
| 49.1 | 49.45 | 24.8 | **V0_BT709 LIMITED** (YouTube ile aynı) | **CLIENT** |

- H1 (renk aralığı) elendi. Dataspace YouTube'unkiyle aynı olduğu hâlde HWC katmanı video düzlemine almıyor.
- Kalan tek fark tampon türü:
  - YouTube: MTK `externalbuffer-allocator` üzerinden 1.8 KB'lık YV12 handle tamponları (usage 0x42400900)
  - alıcı: 4 MB'lık YCbCr_420_SP tamponlar (usage 0x2400930)
- Sonuç: bu TV'nin HWC'si video düzlemine yalnızca vendor handle tamponlarını ya da tünelli (SIDEBAND) akışı alıyor gibi görünüyor. Yan yüklenen alıcı bu yüzden GPU kompozisyonunun ~25 fps tavanında kalıyor.

**Karar (kullanıcı):** ~25 fps kabul edildi. Proje kararlılık, A/V senkronu, soak/sızıntı testleri ve dokümanlarla kapatılacak. Tünelli oynatma ileride denenebilecek bir yol olarak kayıtta duruyor.

## M7: 3bd6ab3 (doğrudan çıkış + bekleyen kare sınırı), Mac, 2026-09-26 14:58: REGRESYON

| req | recv | in | dec | presented | dropped | output | kullanıcı |
|---|---|---|---|---|---|---|---|
| 1920x1080@30 | 1920x1080 H.264 | 25.3 | **7.5** | **7.2** | **3988** | direct | 4–5 sn gecikme, kare atlıyor |

- `1dd51c9`'daki sınır `onFrameRendered` bildirimlerine dayanıyordu. Bu TV'de bildirimler gelmiyor, bu yüzden kareler 250 ms'de bir gösterildi.
- Gecikme doğrudan çıkıştan (`cb2c07a`) geliyor. İkisi de geri alındı (`6a7755d`, `c1ab6ee`, `1cb029b`).

## M8 (A/B'nin A kolu): db9c157 (upstream GL yolu + kimlik), Mac, 2026-09-26 15:08

| req | recv | in | dec | presented | dropped | içerik temposuna göre jank | HWC |
|---|---|---|---|---|---|---|---|
| 3840x2160@60 (ayar AUTO) | 3840x2160 H.264 | 27.0 | 27.2 | **25.6** | 0 | %1.68 | CLIENT (RGBA/GL) |

- Referans: upstream GL yolu gecikme biriktirmiyor ve ~27 fps girişin %95'ini gösteriyor. CPU %41, PSS ~61–69 MB.
- B kolu (`1cb029b`: aynı GL yolu + 1080p/30 varsayılanı + bayat kare temizliği) aynı içerikle ölçülecek. B, A'dan kötü değilse kalır.

## M9: A/B, aynı içerik, ikisi de 1080p/30, 2026-09-26 15:22–15:30

| sürüm | in | dec | presented | dropped | jank (içerik temposu) | eksik kare | CPU | PSS tepe |
|---|---|---|---|---|---|---|---|---|
| A `db9c157` (upstream GL) | 25.85 | 25.85 | 25.2 | 0 | %0.92 | %2.70 | %40 | 73.5 MB |
| B `1cb029b` (GL + stats + bayat kare + yüzey iletimi) | 25.3 | 25.3 | 24.9 | 0 | %0.90 | %1.52 | %41 | 66.8 MB |

- B, A'dan kötü değil; fark ölçüm gürültüsü içinde. **B son sürüm olarak kaldı.**
- Gecikme fotoğrafı henüz yok; A/V senkron testiyle birlikte ölçülecek.
