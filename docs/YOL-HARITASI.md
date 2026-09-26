# Yol Haritası

v1.0.0 Vestel `shandao` TV'de kuruldu ve çalışıyor.

| | ölçüm |
|---|---|
| Gecikme | ~50–90 ms |
| Kare kaybı (1080p) | yok |
| Sızıntı | yok |
| TV açılışında | sunucu otomatik başlıyor |

Aşağıdakiler sırasıyla, **her biri A/B ölçümüyle** yapılacak. Çalışan sürümün davranışı ölçülmeden değiştirilmez.

## 1. Geri alınabilir debloat (düşük risk, uygulama kodu yok)

**Neden:**
- TV'de 1.82 GB RAM var ve 481 MB zRAM kullanımda.
- Yansıtma sırasında 2 dakikada 60–74 MB swap-out ölçüldü (M1, M5). LMK olayları da görülüyor.

**Beklenen:** Swap ve ani takılmalar azalır, uygulama geçişleri hızlanır. 25 fps tavanını değiştirmez.

**Yöntem:**
- `scripts/20-debloat.sh` önce `RESTORE-ALL.sh` üretir, sonra küçük batch'ler hâlinde yalnızca `pm disable-user --user 0` uygular. Hiçbir paket kaldırılmaz; root yok.
- Aday liste `10-baseline` paket/bellek dökümünden çıkarılır ve kullanıcı onaylar. İlk aday: `com.google.android.backdrop` (Ambient, ~125 MB).
- **Korunacaklar:**
  - Wi-Fi, BT/kumanda, DRM, Play, Cast, Assistant
  - `com.mediatek.tvinput`, `com.fuzun.hueambilight`, YouTube, Netflix

**Ölçüm:** `50-perf-capture` ve `65-leak-watch`, öncesi ve sonrası. Bakılacaklar: swap-out, MemAvailable, jank. Her batch'ten sonra kumanda, ses, Cast, YouTube/Netflix ve Hue elle kontrol edilir.

## 2. Tünelli oynatma deneyi (25 fps tavanını aşmanın tek yolu, yüksek risk)

**Neden:**
- Bu TV'nin HWC'si video düzlemine yalnızca vendor ya da tünelli (SIDEBAND) tamponları alıyor.
- Uygulamanın katmanı GPU'da 4K'ya birleştiriliyor ve ~25 fps ile sınırlı kalıyor (M3–M6).
- OMX.MS AVC/HEVC decoder'ları `tunneled-playback` destekliyor.

**Beklenen:** Görüntü GPU'yu atlayıp donanım video düzlemine gider. Hedef 60 fps ve daha düşük GPU yükü.

**Yöntem:**
- adb ile açılan, **varsayılan kapalı** bir deney anahtarı. Mevcut GL yolu değişmez.
- Önce yalnızca video için PoC: `FEATURE_TunneledPlayback`, audio session id, `PARAMETER_KEY_TUNNEL_PEEK`.
- Ölçülecekler: HWC `SIDEBAND` mi, presented fps, gecikme.
- Başarılıysa ayrı bir adımda ses de tünelli `AudioTrack`'e taşınır ve A/V senkronu yeniden ölçülür.

**Kabul:**
- A/B'de presented > 25 fps
- gecikme ≤ ~90 ms
- A/V senkron gözle aynı
- 20 bağlan/kopar sorunsuz

**Risk:** Vendor davranışı belgesiz; deney başarısız olabilir. O durumda anahtar kaldırılır ve bulgu belgelenir.

## Açık konular

- **Bellek basamağı (M12):** bir turda tek seferlik +6 MB görüldü. Tekrar edip etmediği uzun bir turla netleşir: `65-leak-watch 50 30` ile birlikte `AUTO=1 60-soak connect-cycles 40`.
- **ADB:** şimdilik açık. İşler bitince kapatılacak (bkz. `GUVENLIK.md`).
- **Ağ (öneri):** TV'yi kabloyla bağlamak Mac kaynaklı Wi-Fi jitter'ını (maks. 57 ms) azaltır. Şu anki gecikmede belirgin bir fark beklenmiyor.
