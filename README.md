# AndroidTV_AppleScreenShare

Vestel Android TV'ye (Android 11, MediaTek m7632) **iPhone ve Mac'ten AirPlay ekran yansıtma** —
görüntü + ses, sistemin kendi *Denetim Merkezi → Ekran Yansıtma* menüsüyle.

Alıcı, açık kaynak [`jqssun/android-airplay-server`](https://github.com/jqssun/android-airplay-server)
(GPL-3.0, UxPlay tabanlı) üzerine kuruludur ve pinlenmiş bir commit'ten `receiver/` altında derlenir.

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
