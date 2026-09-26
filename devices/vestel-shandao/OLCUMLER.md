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
