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
