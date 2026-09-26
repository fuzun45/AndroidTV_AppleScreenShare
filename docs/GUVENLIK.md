# Güvenlik Rehberi

## Tehdit Modeli

Bu bölüm AirPlay yansıtması ve ağ ADB'si ile ilgili bilinen riskler ve hafifletme yollarını açıklar.

## Riskler ve Öneriler

### 1. Açık AirPlay (PIN Yok)

**Risk**: Ortak Wi-Fi ağındaki **herhangi biri** Mac veya iPhone yansıtmaya deneyebilir.

**Şiddet**: **Orta** — Yanlışlıkla veya kötü niyetli ekran paylaşma, hassas bilgiler görünür olabilir.

**Azaltma Yolları**:

#### Seçenek A: AirPlay PIN'i Aç (Önerilen)

TV Mirror uygulamasında:

1. **Settings** → **Security** → **Require PIN**
2. PIN kodu seç (4–6 rakam)
3. Aktif hale getir

Mac/iPhone yansıtırken:

- Kontrol Merkezi ekran yansıtması
- "Salon TV" seç
- Talep edilen PIN'i gir

**Önemli**: PIN her oturum başında istenir; hafıza yok.

#### Seçenek B: Güvenilir Wi-Fi Ağı Kullan

- TV ve Mac/iPhone'u **private home Wi-Fi**'de tutun
- Konuk ağını kapalı tut veya farklı SSID kullan
- Ofis / halka açık Wi-Fi'den kaçın

#### Seçenek C: Ağ İzolasyonu

TV'nin yalnızca güvenilir cihazlardan bağlanabileceği bir VLAN oluştur (router bağlı olarak).

---

### 2. Açık ADB (Ağ Hata Ayıklaması)

**Risk**: Herhangi bir ağ cihazı `adb shell` ile TV'ye komut verebilir.

**Şiddet**: **Yüksek** — Uygulamaları kaldır, dosyaları sil, cihazı yönet.

**Geçerli Olma**: Aynı ağdaki biri TV'ye ADB ile bağlanırsa (bağlantı TV'de onaylandıysa veya daha önce yetkilendirilmiş bir bilgisayar varsa) uygulama kurup kaldırabilir, dosyaları okuyup silebilir ve ekranı kaydedebilir.

### Azaltma

**HEMEN Yapılacak** (Her kullanım sonrası):

1. TV'de **Ayarlar** → **Sistem** → **Geliştirici Seçenekleri**
2. **Ağ hata ayıklaması** kapatın
3. **Geliştirici Seçenekleri** tamamen kapat

**Daha Güvenli** (Kalıcı):

```bash
# Önce TV'de ADB'yi kapat (bu komut bağlantıyı da keser), sonra Mac tarafında bağlantıyı unut
adb -s 192.168.1.104:5555 shell settings put global adb_enabled 0
adb disconnect 192.168.1.104:5555
```

**Not**: ADB yalnızca **geliştirme/hata ayıklama için** kullanılır. Yansıtma kendisi ADB'ye ihtiyaç duymaz.

---

### 3. DRM Korumalı İçerik (Netflix vb.)

**Risk**: Netflix, Disney+, Apple TV+ gibi hizmetlerden DRM içeriği yansıtılamaz.

**Sebep**: Apple, HDCP sertifikası olmayan AirPlay alıcılarına DRM korumalaşı akışları göndermez. Bu **tasarım kısıtlaması**, alıcı açığı değil.

**Çözüm**: Yoktur. Bu bir TV Mirror sınırlaması değil, AirPlay protokolünün tasarımıdır.

**Alternatif**: Cihazdan doğrudan Netflix uygulamasını aç (yerleşik TV uygulamalarına bak).

---

### 4. Hue Ambilight'ın "Ekran" Mod Çakışması

**Risk**: Hue Ambilight'ın "ekranı yakala" modu ile aynı anda yansıtma çalıştırılırsa **fps düşüşü**.

**Sebep**: Her iki hizmet de VirtualDisplay (yazılım görüntü katmanı) acar; bu çalışma süresi düşürür.

**Belirtisi**: Yansıtma boyunca hızlı kare atması / takılma.

### Azaltma

Yansıtırken Hue Ambilight'ı kapatın:

```bash
adb shell am force-stop com.hue.app.android
```

veya Hue uygulamasında "ekran yakalama" modu devre dışı bırakın.

---

### 5. Yazılım Güvenlik Yamaları

**Risk**: Eski Android veya Decoder yazılımı güvenlik boşluğu içerebilir.

**Durum**: Vestel shandao (Android 14, yamaları 2026-06-01'den):

- ✓ Desteklenen Android sürümü
- ✓ Nispeten yeni MediaTek decoder'lar
- ✓ Düzenli güvenlik yamaları (taşıyıcıya / OEM'ye bağlı)

**Azaltma**:

- TV'nin **sistem güncellemeleri** etkinleştirmiş kalmasını sağla
- Önemli yamaları hemen uygula

---

### 6. Hiçbir İnternet Bileşeni Eklenmemiş

**Bilgi**: TV Mirror alıcısı **çevrimiçi / analitik / telemetri bileşeni yok** (OpenAI, Google vb. ile iletişim yok).

- Depo: `receiver/` ağ iletişimi yalnızca AirPlay ve mDNS (cihaz bulma)
- Veri: Hiçbir şey gönderilmiyor

**Çıktı**: Ayrı bir ağ segmentasyonu veya izolasyonu gerekmez.

---

## Kontrol Listesi

Yansıtmayı başlataydı önce:

- [ ] ADB **kapalı** (Geliştirici Seçenekleri → Ağ hata ayıklaması kapalı)
- [ ] PIN açık mı? (Seçenek: Açık → daha güvenli)
- [ ] Wi-Fi güvenli ve şifreli mi? (WPA3 veya en azından WPA2)
- [ ] Güvenilir cihazlar yansıtma yapıyor mu?

Yansıtma bittikten sonra:

- [ ] ADB'yi bağlantı havuzundan kaldır: `adb disconnect 192.168.1.104:5555`
- [ ] TV'de Geliştirici Seçenekleri kapat
- [ ] Hue Ambilight ekran yakalama modu kapalı mı?

---

## Sık Sorulan Sorular

**S: Netflix yansıtabilir miyim?**

C: Hayır. Netflix DRM korumalaşı. Apple AirPlay protokolünde bu içeriği HDCP sertifikası olmayan alıcılara göndermez.

**S: Yansıtma sırasında benim başka cihazlarım güvenli midir?**

C: TV Mirror **sadece AirPlay ve mDNS üzerinde konuşuyor**. Veri sağlayıcıya gönderilmez. Ama ağ açık ADB varsa biri TV'yi kontrol edebilir → Geliştirici Seçenekleri'ni kapat.

**S: Lokal ağımda TV Mirror'a saldırabilir mi?**

C: Evet, ADB açıksa. ADB'yi kapalı tut. PIN açıksa yansıtmaya deneme + başarısız deneme kaydedilir (ileride log incelemesi).

**S: Humorlu cihazlar (Google Home, Alexa) TV Mirror ile konuşabilir mi?**

C: Hayır. Ağ yalıtımı seçerse ayrıntılı kurulum gerekli. Buradan değil.

---

## Referans

- [KURULUM.md](KURULUM.md) — ADB kapatma
- [TEST-PROTOKOLU.md](TEST-PROTOKOLU.md) — İşlemleri doğrulama
- **AirPlay Protokolü**: https://openairplay.github.io/airplay-spec/

