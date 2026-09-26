# Performans Analizi

## Genel Bakış

Vestel shandao TV'de AirPlay yansıtması **~25 fps tavan** ile sınırlandırılmıştır. Bunun sebebi ve denenmiş çözümler aşağıda açıklanmıştır.

## Ölçüm Modeli

Her ölçümde şu noktalar kaydedilir:

| Nokta | Açıklama |
|---|---|
| **requested** | iPhone/Mac'ten istenen çözünürlük ve kare hızı |
| **received** | TV'nin aldığı akış çözünürlüğü |
| **decoded** | Video decoder'ının çıktı fps'i |
| **presented** | Ekranda gösterilen kare fps'i |
| **HWC Comp Type** | Hardware Composer'ın karar verdiği kombinasyon: DEVICE (donanım), CLIENT (GPU), veya MIXED |

**Ölçüm aracı**: `scripts/50-perf-capture.sh <etiket> [saniye]`

## Ölçüm Sonuçları (M1–M9)

### M1 — Upstream Varsayılanları, Mac, 4K İstek

| requested | received | codec | in_fps | dec_fps | presented | HWC Type | Durum |
|---|---|---|---|---|---|---|---|
| 3840×2160@60 | 3840×2160 | H.264 AVC | 40.3 | 40.3 | N/A | N/A | Katman seçimi başarısız |

**Gözlem**: Mac 4K H.264 gönderiyor; gelen = çözülen fps'i yüksek, ama ekrana ulaşan metrik ölçülemiyor (araç katmanı bulamadı).

### M2 — SurfaceView Katmanı Seçildi, Mac, 4K AUTO

| requested | received | codec | in_fps | dec_fps | presented | HWC Type | Durum |
|---|---|---|---|---|---|---|---|
| 3840×2160@60 | 3840×2160 | H.264 AVC | 43 | 43 | N/A | CLIENT | GPU Composition |

**Analiz**: 
- Katman bulundu: `SurfaceView[io.github.fuzun45.tvmirror](BLAST)#55162`
- HWC tip: **CLIENT** — GPU'da birleştirilecek
- Sonuç: Decoder kapasite var ama görüntü GPU'da işlenecek (4K → çıktı 3840×2160)

### M3 — Doğrudan Decoder Çıkışı (Direct Output), 4K

| requested | received | in_fps | dec_fps | presented | HWC Type | Durum |
|---|---|---|---|---|---|---|
| 3840×2160@60 | 3840×2160 | 39.9 | 38.95 | **27.6** | CLIENT | Kare kaybı ~30% |

**Bulgu**: 
- Decoder çıkışı doğrudan SurfaceView'a verildi
- Yine de HWC **CLIENT** (GPU) karar verdi
- Ekrana ulaşan: 27.6 fps (~30% kaybı)
- **Sorun**: GPU 3840×2160 hedefte her kareyi birleştiriyor; 60 Hz panelde 25 fps civarında kılıyor

### M4 — Doğrudan Çıkış, 1080p

| requested | received | in_fps | dec_fps | presented | HWC Type | Durum |
|---|---|---|---|---|---|---|
| 1920×1080@60 | 1920×1080 | 25.9 | 25.9 | **25.7** | CLIENT | Kayıp < %1 |

**Analiz**:
- Mac ~26 fps gönderiyor (YouTube 25 fps içeriğinden)
- Decoder: 26 fps → Sunulan: 25.7 fps
- **Kare kaybı yok** (içerik temposunu dikkate alarak)
- HWC: CLIENT (ama daha az GPU iş yükü)

### M5 — 1080p Varsayılan, Yüksek İçerik FPS, Latency Testi

| in_fps | dec_fps | presented | Latency | Durum |
|---|---|---|---|---|
| 49.2 | 49.2 | **24.8** | 4–5 sn regresyonu | Kare sırası içinde takılma |

**Keşif**: 
- İçerik 49 fps (ör. yüksek FPS oyun/test) gönderildiğinde
- Decoder 49 fps çalıştırıyor ama GPU ekrana 24.8 fps koyabiliyor
- **Gecikme birikimi**: Decoder FIFO sıraya kareleri koyuyor, ekran iştah kütleşince sıraya sığmayan kareler bekliyor → 4–5 sn gecikmesi
- **Sebep**: doğrudan çıkış yolu (GL yerine codec → SurfaceView). `1dd51c9` ile denenen kare sınırlaması işe yaramadı ve M7'de durumu daha da kötüleştirdi.

**Sonuç**: Doğrudan çıkış kapatıldı (`DIRECT_OUTPUT = false`). Upstream GL yolu yalnızca en yeni kareyi gösterdiği için gecikme birikmiyor (M8/M9).

### M6 — Renk Aralığı Deneyi (Color Range Experiment)

| in_fps | dec_fps | presented | dataspace | HWC | Durum |
|---|---|---|---|---|---|
| 49.1 | 49.45 | **24.8** | V0_BT709 LIMITED | CLIENT | İşe yaramadı |

**Deney**: YouTube'ün kullandığı renk aralığını (V0_BT709 LIMITED / FULL range) tam olarak taklit ettik.

**Sonuç**: HWC yine CLIENT (GPU) kaldı.

**Neden?** TV'nin HWC'si video düzlemine yalnızca:
1. Vendor handle tamponları (YouTube'ün externalbuffer-allocator'ı)
2. Tünelli (SIDEBAND) akışı

alıyor. Standart YUV tampon kullanımızda GPU budunu geçemiyor.

### M7 — Doğrudan Çıkış + Bekleyen Kare Sınırı (`3bd6ab3`): REGRESYON

| req | in_fps | dec_fps | presented | dropped | Durum |
|---|---|---|---|---|---|
| 1920×1080@30 | 25.3 | 7.5 | **7.2** | 3988 | 4–5 sn gecikme, kare atlama |

İki değişiklik de geri alındı (`6a7755d`, `c1ab6ee`, `1cb029b`).

### M8/M9 — A/B: Upstream (`db9c157`) ve Son Sürüm (`1cb029b`), 1080p/30, Aynı İçerik

| Sürüm | in_fps | dec_fps | presented | dropped | Jank (içerik temposu) | CPU | PSS tepe |
|---|---|---|---|---|---|---|---|
| A `db9c157` | 25.85 | 25.85 | 25.2 | 0 | %0.92 | %40 | 73.5 MB |
| B `1cb029b` | 25.3 | 25.3 | 24.9 | 0 | %0.90 | %41 | 66.8 MB |

**Sonuç**: B, upstream kadar iyi (fark ölçüm gürültüsü içinde). B son sürüm olarak kaldı.

---

## 25 FPS Tavanının Açıklaması

### Mimarı

```
iPhone/Mac (1920×1080 @25fps) 
    ↓ [AirPlay H.264]
TV Decoder (OMX.MS.AVC) → 25 fps output
    ↓ [YCbCr_420_SP 4 MB buffers]
SurfaceFlinger
    ↓ [HWC karar: CLIENT = GPU]
GPU Compositor (3840×2160 hedef)
    ↓ [vsync 60 Hz, GPU kapasitesi ~25 fps @ 3840×2160]
Display (Panel 60 Hz)
    ↓
Ekran (25 fps görünür)
```

### Neden GPU Sınırlı?

1. **Decoder → SurfaceTexture → GL → SurfaceView** (upstream yolu; doğrudan çıkış denendi, bkz. M5/M7)
2. **HWC**: Uygulama tamponunu (RGBA ya da standart YCbCr) video düzlemine almıyor → **CLIENT (GPU)**
3. **GPU**: 1920×1080 → 3840×2160 ölçeklendirme + birleştirme
4. **Kapasite**: ölçülen tavan **~25 fps** (M3–M9)

Gelen 25 fps'te GPU ne zaman: 25 fps → GPU işler → 25 fps sunulur.

Gelen 50 fps'te: Decoder 50 fps → GPU tıkandığında → kare atılmaya başlanıyor.

### DEVICE Düzleminin Neden Çalışmadığı

YouTube gibi **HWC'yi donanım düzlemine (DEVICE) koymak** için:

- Vendor allocator (MTK externalbuffer-allocator) **veya**
- Tünelli playback (SIDEBAND) **gerekli**

Elimizdeki yol: Standart HAL buffers → HWC **CLIENT** → GPU.

---

## Denenmiş Çözümler

| Deney | Kod | Sonuç | Neden İşe Yaramadı |
|---|---|---|---|
| Doğrudan çıkış | `cb2c07a` (kapatıldı) | ~25 fps + 4–5 sn gecikme | HWC yine CLIENT; FIFO kuyruk gecikme biriktirdi |
| Bekleyen kare sınırı | `1dd51c9` (geri alındı) | 7 fps | `onFrameRendered` bildirimleri bu TV'de gelmiyor |
| 1080p Varsayılan | `97d3486` | 25 fps tamam | İçeriğin 25 fps olduğu şüpheleniliyor; yüksek FPS → 24 fps + gecikme |
| Renk aralığı | `97d3486` + LIMITED range | 24.8 fps | HWC'nin tamanı yok, YouTube gibi vendor buffer lazım |

## Gelecek Seçenek: Tünelli Oynatma (Tunneled Playback)

MediaTek HWC'ler **FEATURE_TunneledPlayback** desteğinde decoder'lar reklam yapıyor.

```
Decoder → tunneled buffer
    ↓ [Doğrudan video düzlem, HWC DEVICE]
Display
```

**Avantaj**: GPU bypass, donanım düzlem → 60 fps muhtemel.

**Durum**: Henüz uygulanmamış. Bu yol `devices/vestel-shandao/OLCUMLER.md` içinde belirtilir.

---

## Performans İstatistikleri

### CPU & Bellek (M3, 4K)

| Metrik | Değer |
|---|---|
| App CPU medyanı | ~25% (tek çekirdek ölçek) |
| PSS başında | 86 MB |
| PSS sonu | 61 MB |
| Pik PSS | 86 MB |
| Swap-out 2 dakika | ~60 MB |

**Değerlendirme**: Normal. Swap'i düzenli, bellek sıkışmadığı sürece sorun değil.

### Ağ Jitter

Mac → TV ping (50 paket):
- Min: 2.6 ms
- Ort: 14.9 ms
- Max: 57.1 ms
- Std Dev: 17.9 ms

**Kaynak şüphesi**: macOS AWDL kanala geçişi veya Wi-Fi güç tasarrufu.

**Etki**: `in_fps` dalgalanması ve sunulan kare jank'ı. Tek başına sistem arızası sayılmıyor.

---

## Kabul Edilen Durum

Proje **~25 fps tavanı** kabul ederek:

1. ✓ A/V senkronizasyonu ölçülüyor (< ~100 ms)
2. ✓ Gecikme kontrol ediliyor (hedef < ~300 ms, GL yolu)
3. ✓ Bellek sızıntısı testleri yapılıyor
4. ✓ Soak (dayanıklılık) testleri çalışıyor
5. ✓ Dokümantasyon tamamlanıyor

---

## Referans

- **Ölçüm Dosyası**: `devices/vestel-shandao/OLCUMLER.md`
- **Test Protokolü**: [TEST-PROTOKOLU.md](TEST-PROTOKOLU.md)
- **Belirlenen Geçmiş**: `scripts/50-perf-capture.sh`, `tools/jank.py`

