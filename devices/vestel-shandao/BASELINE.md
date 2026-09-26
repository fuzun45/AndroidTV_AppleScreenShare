# Vestel `shandao` — stock baseline (2026-09-26)

Kaynak: `scripts/10-baseline.sh` çıktısı (salt okunur). Ağ kimlikleri (SSID/BSSID/MAC) bilinçli olarak yazılmadı.

## Künye

| | |
|---|---|
| Marka / cihaz | Vestel / `shandao` (board `EMIR`) |
| Android | **14 (API 34)**, güvenlik yaması 2026-06-01 |
| SoC | MediaTek `m7632` |
| Panel | 3840x2160 @ 60.000004 Hz, tek mod, HDR tipleri 1/2/3/4 |
| UI | `wm size` override 1920x1080 (HWC 4K'da kompoze ediyor) |
| HOME | `com.google.android.tvlauncher` |

> Not: Hue projesinin belgelerinde "Android 11" yazıyordu; cihaz şu an Android 14 çalıştırıyor.

## Bellek

| | |
|---|---|
| Toplam | 1,824,348 kB |
| Boş (cached dahil) | ~623 MB |
| ZRAM | 481 MB swap kullanımda (111 MB fiziksel) |
| En büyük PSS | `backdrop` (Ambient) 125 MB, `system` 121 MB, `tvlauncher` 115 MB, `netflix` 108 MB |

Swap aktif ama durum "normal". Debloat şimdilik yapılmıyor; ölçüm bellek baskısı gösterirse ilk aday `com.google.android.backdrop`.

## Ağ

| | |
|---|---|
| TV bağlantısı | **5 GHz** (5220 MHz, 80 MHz kanal), Wi-Fi 5, RSSI −35 dBm, link 780–866 Mbps |
| Router | Aynı SSID'de 2.4 GHz BSSID de var (2437 MHz) |
| Mac → TV ping (50 paket) | min 2.6 / ort 14.9 / maks 57.1 ms, stddev 17.9 ms, kayıp %0 |

TV tarafı iyi. Mac de aynı 5 GHz kanalında (kanal 44 = 5220 MHz, 80 MHz), yani bant farkı yok.
Jitter'ın muhtemel kaynakları macOS AWDL kanal atlaması veya Wi-Fi güç tasarrufu. Yansıtmadaki
etkisi `in_fps` dalgalanması ve `presented` jank'ıyla ölçülecek; tek başına bir sorun sayılmıyor.

## AirPlay / portlar

- TV native AirPlay yayınlamıyor (`_airplay._tcp`'de yalnızca Mac görünüyor).
- Port 7000 boş; Cast portları (8008/8009/8443) dinlemede.

## Video decoder'ları (media_codecs XML, 2. baseline)

| Decoder | Maks. boyut | Performance point | Ölçülen fps | Özellikler |
|---|---|---|---|---|
| `OMX.MS.HEVC.Decoder` | 4096x2176 | 3840x2160@60 | 1080p: 393, **2160p: 84** | adaptive, **low-latency**, tunneled |
| `OMX.MS.AVC.Decoder` | 4096x2304 | 3840x2160@60 | 1080p: 192 | adaptive, **low-latency**, tunneled |
| `c2.android.avc/hevc` (yazılım) | 2048x2048 | – | 1080p: 13 / 28 | yalnızca yedek, gerçek zamanlı değil |

Sonuç:
- Donanım decoder'ları 4K60 HEVC/AVC'yi rahatça karşılıyor; decoder darboğaz beklenmiyor.
- Yazılım yedeğine düşmek bu TV'de kullanılamaz sonuç verir (1080p'de 13–28 fps). Logda `decoder=c2.android.*` görülürse bu hata sayılır.
- Asıl şüpheli, upstream'in her kareyi GL ile SurfaceView'a çizmesi (4K'da zayıf GPU). Audit adımında ölçülecek.

## HWC

- Boşta `HWC missed frame count: 7297` (~23 saat uptime; kümülatif).
- Ölçümlerde yalnızca test öncesi/sonrası fark kullanılır.
