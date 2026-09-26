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

TV tarafı iyi. Jitter yüksek; muhtemel kaynak Mac'in bandı veya güç tasarrufu. Mac ve iPhone'un 5 GHz BSSID'ye bağlı olduğu yansıtma testinden önce doğrulanacak.

## AirPlay / portlar

- TV native AirPlay yayınlamıyor (`_airplay._tcp`'de yalnızca Mac görünüyor).
- Port 7000 boş; Cast portları (8008/8009/8443) dinlemede.

## Video decoder'ları

- `OMX.MS.AVC.Decoder` donanım AVC decoder'ı var.
- HEVC donanım decoder'ı ve boyut/fps sınırları ilk baseline özetine düşmedi; `10-baseline.sh` düzeltildi.
- Kesin bilgi ilk yansıtmada `TvMirrorStats decoder=...` satırından gelecek.

## HWC

- Boşta `HWC missed frame count: 7297` (~23 saat uptime; kümülatif).
- Ölçümlerde yalnızca test öncesi/sonrası fark kullanılır.
