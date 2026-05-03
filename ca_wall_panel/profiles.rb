# ----------------------------------------------------------------
#  CA-Wall Panel — Profile Database (built-in + custom)
# ----------------------------------------------------------------
#  Built-in profiller DATA dizisinde tanımlıdır. Kullanıcı diyalogdan
#  yeni özel profiller ekleyebilir; bunlar Sketchup.write_default ile
#  saklanır ve `all` çağrısında listeye eklenir.
#
#  Profil hash alanları:
#    :code      → ürün kodu (tekil)
#    :name      → görünen ad
#    :width_mm  → genişlik (kesitin yüzeye paralel boyutu)
#    :depth_mm  → derinlik (duvardan dışa çıkan boyut)
#    :length_mm → standart boy (panel yüksekliği için referans)
#    :pattern   → :flat | :v_groove | :u_groove | :ribbed |
#                 :half_round | :double_groove | :reeded | :step | :louver
#    :params    → desene özel parametreler
#    :custom    → true ise kullanıcı tanımlı (silinebilir)
# ----------------------------------------------------------------

require 'json'
require 'sketchup.rb'

module CAWorks
  module CAWallPanel
    module Profiles

      DEFAULT_SECTION = 'caworks_ca_wall_panel'.freeze
      CUSTOM_KEY      = 'custom_profiles_v1'.freeze
      RECENTS_KEY     = 'recent_profile_codes_v1'.freeze
      RECENTS_LIMIT   = 6

      # Birincil depolama: kullanıcı home klasöründe JSON dosyası
      # (Sketchup.write_default'tan daha güvenilir; Türkçe karakter ve
      # uzun string sorunlarına karşı dayanıklı). Defaults eski sürümden
      # gelen veriler için fallback olarak okunur.
      def self.custom_file
        File.join(Dir.home, '.caworks_ca_wall_panel_profiles.json')
      rescue StandardError
        File.join(File.dirname(File.dirname(__FILE__)), '.caworks_custom_profiles.json')
      end

      def self.recents_file
        File.join(Dir.home, '.caworks_ca_wall_panel_recents.json')
      rescue StandardError
        File.join(File.dirname(File.dirname(__FILE__)), '.caworks_recents.json')
      end

      # ------------------------------------------------------------
      #  SON KULLANILANLAR (recently used profile codes)
      # ------------------------------------------------------------
      def self.recent_codes
        json = if File.exist?(recents_file)
                 File.read(recents_file, mode: 'rb:UTF-8') rescue '[]'
               else
                 Sketchup.read_default(DEFAULT_SECTION, RECENTS_KEY, '[]')
               end
        arr = JSON.parse(json) rescue []
        arr.is_a?(Array) ? arr.first(RECENTS_LIMIT) : []
      rescue StandardError
        []
      end

      def self.add_recent(code)
        return unless code.is_a?(String) && !code.empty?
        list = ([code] + recent_codes.reject { |c| c == code }).first(RECENTS_LIMIT)
        json = JSON.generate(list)
        begin
          File.write(recents_file, json, mode: 'wb:UTF-8')
        rescue StandardError
          Sketchup.write_default(DEFAULT_SECTION, RECENTS_KEY, json) rescue nil
        end
        list
      end

      # Yerleşik profil havuzu — kesitler gerçek panel ölçülerine göre
      # ayarlandı. Her isim genel/teknik tanımdır; üretici markası içermez.
      DATA = [
        # — Düz (flat) seri ———————————————————————————————————————
        {
          code: '08126-01', name: 'Düz 8×126', width_mm: 126, depth_mm: 8,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '18126-01', name: 'Düz 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '18120-01', name: 'Düz 18×120', width_mm: 120, depth_mm: 18,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '14150-01', name: 'İnce Düz 14×150', width_mm: 150, depth_mm: 14,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '19200-01', name: 'Geniş Düz 19×200', width_mm: 200, depth_mm: 19,
          length_mm: 2800, pattern: :flat, params: {}
        },
        {
          code: '08215-01', name: 'Geniş Düz 8×215', width_mm: 215, depth_mm: 8,
          length_mm: 2800, pattern: :flat, params: {}
        },

        # — Pahlı Düz (chamfered_edge) ——————————————————————————
        {
          code: '18126-CH', name: 'Pahlı Düz 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :chamfered_edge,
          params: { chamfer: 1.5 }
        },
        {
          code: '18120-CH', name: 'Pahlı Düz 18×120', width_mm: 120, depth_mm: 18,
          length_mm: 2800, pattern: :chamfered_edge,
          params: { chamfer: 1.5 }
        },

        # — V-Kanal seri ——————————————————————————————————————————
        {
          code: '18126-46', name: 'V-Kanal 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :v_groove,
          params: { groove_count: 1, groove_width: 6.0, groove_depth: 3.0 }
        },
        {
          code: '18120-46', name: 'V-Kanal 18×120', width_mm: 120, depth_mm: 18,
          length_mm: 2800, pattern: :v_groove,
          params: { groove_count: 1, groove_width: 6.0, groove_depth: 3.0 }
        },
        {
          code: '22150-46', name: 'Derin V 22×150', width_mm: 150, depth_mm: 22,
          length_mm: 2800, pattern: :v_groove,
          params: { groove_count: 1, groove_width: 10.0, groove_depth: 6.0 }
        },
        {
          code: '18126-CV', name: 'Pahlı V-Kanal 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :chamfered_edge,
          params: { chamfer: 1.5, groove_width: 6.0, groove_depth: 3.0 }
        },

        # — Çift V ————————————————————————————————————————————————
        {
          code: '18126-44', name: 'Çift V-Kanal 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :double_groove,
          params: { groove_count: 2, groove_width: 5.0, groove_depth: 3.0,
                    groove_spacing: 32.0 }
        },

        # — Üçlü V (ribbed_center 3 yiv merkezde) ————————————————
        {
          code: '18126-3V', name: 'Üçlü V-Kanal 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :triple_groove,
          params: { groove_width: 4.0, groove_depth: 2.5, groove_spacing: 14.0 }
        },

        # — U-Kanal —————————————————————————————————————————————
        {
          code: '18126-45', name: 'U-Kanal 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :u_groove,
          params: { groove_count: 1, groove_width: 12.0, groove_depth: 4.0 }
        },

        # — Çoklu Yiv (ribbed) ————————————————————————————————————
        {
          code: '18126-47', name: 'Çoklu Yiv 18×126', width_mm: 126, depth_mm: 18,
          length_mm: 2800, pattern: :ribbed,
          params: { rib_count: 8, rib_depth: 2.0 }
        },

        # — Step (kademeli) ——————————————————————————————————————
        {
          code: '22126-45', name: 'Derin Kademeli 22×126', width_mm: 126, depth_mm: 22,
          length_mm: 2800, pattern: :step,
          params: { step_count: 2, step_depth: 5.0 }
        },

        # — Yarım Yuvarlak / Reeded ——————————————————————————————
        {
          code: '08215-12', name: 'Yarım Yuvarlak 8×215', width_mm: 215, depth_mm: 12,
          length_mm: 2800, pattern: :half_round,
          params: { radius: 6.0 }
        },
        {
          code: '08160-01', name: 'Reeded 8×160', width_mm: 160, depth_mm: 12,
          length_mm: 2800, pattern: :reeded,
          params: { rib_count: 14, rib_radius: 4.0 }
        },

        # — Tongue & Groove (geçmeli) ———————————————————————————
        {
          code: '18120-TG', name: 'Geçmeli Lambri 18×120', width_mm: 120, depth_mm: 18,
          length_mm: 2800, pattern: :tongue_groove,
          params: { tongue_width: 4.0, tongue_height: 6.0 }
        },

        # — Lamel (kare kesit) ————————————————————————————————————
        {
          code: '3030-08', name: 'Lamel 30×30', width_mm: 30, depth_mm: 30,
          length_mm: 2800, pattern: :louver,
          params: {}
        }
      ].freeze

      # ------------------------------------------------------------
      def self.all
        DATA + custom_profiles
      end

      def self.find(code)
        all.find { |p| p[:code].to_s == code.to_s }
      end

      def self.builtin_codes
        DATA.map { |p| p[:code] }.freeze
      end

      def self.builtin?(code)
        builtin_codes.include?(code)
      end

      # ------------------------------------------------------------
      #  CUSTOM PROFIL DEPOLAMA
      # ------------------------------------------------------------
      def self.custom_profiles
        json = read_custom_json
        arr  = JSON.parse(json) rescue nil
        return [] unless arr.is_a?(Array)
        arr.map { |h| symbolize_profile(h) rescue nil }.compact
      rescue StandardError => e
        warn "[CA-Wall Panel] custom_profiles read error: #{e.message}"
        []
      end

      def self.read_custom_json
        # 1) Dosya varsa onu kullan
        path = custom_file
        if File.exist?(path)
          begin
            return File.read(path, mode: 'rb:UTF-8')
          rescue StandardError => e
            warn "[CA-Wall Panel] custom file read failed (#{path}): #{e.message}"
          end
        end
        # 2) Eski Sketchup defaults'tan migrate
        legacy = Sketchup.read_default(DEFAULT_SECTION, CUSTOM_KEY, nil)
        return legacy if legacy.is_a?(String) && !legacy.empty?
        '[]'
      end

      def self.save_custom(profile)
        return [false, 'Profil kodu boş olamaz.'] if profile[:code].to_s.strip.empty?
        return [false, 'Profil adı boş olamaz.']  if profile[:name].to_s.strip.empty?
        if builtin?(profile[:code])
          return [false, "Bu kod yerleşik profil ile çakışıyor: #{profile[:code]}"]
        end
        return [false, 'Genişlik > 0 olmalı.']      if profile[:width_mm].to_f  <= 0
        return [false, 'Derinlik > 0 olmalı.']      if profile[:depth_mm].to_f  <= 0
        return [false, 'Standart boy > 0 olmalı.']  if profile[:length_mm].to_f <= 0

        pattern = (profile[:pattern].respond_to?(:to_sym) ? profile[:pattern].to_sym : :flat) rescue :flat
        cleaned = {
          code:      profile[:code].to_s.strip,
          name:      profile[:name].to_s.strip,
          width_mm:  profile[:width_mm].to_f,
          depth_mm:  profile[:depth_mm].to_f,
          length_mm: profile[:length_mm].to_f,
          pattern:   pattern,
          params:    sanitize_params(pattern, profile[:params] || {}),
          custom:    true
        }

        list = custom_profiles.reject { |p| p[:code] == cleaned[:code] }
        list << cleaned

        ok, err = write_custom(list)
        unless ok
          return [false, "Kaydedilemedi: #{err}"]
        end

        # Doğrulama: dosyayı geri okuyup yeni profilin gerçekten orada olduğunu kontrol et
        verify = custom_profiles.find { |p| p[:code] == cleaned[:code] }
        if verify.nil?
          return [false, "Kayıt sonrası doğrulama başarısız (#{custom_file})"]
        end

        warn "[CA-Wall Panel] custom profile saved: #{cleaned[:code]} (toplam: #{list.size})"
        [true, cleaned]
      end

      def self.delete_custom(code)
        list = custom_profiles.reject { |p| p[:code] == code.to_s }
        ok, err = write_custom(list)
        warn "[CA-Wall Panel] custom profile deleted: #{code} → #{ok ? 'OK' : err}"
        ok
      end

      # Geri dönüş: [ok, error_msg]
      def self.write_custom(list)
        json = JSON.generate(list.map { |p| stringify_profile(p) })

        path = custom_file
        begin
          dir = File.dirname(path)
          require 'fileutils'
          FileUtils.mkdir_p(dir) unless File.directory?(dir)
          File.write(path, json, mode: 'wb:UTF-8')
        rescue StandardError => e
          warn "[CA-Wall Panel] write_custom file failed: #{e.message}"
          # Dosyaya yazılamadı; defaults'a düş
          begin
            Sketchup.write_default(DEFAULT_SECTION, CUSTOM_KEY, json)
            return [true, nil]
          rescue StandardError => e2
            return [false, "Dosya & defaults yazımı başarısız: #{e.message} / #{e2.message}"]
          end
        end

        # Hem dosya hem defaults'a yaz (en iyi senaryo, geriye dönüm yok)
        begin
          Sketchup.write_default(DEFAULT_SECTION, CUSTOM_KEY, json)
        rescue StandardError
          nil # defaults yazılmazsa sorun değil; dosyada var
        end
        [true, nil]
      end

      def self.symbolize_profile(h)
        params = h['params'] || {}
        params_sym = {}
        params.each { |k, v| params_sym[k.to_sym] = v }
        {
          code:      h['code'].to_s,
          name:      h['name'].to_s,
          width_mm:  h['width_mm'].to_f,
          depth_mm:  h['depth_mm'].to_f,
          length_mm: h['length_mm'].to_f,
          pattern:   (h['pattern'] || 'flat').to_sym,
          params:    params_sym,
          custom:    true
        }
      end

      def self.stringify_profile(p)
        {
          'code'      => p[:code],
          'name'      => p[:name],
          'width_mm'  => p[:width_mm],
          'depth_mm'  => p[:depth_mm],
          'length_mm' => p[:length_mm],
          'pattern'   => p[:pattern].to_s,
          'params'    => (p[:params] || {}).each_with_object({}) { |(k, v), o| o[k.to_s] = v }
        }
      end

      def self.sanitize_params(pattern, params)
        h = params.each_with_object({}) { |(k, v), o| o[k.to_sym] = v }
        case pattern
        when :v_groove
          { groove_count: 1,
            groove_width: (h[:groove_width] || 8.0).to_f,
            groove_depth: (h[:groove_depth] || 4.0).to_f }
        when :double_groove
          { groove_count: 2,
            groove_width:   (h[:groove_width]   || 6.0).to_f,
            groove_depth:   (h[:groove_depth]   || 3.5).to_f,
            groove_spacing: (h[:groove_spacing] || 30.0).to_f }
        when :u_groove
          { groove_count: 1,
            groove_width: (h[:groove_width] || 14.0).to_f,
            groove_depth: (h[:groove_depth] || 5.0).to_f }
        when :ribbed
          { rib_count: (h[:rib_count] || 8).to_i,
            rib_depth: (h[:rib_depth] || 3.0).to_f }
        when :half_round
          { radius: (h[:radius] || 6.0).to_f }
        when :step
          { step_count: (h[:step_count] || 2).to_i,
            step_depth: (h[:step_depth] || 6.0).to_f }
        when :reeded
          { rib_count:  (h[:rib_count]  || 14).to_i,
            rib_radius: (h[:rib_radius] || 4.0).to_f }
        when :chamfered_edge
          out = { chamfer: (h[:chamfer] || 1.5).to_f }
          if h[:groove_width].to_f > 0 && h[:groove_depth].to_f > 0
            out[:groove_width] = h[:groove_width].to_f
            out[:groove_depth] = h[:groove_depth].to_f
          end
          out
        when :tongue_groove
          { tongue_width:  (h[:tongue_width]  || 4.0).to_f,
            tongue_height: (h[:tongue_height] || 6.0).to_f }
        when :triple_groove
          { groove_width:   (h[:groove_width]   || 4.0).to_f,
            groove_depth:   (h[:groove_depth]   || 2.5).to_f,
            groove_spacing: (h[:groove_spacing] || 14.0).to_f }
        else
          {}
        end
      end

      # ------------------------------------------------------------
      #  KESİT POLİGON ÜRETİMİ
      #  Geri dönüş: Geom::Point3d dizisi (kapalı poligon, son nokta != ilk).
      #  Birim: inç (SketchUp iç birim). 1 mm = 1.mm helper'ı kullanılır.
      # ------------------------------------------------------------
      def self.build_profile_points(profile)
        w = profile[:width_mm].mm
        d = profile[:depth_mm].mm
        pts = case profile[:pattern]
        when :flat            then flat_points(w, d)
        when :v_groove        then v_groove_points(w, d, profile[:params])
        when :double_groove   then double_groove_points(w, d, profile[:params])
        when :triple_groove   then triple_groove_points(w, d, profile[:params])
        when :u_groove        then u_groove_points(w, d, profile[:params])
        when :ribbed          then ribbed_points(w, d, profile[:params])
        when :half_round      then half_round_points(w, d, profile[:params])
        when :step            then step_points(w, d, profile[:params])
        when :reeded          then reeded_points(w, d, profile[:params])
        when :chamfered_edge  then chamfered_edge_points(w, d, profile[:params])
        when :tongue_groove   then tongue_groove_points(w, d, profile[:params])
        when :louver          then flat_points(w, d)
        else
          flat_points(w, d)
        end
        dedupe_consecutive(pts)
      end

      # Geom::Point3d listesinden ardışık ve uç-uç çakışan noktaları
      # eler — SketchUp.add_face "Duplicate points in array" hatasının
      # önüne geçer.
      def self.dedupe_consecutive(pts, tol_inch = 1.0e-4)
        out = []
        pts.each do |p|
          if out.empty? || (p - out.last).length > tol_inch
            out << p
          end
        end
        if out.size >= 3 && (out.first - out.last).length < tol_inch
          out.pop
        end
        out
      end

      # ============================================================

      def self.flat_points(w, d)
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(0, d, 0)
        ]
      end

      def self.v_groove_points(w, d, p)
        gw = (p[:groove_width] || 8.0).mm
        gd = (p[:groove_depth] || 4.0).mm
        cx = w / 2.0
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(cx + gw / 2.0, d, 0),
          Geom::Point3d.new(cx, d - gd, 0),
          Geom::Point3d.new(cx - gw / 2.0, d, 0),
          Geom::Point3d.new(0, d, 0)
        ]
      end

      def self.double_groove_points(w, d, p)
        gw = (p[:groove_width]   || 6.0).mm
        gd = (p[:groove_depth]   || 3.5).mm
        sp = (p[:groove_spacing] || 30.0).mm
        cx = w / 2.0
        c1 = cx - sp / 2.0
        c2 = cx + sp / 2.0
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(c2 + gw / 2.0, d, 0),
          Geom::Point3d.new(c2, d - gd, 0),
          Geom::Point3d.new(c2 - gw / 2.0, d, 0),
          Geom::Point3d.new(c1 + gw / 2.0, d, 0),
          Geom::Point3d.new(c1, d - gd, 0),
          Geom::Point3d.new(c1 - gw / 2.0, d, 0),
          Geom::Point3d.new(0, d, 0)
        ]
      end

      def self.u_groove_points(w, d, p)
        gw = (p[:groove_width] || 14.0).mm
        gd = (p[:groove_depth] || 5.0).mm
        cx = w / 2.0
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(cx + gw / 2.0, d, 0),
          Geom::Point3d.new(cx + gw / 2.0, d - gd, 0),
          Geom::Point3d.new(cx - gw / 2.0, d - gd, 0),
          Geom::Point3d.new(cx - gw / 2.0, d, 0),
          Geom::Point3d.new(0, d, 0)
        ]
      end

      def self.ribbed_points(w, d, p)
        n  = (p[:rib_count] || 8).to_i
        rd = (p[:rib_depth] || 3.0).mm
        seg = w / n.to_f
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0)
        ]
        (1...n).each do |i|
          x = w - i * seg
          pts << Geom::Point3d.new(x + seg / 2.0, d, 0)
          pts << Geom::Point3d.new(x, d - rd, 0)
        end
        pts << Geom::Point3d.new(seg / 2.0, d, 0)
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      def self.half_round_points(w, d, p)
        r  = (p[:radius] || 6.0).mm
        seg = 16
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0)
        ]
        # i=0'da (cos=1, sin=0) bu nokta zaten eklenmiş (w, d) ile çakışır
        # → 1..seg arasında üret.
        (1...seg).each do |i|
          t   = i / seg.to_f
          ang = t * Math::PI
          x   = w / 2.0 + (w / 2.0) * Math.cos(ang)
          y   = d + r * Math.sin(ang)
          pts << Geom::Point3d.new(x, y, 0)
        end
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      def self.step_points(w, d, p)
        sc = (p[:step_count] || 2).to_i
        sd = (p[:step_depth] || 6.0).mm
        cx = w / 2.0
        step_total = w * 0.5
        sw = step_total / sc.to_f
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0)
        ]
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

      def self.reeded_points(w, d, p)
        n  = (p[:rib_count]  || 14).to_i
        rr = (p[:rib_radius] || 4.0).mm
        seg_per_rib = 8
        rib_w = w / n.to_f
        # rr panel'in yarısından büyükse rib_w/2 ile eşitlenir → ilk
        # rib'in ilk noktası (w, d) ile çakışırdı; r'yi hafif küçültürüz.
        actual_r = [rib_w / 2.0 - 1.0e-4, rr].min
        actual_r = 0.0 if actual_r < 0
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0)
        ]
        (n - 1).downto(0) do |i|
          cx = (i + 0.5) * rib_w
          (0..seg_per_rib).each do |k|
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

      # Üçlü merkez V-yivi (3 V eşit aralıklı, panel ortasında)
      def self.triple_groove_points(w, d, p)
        gw = (p[:groove_width]   || 4.0).mm
        gd = (p[:groove_depth]   || 2.5).mm
        sp = (p[:groove_spacing] || 14.0).mm
        cx = w / 2.0
        c2 = cx + sp
        c0 = cx - sp
        c1 = cx
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0)
        ]
        [c2, c1, c0].each do |c|
          pts << Geom::Point3d.new(c + gw / 2.0, d, 0)
          pts << Geom::Point3d.new(c, d - gd, 0)
          pts << Geom::Point3d.new(c - gw / 2.0, d, 0)
        end
        pts << Geom::Point3d.new(0, d, 0)
        pts
      end

      # Pahlı kenar — panel üst köşeleri 45° pahlı, opsiyonel merkez V yivi.
      # Komşu paneller yan yana geldiğinde aralarında küçük V çizgisi
      # oluşur (gerçek lambri görünümü).
      def self.chamfered_edge_points(w, d, p)
        c  = (p[:chamfer] || 1.5).mm
        # Güvenlik: pah sıfır olamaz, panel boyutunun yarısını da geçemez
        c = 0.5.mm if c < 0.1.mm
        c = [c, w / 2.5, d / 2.0].min
        gw = p[:groove_width].to_f.mm
        gd = p[:groove_depth].to_f.mm
        cx = w / 2.0
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d - c, 0),
          Geom::Point3d.new(w - c, d, 0)
        ]
        if gw > 0 && gd > 0
          pts << Geom::Point3d.new(cx + gw / 2.0, d, 0)
          pts << Geom::Point3d.new(cx, d - gd, 0)
          pts << Geom::Point3d.new(cx - gw / 2.0, d, 0)
        end
        pts << Geom::Point3d.new(c, d, 0)
        pts << Geom::Point3d.new(0, d - c, 0)
        pts
      end

      # Geçmeli (Tongue & Groove): sağ kenarda pim, sol kenarda kanal.
      # Kesit X aralığı [0, w + tongue_width]; chord-walk panel_w = w
      # kullanır → komşu paneller pim/kanal birbirine geçer.
      def self.tongue_groove_points(w, d, p)
        tw = (p[:tongue_width]  || 4.0).mm
        th = (p[:tongue_height] || 6.0).mm
        ty = d / 2.0
        gd_inset = tw + 0.5.mm    # kanal iç sınırı (sol kenardan içeri)
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w,        ty - th / 2.0, 0),
          Geom::Point3d.new(w + tw,   ty - th / 2.0, 0),
          Geom::Point3d.new(w + tw,   ty + th / 2.0, 0),
          Geom::Point3d.new(w,        ty + th / 2.0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(0, d, 0),
          Geom::Point3d.new(0,        ty + th / 2.0, 0),
          Geom::Point3d.new(gd_inset, ty + th / 2.0, 0),
          Geom::Point3d.new(gd_inset, ty - th / 2.0, 0),
          Geom::Point3d.new(0,        ty - th / 2.0, 0)
        ]
      end

    end
  end
end