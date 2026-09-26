# AndroidTV_AppleScreenShare

Vestel Android TV'ye (Android 11, MediaTek m7632) **iPhone ve Mac'ten AirPlay ekran yansıtma** —
görüntü + ses, sistemin kendi *Denetim Merkezi → Ekran Yansıtma* menüsüyle.

Alıcı, açık kaynak [`jqssun/android-airplay-server`](https://github.com/jqssun/android-airplay-server)
(GPL-3.0, UxPlay tabanlı) üzerine kuruludur ve pinlenmiş bir commit'ten `receiver/` altında derlenir.

## Hızlı Başlangıç

1. **Kur**: [KURULUM.md](docs/KURULUM.md)
2. **Test Et**: [TEST-PROTOKOLU.md](docs/TEST-PROTOKOLU.md)
3. **Ağ Ayarla**: [AG-REHBERI.md](docs/AG-REHBERI.md)
4. **Performans Ölç**: [PERFORMANS.md](docs/PERFORMANS.md)
5. **Güvenlik**: [GUVENLIK.md](docs/GUVENLIK.md)
6. **Yol Haritası**: [YOL-HARITASI.md](docs/YOL-HARITASI.md)

Özet: `./scripts/00-connect.sh` → `./scripts/30-install.sh <apk>` → iPhone/Mac'ten yansıt.

## Durum

| Özellik | Durumu | Notlar |
|---|---|---|
| **Çözünürlük** | 1920×1080 (1080p) | Önerilen varsayılan |
| **Kare Hızı** | ~25 fps | GPU compositor limiti |
| **Ses** | ✓ Çalışıyor | AAC-ELD |
| **Netflix vb. (DRM)** | ✗ Çalışmıyor | Apple tasarımı, çözüm yok |
| **Stabilite** | ✓ İyi | Soak/sızıntı testleri PASS |
| **A/V Senkronu** | < ~100 ms | Ölçülmüş |
| **Latency** | < ~200 ms | Ağ jitter'ına bağlı |

### Bilinen Sınırlamalar

- **25 fps Tavan**: MediaTek m7632 GPU'sunun 3840×2160 çıktıda composite yeterliliği → [PERFORMANS.md](docs/PERFORMANS.md)
- **Hue Ambilight Çakışması**: "Ekran Yakalama" modu yansıtmayı yavaşlatabilir → [GUVENLIK.md](docs/GUVENLIK.md)
- **ADB Açık Olduğunda Yüksek Risk**: Geliştirici Seçenekleri'ni kapat → [GUVENLIK.md](docs/GUVENLIK.md)
- **Pin Varsayılanı Kapalı**: Ortak ağda PIN'i aç → [GUVENLIK.md](docs/GUVENLIK.md)

## İlke: önce ölç, sonra değiştir

Upstream önce değiştirilmeden kurulur ve bu TV'de ölçülür
(`requested → received → decoded → presented`, SurfaceFlinger HWC kompozisyon tipi).
Kod değişikliği yalnızca ölçüm gerektirdiğinde yapılır.

## Dizinler

| Yol | İçerik |
|---|---|
| `receiver/` | AirPlay alıcısı (upstream, pinli) |
| `scripts/` | Mac'ten ADB ile bağlantı, baseline, kurulum, doğrulama, ölçüm |
| `tools/` | SurfaceFlinger tabanlı kare zamanlama ölçümü |
| `devices/` | Cihaza özel baseline ve ölçüm kayıtları |
| `docs/` | Kurulum, ağ, test protokolü, performans ve güvenlik |

## Lisans

GPL-3.0 (upstream ile aynı). Bkz. `LICENSE`.
