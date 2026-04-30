# ----------------------------------------------------------------
#  CA-Wall Panel — Profile Database
# ----------------------------------------------------------------
#  Her profil bir hash ile tanımlanır:
#    :code      → ürün kodu (örn. "18126-46")
#    :width_mm  → genişlik (kesitin yüzeye paralel boyutu)
#    :depth_mm  → derinlik (duvardan dışa çıkan boyut, kalınlık)
#    :length_mm → standart boy (referans, follow-me uzunluğunu çizgi belirler)
#    :pattern   → :flat | :v_groove | :u_groove | :ribbed | :half_round |
#                 :double_groove | :wave | :reeded | :louver | :step
#    :params    → desene özel parametreler (kanal sayısı, derinlik vb.)
#
#  Kesit, build_profile_points ile parametrik üretilir.
#  Kesit koordinat sistemi:
#    - X ekseni: yüzey boyunca (genişlik)
#    - Y ekseni: derinliğe (duvardan dışarı, +Y dışa)
#    - Kesit, daha sonra path'in başlangıç noktasına dik düzlemde inşa edilir.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module Profiles

      # ------------------------------------------------------------
      #  PROFIL VERITABANI
      # ------------------------------------------------------------
      DATA = [
        {
          code: '08126-01', name: 'Düz 8x126', width_mm: 126, depth_mm: 8,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '18126-46', name: 'V-Kanal 18x126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :v_groove,
          params: { groove_count: 1, groove_width: 8.0, groove_depth: 4.0 }
        },
        {
          code: '18126-44', name: 'Çift V-Kanal 18x126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :double_groove,
          params: { groove_count: 2, groove_width: 6.0, groove_depth: 3.5,
                    groove_spacing: 30.0 }
        },
        {
          code: '18126-45', name: 'U-Kanal 18x126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :u_groove,
          params: { groove_count: 1, groove_width: 14.0, groove_depth: 5.0 }
        },
        {
          code: '18126-47', name: 'Çoklu Yiv 18x126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :ribbed,
          params: { rib_count: 8, rib_depth: 3.0 }
        },
        {
          code: '08215-01', name: 'Geniş Düz 8x215', width_mm: 215, depth_mm: 8,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '08215-12', name: 'Yarım Yuvarlak 8x215', width_mm: 215, depth_mm: 12,
          length_mm: 2800, pattern: :half_round,
          params: { radius: 6.0 }
        },
        {
          code: '22126-45', name: 'Derin Yiv 22x126', width_mm: 126, depth_mm: 22,
          length_mm: 2800, pattern: :step,
          params: { step_count: 2, step_depth: 6.0 }
        },
        {
          code: '08160-01', name: 'Reeded 8x160', width_mm: 160, depth_mm: 12,
          length_mm: 2800, pattern: :reeded,
          params: { rib_count: 14, rib_radius: 4.0 }
        },
        {
          code: '3030-08', name: 'Lamel 30x30', width_mm: 30, depth_mm: 30,
          length_mm: 2800, pattern: :louver,
          params: {}
        }
      ].freeze

      # ------------------------------------------------------------
      #  ARAMA YARDIMCILARI
      # ------------------------------------------------------------
      def self.all
        DATA
      end

      def self.find(code)
        DATA.find { |p| p[:code] == code }
      end

      # ------------------------------------------------------------
      #  KESİT POLİGON ÜRETİMİ
      #  Geri dönüş: Geom::Point3d dizisi (kapalı poligon, son nokta != ilk).
      #  Birim: inç (SketchUp iç birim). 1 mm = 1.mm helper'ı kullanılır.
      # ------------------------------------------------------------
      def self.build_profile_points(profile)
        w = profile[:width_mm].mm
        d = profile[:depth_mm].mm
        case profile[:pattern]
        when :flat          then flat_points(w, d)
        when :v_groove      then v_groove_points(w, d, profile[:params])
        when :double_groove then double_groove_points(w, d, profile[:params])
        when :u_groove      then u_groove_points(w, d, profile[:params])
        when :ribbed        then ribbed_points(w, d, profile[:params])
        when :half_round    then half_round_points(w, d, profile[:params])
        when :step          then step_points(w, d, profile[:params])
        when :reeded        then reeded_points(w, d, profile[:params])
        when :louver        then flat_points(w, d) # basit dikdörtgen
        else
          flat_points(w, d)
        end
      end

      # ============================================================
      #  KESİT ÜRETİCİLER (XY düzleminde, sol-alt köşeden başlar)
      # ============================================================

      # Basit dikdörtgen
      def self.flat_points(w, d)
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(0, d, 0)
        ]
      end

      # Ortada tek V-kanal
      def self.v_groove_points(w, d, p)
        gw = (p[:groove_width] || 8.0).mm
        gd = (p[:groove_depth] || 4.0).mm
        cx = w / 2.0
        pts = []
        pts << Geom::Point3d.new(0, 0, 0)
        pts << Geom::Point3d.new(w, 0, 0)
        pts << Geom::Point3d.new(w, d, 0)
        pts << Geom::Point3d.new(cx + gw / 2.0, d, 0)
        pts << Geom::Point3d.new(cx, d - gd, 0)
        pts << Geom::Point3d.new(cx - gw / 2.0, d, 0)
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # İki V-kanal
      def self.double_groove_points(w, d, p)
        gw = (p[:groove_width] || 6.0).mm
        gd = (p[:groove_depth] || 3.5).mm
        sp = (p[:groove_spacing] || 30.0).mm
        cx = w / 2.0
        c1 = cx - sp / 2.0
        c2 = cx + sp / 2.0
        pts = []
        pts << Geom::Point3d.new(0, 0, 0)
        pts << Geom::Point3d.new(w, 0, 0)
        pts << Geom::Point3d.new(w, d, 0)
        pts << Geom::Point3d.new(c2 + gw / 2.0, d, 0)
        pts << Geom::Point3d.new(c2, d - gd, 0)
        pts << Geom::Point3d.new(c2 - gw / 2.0, d, 0)
        pts << Geom::Point3d.new(c1 + gw / 2.0, d, 0)
        pts << Geom::Point3d.new(c1, d - gd, 0)
        pts << Geom::Point3d.new(c1 - gw / 2.0, d, 0)
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # U-kanal (dik kenarlı kanal)
      def self.u_groove_points(w, d, p)
        gw = (p[:groove_width] || 14.0).mm
        gd = (p[:groove_depth] || 5.0).mm
        cx = w / 2.0
        pts = []
        pts << Geom::Point3d.new(0, 0, 0)
        pts << Geom::Point3d.new(w, 0, 0)
        pts << Geom::Point3d.new(w, d, 0)
        pts << Geom::Point3d.new(cx + gw / 2.0, d, 0)
        pts << Geom::Point3d.new(cx + gw / 2.0, d - gd, 0)
        pts << Geom::Point3d.new(cx - gw / 2.0, d - gd, 0)
        pts << Geom::Point3d.new(cx - gw / 2.0, d, 0)
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # Çoklu yiv (rib_count adet eşit aralıklı V-yiv)
      def self.ribbed_points(w, d, p)
        n  = p[:rib_count] || 8
        rd = (p[:rib_depth] || 3.0).mm
        seg = w / n.to_f
        pts = []
        pts << Geom::Point3d.new(0, 0, 0)
        pts << Geom::Point3d.new(w, 0, 0)
        pts << Geom::Point3d.new(w, d, 0)
        (1...n).each do |i|
          x = w - i * seg
          pts << Geom::Point3d.new(x + seg / 2.0, d, 0)
          pts << Geom::Point3d.new(x, d - rd, 0)
        end
        pts << Geom::Point3d.new(seg / 2.0, d, 0)
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # Yarım yuvarlak (kabarık)
      def self.half_round_points(w, d, p)
        r  = (p[:radius] || 6.0).mm
        seg = 16
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0)
        ]
        seg.times do |i|
          t   = i / seg.to_f
          ang = t * Math::PI
          x   = w / 2.0 + (w / 2.0) * Math.cos(ang)
          y   = d + r * Math.sin(ang)
          pts << Geom::Point3d.new(x, y, 0)
        end
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # Step (kademeli kanal)
      def self.step_points(w, d, p)
        sc = p[:step_count] || 2
        sd = (p[:step_depth] || 6.0).mm
        cx = w / 2.0
        step_total = w * 0.5
        sw = step_total / sc.to_f
        pts = []
        pts << Geom::Point3d.new(0, 0, 0)
        pts << Geom::Point3d.new(w, 0, 0)
        pts << Geom::Point3d.new(w, d, 0)
        sc.times do |i|
          x_outer = cx + step_total / 2.0 - i * sw
          y       = d - i * sd
          pts << Geom::Point3d.new(x_outer, y, 0)
          pts << Geom::Point3d.new(x_outer - sw, y, 0)
        end
        deepest_y = d - sc * sd
        pts << Geom::Point3d.new(cx + step_total / 2.0 - sc * sw, deepest_y, 0)
        pts << Geom::Point3d.new(cx - step_total / 2.0 + sc * sw, deepest_y, 0)
        sc.downto(1) do |i|
          x_inner = cx - step_total / 2.0 + (i - 1) * sw
          y       = d - (i - 1) * sd
          pts << Geom::Point3d.new(x_inner, y, 0)
          pts << Geom::Point3d.new(x_inner - sw, y, 0)
        end
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # Reeded (yarım daire çubuklar)
      def self.reeded_points(w, d, p)
        n  = p[:rib_count] || 14
        rr = (p[:rib_radius] || 4.0).mm
        seg_per_rib = 8
        rib_w = w / n.to_f
        actual_r = [rib_w / 2.0, rr].min
        pts = []
        pts << Geom::Point3d.new(0, 0, 0)
        pts << Geom::Point3d.new(w, 0, 0)
        pts << Geom::Point3d.new(w, d, 0)
        (n - 1).downto(0) do |i|
          cx = (i + 0.5) * rib_w
          seg_per_rib.times do |k|
            t   = k / seg_per_rib.to_f
            ang = t * Math::PI
            x   = cx + actual_r * Math.cos(ang)
            y   = d + actual_r * Math.sin(ang)
            pts << Geom::Point3d.new(x, y, 0)
          end
        end
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

    end
  end
end
