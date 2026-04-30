# ----------------------------------------------------------------
#  CA-Wall Panel — Apply Tool (v0.2.0)
#  Kullanıcı bir veya daha fazla bağlantılı edge (line/arc/circle/curve)
#  seçer ve diyalogda bir yükseklik girer; aktif profile göre, çizgi
#  boyunca panel genişliği adımlarla yan yana dik panel grupları
#  oluşturulur. Her panel kendi alt grubu olarak yerleştirilir, hepsi
#  ortak bir CA-Wall Panel grubunda toplanır.
#
#  Geometri: profil kesiti yatay düzlemde (path tanjantı = X, dik
#  yatay normal = Y) kurulur, ardından pushpull ile yukarı (+Z)
#  yükseklik kadar extrude edilir.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module ApplyTool

      ATTR_DICT         = 'caworks_ca_wall_panel'.freeze
      DEFAULT_HEIGHT_MM = 2800.0

      @active_profile_code = '18126-46'
      @flip_orientation    = false
      @last_height_mm      = DEFAULT_HEIGHT_MM

      class << self
        attr_accessor :active_profile_code, :flip_orientation, :last_height_mm
      end

      # ------------------------------------------------------------
      #  GİRİŞ
      # ------------------------------------------------------------
      def self.run(height_mm = nil)
        model = Sketchup.active_model
        sel   = model.selection.to_a.select { |e| e.is_a?(Sketchup::Edge) }

        if sel.empty?
          UI.messagebox("Önce uygulanacak çizgi(ler)i seçin.\n\n"\
                        "Tek bir çizgi, bir yay (arc), bir daire veya birbirine "\
                        "bağlı edge'lerden oluşan bir polyline / freehand seçebilirsiniz.")
          return
        end

        profile = Profiles.find(@active_profile_code)
        unless profile
          UI.messagebox("Aktif profil bulunamadı: #{@active_profile_code}")
          return
        end

        h_mm = (height_mm || @last_height_mm).to_f
        if h_mm <= 0
          UI.messagebox("Geçerli bir yükseklik girin.")
          return
        end

        max_mm = profile[:length_mm].to_f
        if h_mm > max_mm
          answer = UI.messagebox(
            "Malzeme boyutunu geçtiniz!\n\n" \
            "Girilen yükseklik     : #{h_mm.round} mm\n" \
            "Profil standart boyu  : #{max_mm.round} mm\n\n" \
            "Bu boyda tek parça malzeme bulunmayabilir; uygulamada birden fazla "\
            "parça gerekecektir.\n\nYine de devam edilsin mi?",
            MB_YESNO
          )
          return if answer == IDNO
        end

        @last_height_mm = h_mm

        ordered = order_edges(sel)
        if ordered.nil? || ordered.empty?
          UI.messagebox("Seçili edge'ler birbirine bağlı tek bir path "\
                        "oluşturmuyor. Lütfen bağlantılı edge'leri seçin.")
          return
        end

        parent_entities = ordered.first.parent.entities
        unless ordered.all? { |e| e.parent.entities == parent_entities }
          UI.messagebox("Seçili edge'ler farklı bağlamlarda (grup/component) "\
                        "olamaz. Hepsi aynı düzeyde olmalı.")
          return
        end

        model.start_operation('CA-Wall Panel Uygula', true)
        begin
          group = build_panels_along_path(model, parent_entities, ordered, profile, h_mm)
          if group
            model.selection.clear
            model.selection.add(group)
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Hata: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
        end
      end

      # ------------------------------------------------------------
      #  EDGE SIRALAMA
      # ------------------------------------------------------------
      def self.order_edges(edges)
        return [] if edges.empty?
        return edges if edges.size == 1

        adjacency = Hash.new { |h, k| h[k] = [] }
        edges.each do |e|
          adjacency[pt_key(e.start.position)] << e
          adjacency[pt_key(e.end.position)]   << e
        end

        endpoint_keys = adjacency.select { |_, es| es.size == 1 }.keys

        if endpoint_keys.any?
          ordered = []
          visited = {}
          current_key = endpoint_keys.first
          while ordered.size < edges.size
            candidates = adjacency[current_key].reject { |e| visited[e] }
            break if candidates.empty?
            edge          = candidates.first
            visited[edge] = true
            ordered      << edge
            other = (pt_key(edge.start.position) == current_key) ?
                    edge.end.position : edge.start.position
            current_key = pt_key(other)
          end
          return ordered.size == edges.size ? ordered : nil
        end

        ordered = []
        visited = {}
        edge    = edges.first
        ordered << edge
        visited[edge] = true
        current_key = pt_key(edge.end.position)
        while ordered.size < edges.size
          candidates = adjacency[current_key].reject { |e| visited[e] }
          break if candidates.empty?
          edge          = candidates.first
          visited[edge] = true
          ordered      << edge
          other = (pt_key(edge.start.position) == current_key) ?
                  edge.end.position : edge.start.position
          current_key = pt_key(other)
        end
        ordered.size == edges.size ? ordered : nil
      end

      def self.pt_key(pt, tol = 1.0e-3)
        format('%.4f,%.4f,%.4f', (pt.x / tol).round * tol,
                                  (pt.y / tol).round * tol,
                                  (pt.z / tol).round * tol)
      end

      # ------------------------------------------------------------
      #  PATH ÖRNEKLEME — yürüyüş yönüne göre segment listesi
      #  (eğri/yayda her edge ayrı segment, kümülatif uzunluk hesaplı)
      # ------------------------------------------------------------
      def self.compute_walk_segments(ordered_edges)
        return [] if ordered_edges.empty?

        if ordered_edges.size == 1
          e = ordered_edges.first
          a = e.start.position; b = e.end.position
          return [{ a: a, b: b, length: (b - a).length, cum_start: 0.0 }]
        end

        segments   = []
        cumulative = 0.0

        e1  = ordered_edges[0]
        e2  = ordered_edges[1]
        e1s = e1.start.position
        e1e = e1.end.position
        if pt_key(e1e) == pt_key(e2.start.position) ||
           pt_key(e1e) == pt_key(e2.end.position)
          a = e1s; b = e1e
        else
          a = e1e; b = e1s
        end
        len = (b - a).length
        segments << { a: a, b: b, length: len, cum_start: 0.0 }
        cumulative += len
        prev_end = b

        ordered_edges[1..-1].each do |e|
          es = e.start.position; ee = e.end.position
          if pt_key(es) == pt_key(prev_end)
            a = es; b = ee
          else
            a = ee; b = es
          end
          len = (b - a).length
          segments << { a: a, b: b, length: len, cum_start: cumulative }
          cumulative += len
          prev_end = b
        end

        segments
      end

      def self.sample_at_distance(segments, d)
        segments.each do |seg|
          if d <= seg[:cum_start] + seg[:length] + 1.0e-9
            t = seg[:length] > 1.0e-12 ? (d - seg[:cum_start]) / seg[:length] : 0.0
            t = 0.0 if t < 0.0
            t = 1.0 if t > 1.0
            pos = Geom::Point3d.linear_combination(1.0 - t, seg[:a], t, seg[:b])
            tan = seg[:b] - seg[:a]
            tan.length = 1.0 if tan.length > 1.0e-12
            return [pos, tan]
          end
        end
        last = segments.last
        tan  = last[:b] - last[:a]
        tan.length = 1.0 if tan.length > 1.0e-12
        [last[:b], tan]
      end

      # ------------------------------------------------------------
      #  ANA İNŞA — path boyunca panelleri yan yana yerleştir
      # ------------------------------------------------------------
      def self.build_panels_along_path(model, entities, ordered_edges, profile, height_mm)
        segments = compute_walk_segments(ordered_edges)
        return nil if segments.empty?

        total_len_inch = segments.sum { |s| s[:length] }
        panel_w_inch   = profile[:width_mm].mm
        height_inch    = height_mm.mm

        if total_len_inch < panel_w_inch
          UI.messagebox(
            "Çizgi en az bir panel boyu (#{profile[:width_mm]}mm) olmalı.\n" \
            "Seçili path uzunluğu: #{(total_len_inch / 1.mm).round} mm"
          )
          return nil
        end

        panel_count = (total_len_inch / panel_w_inch).floor
        local_pts   = Profiles.build_profile_points(profile)

        panel_groups = []

        panel_count.times do |i|
          d_start = i * panel_w_inch
          pos, tangent = sample_at_distance(segments, d_start)
          pg = place_panel(entities, pos, tangent, local_pts, profile, height_inch)
          panel_groups << pg if pg
        end

        return nil if panel_groups.empty?

        parent = entities.add_group(panel_groups)
        parent.name = "CA-Wall Panel #{profile[:code]} " \
                      "(#{panel_groups.size}× #{profile[:width_mm]}×#{profile[:depth_mm]}mm, " \
                      "h=#{height_mm.round}mm)"

        parent.set_attribute(ATTR_DICT, 'profile_code', profile[:code])
        parent.set_attribute(ATTR_DICT, 'profile_name', profile[:name])
        parent.set_attribute(ATTR_DICT, 'width_mm',    profile[:width_mm])
        parent.set_attribute(ATTR_DICT, 'depth_mm',    profile[:depth_mm])
        parent.set_attribute(ATTR_DICT, 'height_mm',   height_mm)
        parent.set_attribute(ATTR_DICT, 'panel_count', panel_groups.size)

        apply_default_material(parent)

        parent
      end

      # ------------------------------------------------------------
      #  TEK PANEL — yatay düzlemde profil kesiti + yukarı pushpull
      # ------------------------------------------------------------
      def self.place_panel(entities, pos, tangent, local_pts, profile, height_inch)
        t_h = Geom::Vector3d.new(tangent.x, tangent.y, 0)
        if t_h.length < 1.0e-9
          t_h = Geom::Vector3d.new(1, 0, 0)
        else
          t_h.normalize!
        end

        z = Geom::Vector3d.new(0, 0, 1)
        n = t_h * z
        if n.length < 1.0e-9
          n = Geom::Vector3d.new(0, 1, 0)
        else
          n.normalize!
        end
        n.reverse! if @flip_orientation

        base_pts = local_pts.map do |lp|
          p = pos
          p = offset_pt(p, t_h, lp.x)
          p = offset_pt(p, n,   lp.y)
          p
        end

        panel_group = entities.add_group
        panel_ents  = panel_group.entities

        face = panel_ents.add_face(base_pts)
        if face.nil?
          panel_group.erase! if panel_group.valid?
          return nil
        end

        z_up = Geom::Vector3d.new(0, 0, 1)
        face.reverse! if face.normal.dot(z_up) < 0

        face.pushpull(height_inch)

        panel_group.name = profile[:code]
        panel_group
      end

      def self.offset_pt(p, vec, amount)
        return p if amount.abs < 1.0e-9
        v = vec.clone
        v.length = amount.abs
        v.reverse! if amount < 0
        p.offset(v)
      end

      def self.apply_default_material(group)
        model = Sketchup.active_model
        mat   = model.materials['CAWallPanel_Default'] ||
                model.materials.add('CAWallPanel_Default')
        mat.color = Sketchup::Color.new(245, 245, 240)
        group.material = mat
      end

    end
  end
end