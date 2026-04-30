# CA-Wall Panel — SketchUp Plugin

**ca//works · Cihan Aydoğdu Mimarlık**

Duvar paneli profillerini bir çizgi/yay/daire/curve boyunca otomatik
yerleştiren, sonra renklendirilebilen SketchUp eklentisi.

## Kullanıcı için

### Kurulum

1. [Releases](https://github.com/mimarcihanaydogdu/ca-wall-panel/releases/latest) sayfasından `ca_wall_panel.rbz` dosyasını indir.
2. SketchUp → **Window → Extension Manager → Install Extension** → `.rbz` dosyasını seç.
3. SketchUp'ı yeniden başlat.
4. Üst menü: **Eklentiler (Plugins) → CA-Wall Panel**

### Otomatik güncelleme

Plugin her açılışta **arka planda** yeni sürüm var mı diye GitHub'ı
kontrol eder. Yeni sürüm bulursa **sessizce** indirir; **bir sonraki
SketchUp açılışında** otomatik aktive olur ve değişiklik notlarını
gösterir.

### Anında güncelle (yeniden başlatma yok)

**Eklentiler → CA-Wall Panel → Güncelle Plugini** (veya toolbar'daki
güncelleme ikonu): Yeni sürüm varsa indirilir, dosyalar yerine açılır
ve aynı oturumda yeniden yüklenir. SketchUp'ı kapatmaya gerek kalmaz.

### Kullanım

1. Profil seç ve uygula menüsünden bir profil seç.
2. SketchUp'ta uygulamak istediğin geometriyi seç:
   - Tek çizgi · yay · daire · polyline · freehand curve
3. Diyalogdan **Uygula** → profil çizgi boyunca uzanır.
4. Renklendirmek için panel grubunu seç → **Renklendir** menüsü → palet.

## Maintainer için (yeni sürüm yayınlamak)

Tüm süreç bir tag push'ı ile çalışır — manuel zip'leme yok.

```bash
# 1) ca_wall_panel.rb içindeki PLUGIN_VERSION'u güncelle
#    örn: PLUGIN_VERSION = '0.4.0'
git add ca_wall_panel.rb
git commit -m "v0.4.0: <ne değişti>"

# 2) Tag oluştur ve push'la
git tag v0.4.0
git push origin main --tags
```

GitHub Actions otomatik olarak:
- `ca_wall_panel.rbz` build eder
- Release oluşturur ve `.rbz`'yi asset olarak yükler
- Release notlarına yazdığın metin updater tarafından kullanıcılara gösterilir

> **Tag ile dosyadaki PLUGIN_VERSION birebir eşleşmeli**, aksi halde
> workflow `::error::` ile durur. (Yanlış sürüm yayınlamayı önler.)

### Release notu nasıl yazılır

GitHub'da Release sayfasını aç → "Edit release" → body kısmını yaz.
Bu metin updater'ın güncelleme sonrası mesajında kullanıcıya gösterilir.

```markdown
- Yeni profil eklendi: 18126-50
- Daire path'lerde kesit yönü düzeltildi
- Renk paletine 4 yeni ton
```

Kısa, madde madde, kullanıcının umurunda olacak şeyler.

## Yapı

```
ca_wall_panel.rb               ← extension loader
ca_wall_panel/
├── main.rb                    ← UI, menü, toolbar, dialog yönetimi
├── profiles.rb                ← profil veritabanı + kesit poligon üretimi
├── apply_tool.rb              ← edge sıralama + follow-me
├── colorize_tool.rb           ← materyal atama
├── updater.rb                 ← GitHub Releases auto-updater + canlı reload
├── dialog.html                ← profil seçim galerisi
├── colors.html                ← renk paleti
└── icons/
    ├── panel.svg
    ├── color.svg
    └── update.svg
.github/workflows/release.yml  ← tag push → otomatik .rbz build + release
```

## Updater nasıl çalışır

### Arka plan akışı (otomatik, sessiz)
1. Plugin yüklenir → `Updater.boot` çalışır
2. `Plugins/.cawp_pending/` klasörü varsa → içerikler `Plugins/`'e kopyalanır, klasör silinir, kullanıcıya değişiklik notu gösterilir
3. Son kontrolden 6+ saat geçtiyse arka planda thread başlatılır
4. `api.github.com/repos/.../releases/latest` çağrılır
5. Yeni tag varsa `.rbz` indirilir, açılır, `.cawp_pending/`'e yazılır
6. Mevcut oturumda hiçbir görsel değişiklik yok
7. Bir sonraki açılışta 2. adım çalışır → güncelleme aktif

### "Güncelle Plugini" butonu (canlı, anında)
1. Kullanıcı menü/toolbar'dan tıklar → `Updater.update_now!`
2. GitHub'dan en son sürüm sorgulanır
3. Yeni sürüm varsa `.rbz` indirilir, doğrudan `Plugins/` klasörüne açılır
4. Tüm `.rb` dosyaları `load()` ile yeniden yüklenir
5. Açık diyaloglar kapatılıp yeniden açılabilir hale gelir
6. Kullanıcıya başarı mesajı gösterilir — SketchUp kapatılmaz

State dosyaları:
- `.cawp_updater_state` — son kontrol zamanı + yüklü sürüm (JSON)
- `.cawp_pending/` — bekleyen güncelleme klasörü
- `.cawp_dl_<ts>.rbz` — geçici indirme dosyası (extract sonrası silinir)

## Yeni profil eklemek

`ca_wall_panel/profiles.rb` içinde `DATA` dizisine bir hash ekleyin:

```ruby
{
  code: '18126-99', name: 'Yeni Profil', width_mm: 126, depth_mm: 18,
  length_mm: 2800, pattern: :v_groove,
  params: { groove_count: 1, groove_width: 10.0, groove_depth: 5.0 }
}
```

Mevcut desenler: `:flat`, `:v_groove`, `:u_groove`, `:double_groove`,
`:ribbed`, `:half_round`, `:step`, `:reeded`, `:louver`.

## Sürüm

`v0.1.0` — ilk yayın (canlı güncelleme butonu dahil) · 2026
