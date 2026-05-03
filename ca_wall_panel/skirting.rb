# ----------------------------------------------------------------
#  CA-Wall Panel — Süpürgelik (Skirting) Tool
#  ----------------------------------------------------------------
#  Duvar tabanına çekilen süpürgelik (baseboard) hatları:
#  • Path bir veya birden fazla bağlantılı edge (line/arc/curve).
#  • Kesit YZ düzleminde inşa edilir, follow-me ile path boyunca
#    uzatılır → tek bir solid grup oluşur (panel-by-panel değil).
#  • Renk uygulamak için Colorize.apply_to_selection kullanılır.
#  • Metraj: profil + renk bazında toplam uzunluk (m) + alan (m²).
#  • Lambri olsun olmasın, bağımsız uygulanabilir.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module Skirting

      ATTR_DICT      = 'caworks_ca_wall_panel'.freeze
      LAYER_NAME     = 'Süpürgelik'.freeze
      DEFAULT_HEIGHT = 80.0     # mm
      DEFAULT_DEPTH  = 15.0     # mm

      @active_skirting_code = 'SP-MOD-80'

      class << self
        attr_accessor :active_skirting_code
      end

      # ------------------------------------------------------------
      #  KESİT KATALOĞU — yükseklik (z) × derinlik (y).
      #  Cross-section YZ düzleminde, kullanıcı duvar köşesinde
      #  başlar (Y=0 duvar yüzü, Y=d odaya doğru).
      #  pattern: :modern | :chamfer | :round | :step | :ogee | :slim
      # ------------------------------------------------------------
      DATA = [
        {
          code: 'SP-MOD-80',  name: 'Modern Düz 80×12',
          height_mm: 80, depth_mm: 12, length_mm: 2400,
          pattern: :modern, params: {}
        },
        {
          code: 'SP-MOD-100', name: 'Modern Düz 100×15',
          height_mm: 100, depth_mm: 15, length_mm: 2400,
          pattern: :modern, params: {}
        },
        {
          code: 'SP-MOD-150', name: 'Geniş Modern 150×18',
          height_mm: 150, depth_mm: 18, length_mm: 2400,
          pattern: :modern, params: {}
        },
        {
          code: 'SP-CHM-100', name: 'Pahlı Üst 100×15',
          height_mm: 100, depth_mm: 15, length_mm: 2400,
          pattern: :chamfer, params: { chamfer: 8.0 }
        },
        {
          code: 'SP-CHM-120', name: 'Pahlı Üst 120×18',
          height_mm: 120, depth_mm: 18, length_mm: 2400,
          pattern: :chamfer, params: { chamfer: 10.0 }
        },
        {
          code: 'SP-RND-100', name: 'Yuvarlatılmış 100×18',
          height_mm: 100, depth_mm: 18, length_mm: 2400,
          pattern: :round, params: { radius: 14.0 }
        },
        {
          code: 'SP-STP-90',  name: 'Kademeli 90×16',
          height_mm: 90, depth_mm: 16, length_mm: 2400,
          pattern: :step, params: { step_count: 2, step_size: 4.0 }
        },
        {
          code: 'SP-OGE-120', name: 'Klasik Ogee 120×20',
          height_mm: 120, depth_mm: 20, length_mm: 2400,
          pattern: :ogee, params: { bead_radius: 8.0, fillet: 5.0 }
        },
        {
          code: 'SP-SLM-60',  name: 'İnce Slim 60×10',
          height_mm: 60, depth_mm: 10, length_mm: 2400,
          pattern: :slim, params: {}
        }
      ].freeze

      def self.all;        DATA;                                    end
      def self.find(code); DATA.find { |p| p[:code] == code };       end

      # ------------------------------------------------------------
      #  KESİT POLİGON ÜRETİCİLERİ (YZ düzlemi; her noktanın x=0)
      # ------------------------------------------------------------
      def self.build_section_points(profile)
        h = profile[:height_mm].mm
        d = profile[:depth_mm].mm
        pts = case profile[:pattern]
              when :modern  then modern_pts(h, d)
              when :chamfer then chamfer_pts(h, d, profile[:params])
              when :round   then round_pts(h, d, profile[:params])
              when :step    then step_pts(h, d, profile[:params])
              when :ogee    then ogee_pts(h, d, profile[:params])
              when :slim    then modern_pts(h, d)
              else
                modern_pts(h, d)
              end
        Profiles.dedupe_consecutive(pts)
      end

      def self.modern_pts(h, d)
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(0, d, 0),
          Geom::Point3d.new(0, d, h),
          Geom::Point3d.new(0, 0, h)
        ]
      end

      def self.chamfer_pts(h, d, p)
        c = (p[:chamfer] || 8.0).mm
        c = [c, h * 0.5, d * 0.9].min
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(0, d, 0),
          Geom::Point3d.new(0, d, h - c),
          Geom::Point3d.new(0, 0, h)
        ]
      end

      def self.round_pts(h, d, p)
        r = (p[:radius] || 12.0).mm
        r = [r, h * 0.5, d].min
        seg = 12
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(0, d, 0),
          Geom::Point3d.new(0, d, h - r)
        ]
        # Çeyrek daire: front-üst köşeden iç-üst köşeye doğru
        # merkez (d - r, h - r), yarıçap r
        (1..seg).each do |i|
          t   = i / seg.to_f
          ang = t * Math::PI / 2.0
          y   = (d - r) + r * Math.cos(ang)
          z   = (h - r) + r * Math.sin(ang)
          pts << Geom::Point3d.new(0, y, z)
        end
        pts
      end

      def self.step_pts(h, d, p)
        sc = (p[:step_count] || 2).to_i
        ss = (p[:step_size]  || 4.0).mm
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(0, d, 0)
        ]
        # Kademeli üst — her kademe (ss × ss) küçülür
        cur_y = d
        cur_z = h
        sc.times do |i|
          # Yukarı + içeri
          step_h = ss
          pts << Geom::Point3d.new(0, cur_y, cur_z - step_h)
          pts << Geom::Point3d.new(0, cur_y - ss, cur_z - step_h)
          cur_y -= ss
          cur_z -= 0
        end
        pts << Geom::Point3d.new(0, cur_y, h)
        pts << Geom::Point3d.new(0, 0, h)
        pts
      end

      def self.ogee_pts(h, d, p)
        # Klasik S-eğri (ogee) — basitleştirilmiş: konkav fillet alttan,
        # konveks bead üstten. Toplam birkaç parça arc.
        br = (p[:bead_radius] || 8.0).mm
        fr = (p[:fillet]      || 5.0).mm
        br = [br, h * 0.3].min
        fr = [fr, h * 0.2].min

        seg = 8
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(0, d, 0),
          # Ön yüzeyden yukarı çıkış (düz bölüm)
          Geom::Point3d.new(0, d, h - br - fr * 1.5)
        ]
        # Konkav fillet (içeri çekilir)
        cy_f = d - fr
        cz_f = h - br - fr * 0.5
        (1..seg).each do |i|
          t = i / seg.to_f
          ang = t * (Math::PI / 2.0)
          y = cy_f + fr * Math.cos(ang + Math::PI / 2.0)
          z = cz_f + fr * Math.sin(ang + Math::PI / 2.0)
          pts << Geom::Point3d.new(0, y, z)
        end
        # Konveks bead (dışarı çıkıp tepeye)
        cy_b = d - fr - br
        cz_b = h - br
        (1..seg).each do |i|
          t = i / seg.to_f
          ang = t * (Math::PI / 2.0)
          y = cy_b + br * Math.cos(-ang)
          z = cz_b + br * Math.sin(ang)
          pts << Geom::Point3d.new(0, y, z)
        end
        pts << Geom::Point3d.new(0, 0, h)
        pts
      end

      # ============================================================
      #  UYGULAMA AKIŞI
      # ============================================================
      def self.run(skirting_code = nil, room_name = nil)
        model = Sketchup.active_model
        sel   = model.selection.to_a.select { |e| e.is_a?(Sketchup::Edge) }
        if sel.empty?
          UI.messagebox("Önce süpürgelik hattı için çizgi(ler) seçin.")
          return
        end

        code    = skirting_code || @active_skirting_code
        profile = find(code) || DATA.first
        return unless profile

        ordered = ApplyTool.order_edges(sel)
        if ordered.nil? || ordered.empty?
          UI.messagebox("Seçili edge'ler birbirine bağlı tek bir path oluşturmuyor.")
          return
        end

        parent_entities = ordered.first.parent.entities
        unless ordered.all? { |e| e.parent.entities == parent_entities }
          UI.messagebox("Seçili edge'ler aynı bağlamda olmalı.")
          return
        end

        path_pts = ApplyTool.polyline_points_from_edges(ordered)
        return if path_pts.size < 2
        total_len_inch = total_polyline_length(path_pts)

        @active_skirting_code = code
        execute_build(model, parent_entities, ordered, path_pts, profile, total_len_inch, room_name)
      end

      def self.total_polyline_length(pts)
        len = 0.0
        (0...(pts.size - 1)).each do |i|
          len += (pts[i + 1] - pts[i]).length
        end
        len
      end

      def self.execute_build(model, parent_entities, ordered_edges, path_pts, profile, total_len_inch, room_name)
        model.start_operation('Süpürgelik Uygula', true)
        begin
          run_group = parent_entities.add_group
          run_group.name = "Süpürgelik · #{profile[:code]}"

          # Layer
          layer = model.layers[LAYER_NAME] || model.layers.add(LAYER_NAME)
          run_group.layer = layer

          # Default material
          mat = model.materials['CAWallPanel_Skirting_Default'] ||
                model.materials.add('CAWallPanel_Skirting_Default')
          mat.color = Sketchup::Color.new(250, 250, 248)
          run_group.material = mat

          ok = build_solid(run_group, ordered_edges, path_pts, profile)
          unless ok
            run_group.erase! if run_group.valid?
            model.abort_operation
            UI.messagebox("Süpürgelik oluşturulamadı.")
            return nil
          end

          path_array = path_pts.flat_map { |p| [p.x.to_f, p.y.to_f, p.z.to_f] }
          run_group.set_attribute(ATTR_DICT, 'is_skirting',     true)
          run_group.set_attribute(ATTR_DICT, 'skirting_code',   profile[:code])
          run_group.set_attribute(ATTR_DICT, 'skirting_name',   profile[:name])
          run_group.set_attribute(ATTR_DICT, 'height_mm',       profile[:height_mm].to_f)
          run_group.set_attribute(ATTR_DICT, 'depth_mm',        profile[:depth_mm].to_f)
          run_group.set_attribute(ATTR_DICT, 'length_mm',       profile[:length_mm].to_f)
          run_group.set_attribute(ATTR_DICT, 'total_length_mm', (total_len_inch / 1.mm))
          run_group.set_attribute(ATTR_DICT, 'path_points',     path_array)
          if room_name && !room_name.to_s.strip.empty?
            run_group.set_attribute(ATTR_DICT, 'room_name', room_name.to_s.strip)
          end
          rn  = run_group.get_attribute(ATTR_DICT, 'room_name').to_s
          rns = rn.empty? ? '' : " · #{rn}"
          run_group.name = "Süpürgelik · #{profile[:code]}#{rns} · " \
                           "#{(total_len_inch / 1.mm / 1000.0).round(2)} m"

          model.commit_operation
          model.selection.clear
          model.selection.add(run_group)
          run_group
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Hata: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
          nil
        end
      end

      def self.build_solid(run_group, ordered_edges, path_pts, profile)
        # Path başlangıç noktası ve yönü
        start_pt = path_pts.first
        next_pt  = path_pts[1]
        return false unless start_pt && next_pt

        tangent = next_pt - start_pt
        return false if tangent.length < 1.0e-9
        tangent.normalize!

        z_up = Geom::Vector3d.new(0, 0, 1)
        # X axis: tangent yatay bileşeni — duvar boyunca
        # Y axis: duvardan dışa (tangent ile dik, yatay)
        y_axis = z_up * tangent
        if y_axis.length < 1.0e-9
          y_axis = Geom::Vector3d.new(0, 1, 0)
        else
          y_axis.normalize!
        end

        # Kesiti modele kopyala (path başlangıcında, YZ düzleminde inşa
        # edilen 2D nokta listesini path tangentine göre yönlendir)
        local_pts = build_section_points(profile)
        world_pts = local_pts.map do |lp|
          # lp.y → y_axis (depth), lp.z → z_up (height)
          p = start_pt
          if lp.y.abs > 1.0e-9
            v = y_axis.clone; v.length = lp.y
            p = p.offset(v)
          end
          if lp.z.abs > 1.0e-9
            v = z_up.clone; v.length = lp.z
            p = p.offset(v)
          end
          p
        end

        # Path edge'lerini run_group'un içine kopyala (follow-me için
        # gerekli — original edge'lerin parent'ı dışarıda)
        edge_pts_copy = run_group.entities.add_curve(path_pts)
        return false if edge_pts_copy.nil? || edge_pts_copy.empty?

        face = run_group.entities.add_face(world_pts)
        return false if face.nil?

        # Kesit normal'ını path tangentiyle aynı yapalım
        if face.normal.dot(tangent) < 0
          face.reverse!
        end

        success = face.followme(edge_pts_copy)
        unless success
          face.erase! if face.valid?
          edge_pts_copy.each { |e| e.erase! if e.valid? } rescue nil
          return false
        end

        # Path edge'leri (artık fazlalık) sil
        edge_pts_copy.each { |e| e.erase! if e.valid? }
        true
      rescue StandardError => err
        warn "[Süpürgelik] build_solid hatası: #{err.message}"
        false
      end

      # ============================================================
      #  YARDIMCI: skirting? + selected
      # ============================================================
      def self.skirting?(group)
        group.is_a?(Sketchup::Group) &&
          group.get_attribute(ATTR_DICT, 'is_skirting') == true
      end

      def self.find_selected
        Sketchup.active_model.selection.to_a.find { |e| skirting?(e) }
      end

      # ============================================================
      #  Tüm modeldeki süpürgelikleri topla (Metraj için)
      # ============================================================
      def self.collect_all(model = Sketchup.active_model)
        out = []
        walk(model.entities) do |e|
          next unless skirting?(e)
          mat = e.material
          mat_name = e.get_attribute(ATTR_DICT, 'material_name').to_s
          mat_name = mat.name if mat_name.empty? && mat
          mat_name = '— Varsayılan —' if mat_name.empty?
          mat_rgb = e.get_attribute(ATTR_DICT, 'material_rgb')
          if (!mat_rgb.is_a?(Array) || mat_rgb.empty?) && mat && mat.color
            mat_rgb = [mat.color.red, mat.color.green, mat.color.blue]
          end
          mat_rgb ||= [250, 250, 248]

          out << {
            group:           e,
            skirting_code:   e.get_attribute(ATTR_DICT, 'skirting_code').to_s,
            skirting_name:   e.get_attribute(ATTR_DICT, 'skirting_name').to_s,
            height_mm:       e.get_attribute(ATTR_DICT, 'height_mm').to_f,
            depth_mm:        e.get_attribute(ATTR_DICT, 'depth_mm').to_f,
            length_mm:       e.get_attribute(ATTR_DICT, 'length_mm').to_f,
            total_length_mm: e.get_attribute(ATTR_DICT, 'total_length_mm').to_f,
            room_name:       e.get_attribute(ATTR_DICT, 'room_name').to_s,
            material_name:   mat_name,
            material_rgb:    mat_rgb
          }
        end
        out
      end

      def self.walk(entities, &block)
        entities.each do |e|
          yield e
          if e.is_a?(Sketchup::Group)
            next if e.get_attribute(ATTR_DICT, 'is_skirting') == true
            next if e.get_attribute(ATTR_DICT, 'is_panel_run') == true
            walk(e.entities, &block)
          end
        end
      end

    end
  end
end