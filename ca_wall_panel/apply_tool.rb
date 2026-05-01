# ----------------------------------------------------------------
#  CA-Wall Panel — Apply Tool (v0.3.0)
#  ----------------------------------------------------------------
#  Çizgi/yay/daire/curve seçimi (veya draw_tool ile çizilen polyline)
#  üzerinde, panel genişliği adımlarıyla **chord-tabanlı** yürüyüş
#  yaparak komşu panellerin tam uç-uca değdiği bir hat oluşturur.
#
#  Her panel: profil+yükseklik için lazy-create edilen
#  Components.get_or_create ile tanımlı bir ComponentInstance.
#  Tüm instance'lar tek bir "Lambri Hattı" Group'unda toplanır.
#  Run group attribute'larında profil kodu, yükseklik, flip ve
#  ham path noktaları saklanır → Düzenle akışında yeniden üretim.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module ApplyTool

      ATTR_DICT         = 'caworks_ca_wall_panel'.freeze
      DEFAULT_HEIGHT_MM = 2800.0

      @active_profile_code = '18126-46'
      @flip_orientation    = false
      @last_height_mm      = DEFAULT_HEIGHT_MM
      @editing_run         = nil
      @last_status         = nil

      class << self
        attr_accessor :active_profile_code, :flip_orientation, :last_height_mm,
                      :editing_run, :last_status
      end

      # ============================================================
      #  GİRİŞ NOKTALARI
      # ============================================================

      # Seçimden uygula (mevcut ana akış)
      def self.run(height_mm = nil)
        @editing_run = nil
        @last_status = nil

        model = Sketchup.active_model
        sel   = model.selection.to_a.select { |e| e.is_a?(Sketchup::Edge) }

        if sel.empty?
          UI.messagebox("Önce uygulanacak çizgi(ler)i seçin.\n\n"\
                        "Tek bir çizgi, bir yay (arc), bir daire veya birbirine "\
                        "bağlı edge'lerden oluşan bir polyline / freehand seçebilirsiniz.\n\n"\
                        "Veya \"Kalem ile Çiz\" aracını kullanabilirsiniz.")
          return
        end

        profile = Profiles.find(@active_profile_code) || Profiles.all.first
        return unless profile_ok?(profile)
        return unless height_ok?(height_mm, profile)

        ordered = order_edges(sel)
        if ordered.nil? || ordered.empty?
          UI.messagebox("Seçili edge'ler birbirine bağlı tek bir path oluşturmuyor.")
          return
        end

        parent_entities = ordered.first.parent.entities
        unless ordered.all? { |e| e.parent.entities == parent_entities }
          UI.messagebox("Seçili edge'ler aynı bağlamda olmalı (grup/component karışık olamaz).")
          return
        end

        path_pts = polyline_points_from_edges(ordered)
        return if path_pts.size < 2

        execute_build(model, parent_entities, path_pts, profile, @last_height_mm, @flip_orientation)
      end

      # Verilen edge listesinden uygula (DrawTool tarafından çağrılır)
      def self.run_from_edges(edges, height_mm, flip)
        @editing_run = nil
        return if edges.nil? || edges.empty?

        profile = Profiles.find(@active_profile_code) || Profiles.all.first
        return unless profile_ok?(profile)
        return unless height_ok?(height_mm, profile)
        @flip_orientation = flip

        ordered = order_edges(edges)
        return if ordered.nil? || ordered.empty?

        parent_entities = ordered.first.parent.entities
        path_pts = polyline_points_from_edges(ordered)
        return if path_pts.size < 2

        model = Sketchup.active_model
        execute_build(model, parent_entities, path_pts, profile, @last_height_mm, @flip_orientation)
      end

      # Mevcut bir Lambri Hattı'nı düzenle: aynı path üzerinde yeni
      # profil/yükseklik/flip ile yeniden üret
      def self.regenerate_run(run_group, profile, height_mm, flip)
        return unless panel_run?(run_group)

        pts_arr = run_group.get_attribute(ATTR_DICT, 'path_points')
        unless pts_arr.is_a?(Array) && pts_arr.size >= 6
          UI.messagebox("Bu hatın orijinal yol verisi bulunamadı. Yeniden çizmeniz gerekir.")
          return
        end

        path_pts = []
        i = 0
        while i + 2 < pts_arr.size
          path_pts << Geom::Point3d.new(pts_arr[i], pts_arr[i + 1], pts_arr[i + 2])
          i += 3
        end

        return unless profile_ok?(profile)
        return unless height_ok?(height_mm, profile)

        model = Sketchup.active_model

        @last_height_mm      = height_mm.to_f
        @active_profile_code = profile[:code]
        @flip_orientation    = !!flip

        parent_entities = run_group.parent.is_a?(Sketchup::ComponentDefinition) ?
                          run_group.parent.entities :
                          model.entities

        model.start_operation('CA-Wall Panel Düzenle', true)
        begin
          run_group.entities.clear!
          assign_lambri_layer(model, run_group)
          apply_default_material(model, run_group) unless run_group.material
          fill_run_group(run_group, path_pts, profile, height_mm.to_f, !!flip)
          model.commit_operation
          model.selection.clear
          model.selection.add(run_group)
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Düzenleme hatası: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
        end
      end

      # ============================================================
      #  ORTAK
      # ============================================================

      def self.profile_ok?(profile)
        unless profile
          UI.messagebox("Aktif profil bulunamadı.")
          return false
        end
        true
      end

      def self.height_ok?(height_mm, profile)
        h_mm = (height_mm || @last_height_mm).to_f
        if h_mm <= 0
          UI.messagebox("Geçerli bir yükseklik girin.")
          return false
        end
        max_mm = profile[:length_mm].to_f
        if max_mm > 0 && h_mm > max_mm
          answer = UI.messagebox(
            "Malzeme boyutunu geçtiniz!\n\n" \
            "Girilen yükseklik    : #{h_mm.round} mm\n" \
            "Profil standart boyu : #{max_mm.round} mm\n\n" \
            "Bu boyda tek parça malzeme bulunmayabilir; uygulamada birden fazla "\
            "parça gerekecektir.\n\nYine de devam edilsin mi?",
            MB_YESNO
          )
          return false if answer == IDNO
        end
        @last_height_mm = h_mm
        true
      end

      def self.execute_build(model, parent_entities, path_pts, profile, height_mm, flip)
        model.start_operation('CA-Wall Panel Uygula', true)
        begin
          run_group = parent_entities.add_group
          run_group.name = "Lambri Hattı · #{profile[:code]} · h#{height_mm.round}mm"
          assign_lambri_layer(model, run_group)
          apply_default_material(model, run_group)
          fill_run_group(run_group, path_pts, profile, height_mm, flip)

          if run_group.entities.length == 0
            run_group.erase! if run_group.valid?
            model.abort_operation
            UI.messagebox("Hat oluşturulamadı.")
            return nil
          end

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

      def self.assign_lambri_layer(model, group)
        layer = model.layers['Lambri'] || model.layers.add('Lambri')
        group.layer = layer
      rescue StandardError
        nil
      end

      def self.apply_default_material(model, group)
        return if group.material
        mat = model.materials['CAWallPanel_Default'] ||
              model.materials.add('CAWallPanel_Default')
        mat.color = Sketchup::Color.new(245, 245, 240)
        group.material = mat
      end

      def self.fill_run_group(run_group, path_pts, profile, height_mm, flip)
        segments = segments_from_polyline(path_pts)
        return if segments.empty?

        panel_w_inch = profile[:width_mm].mm
        total_len    = segments.sum { |s| s[:length] }

        if total_len < panel_w_inch
          UI.messagebox(
            "Çizgi en az bir panel boyu (#{profile[:width_mm]}mm) olmalı.\n" \
            "Seçili path uzunluğu: #{(total_len / 1.mm).round} mm"
          )
          return
        end

        chord_pts = walk_chord_points(segments, panel_w_inch)
        return if chord_pts.size < 2

        defn = Components.get_or_create(profile, height_mm)
        z_up = Geom::Vector3d.new(0, 0, 1)

        placed = 0
        (0...(chord_pts.size - 1)).each do |i|
          p_a = chord_pts[i]
          p_b = chord_pts[i + 1]

          x_axis = p_b - p_a
          next if x_axis.length < 1.0e-9
          x_axis.normalize!

          y_axis = z_up * x_axis
          if y_axis.length < 1.0e-9
            y_axis = Geom::Vector3d.new(0, 1, 0)
          else
            y_axis.normalize!
          end
          y_axis.reverse! if flip

          # z-axis daima global yukarı — panel her zaman yukarı extrude.
          # flip durumunda x,y left-handed olur; SU bunu yansıma olarak işler,
          # ki bu da "panelin path'in diğer tarafına yerleştirilmesi" demek.
          tr = Geom::Transformation.axes(p_a, x_axis, y_axis, z_up)
          inst = run_group.entities.add_instance(defn, tr)
          inst.name = "Panel #{placed + 1}"
          placed += 1
        end

        return if placed.zero?

        path_array = path_pts.flat_map { |p| [p.x.to_f, p.y.to_f, p.z.to_f] }
        run_group.set_attribute(ATTR_DICT, 'is_panel_run', true)
        run_group.set_attribute(ATTR_DICT, 'profile_code', profile[:code])
        run_group.set_attribute(ATTR_DICT, 'profile_name', profile[:name])
        run_group.set_attribute(ATTR_DICT, 'height_mm',    height_mm.to_f)
        run_group.set_attribute(ATTR_DICT, 'flip',         !!flip)
        run_group.set_attribute(ATTR_DICT, 'panel_count',  placed)
        run_group.set_attribute(ATTR_DICT, 'width_mm',     profile[:width_mm].to_f)
        run_group.set_attribute(ATTR_DICT, 'depth_mm',     profile[:depth_mm].to_f)
        run_group.set_attribute(ATTR_DICT, 'length_mm',    profile[:length_mm].to_f)
        run_group.set_attribute(ATTR_DICT, 'path_points',  path_array)
        run_group.name = "Lambri Hattı · #{profile[:code]} · #{placed}× h#{height_mm.round}mm"
        @last_status = "#{placed} panel yerleştirildi (#{profile[:code]})"
      end

      def self.panel_run?(group)
        group.is_a?(Sketchup::Group) &&
          group.get_attribute(ATTR_DICT, 'is_panel_run') == true
      end

      def self.find_selected_run
        sel = Sketchup.active_model.selection.to_a
        sel.find { |e| panel_run?(e) }
      end

      # ============================================================
      #  EDGE → POLYLINE
      # ============================================================
      def self.polyline_points_from_edges(ordered_edges)
        return [] if ordered_edges.empty?

        if ordered_edges.size == 1
          e = ordered_edges.first
          return [e.start.position, e.end.position]
        end

        pts = []
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
        pts << a << b
        prev_end = b

        ordered_edges[1..-1].each do |e|
          es = e.start.position; ee = e.end.position
          if pt_key(es) == pt_key(prev_end)
            pts << ee
            prev_end = ee
          else
            pts << es
            prev_end = es
          end
        end

        pts
      end

      def self.segments_from_polyline(pts)
        segs = []
        cumulative = 0.0
        (0...(pts.size - 1)).each do |i|
          a = pts[i]; b = pts[i + 1]
          len = (b - a).length
          next if len < 1.0e-12
          segs << { a: a, b: b, length: len, cum_start: cumulative }
          cumulative += len
        end
        segs
      end

      # ============================================================
      #  EDGE SIRALAMA
      # ============================================================
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

      # ============================================================
      #  CHORD-TABANLI YÜRÜYÜŞ — komşu paneller arası tam uç-uca
      # ============================================================
      def self.walk_chord_points(segments, chord_dist)
        return [] if segments.empty? || chord_dist <= 0

        pts     = [segments.first[:a]]
        current = segments.first[:a]
        seg_idx = 0
        local_t = 0.0

        loop do
          np, ni, nt = find_next_chord(segments, seg_idx, local_t, current, chord_dist)
          break if np.nil?
          pts << np
          current = np
          seg_idx = ni
          local_t = nt
        end

        pts
      end

      def self.find_next_chord(segments, start_idx, start_t, center, radius)
        idx = start_idx
        while idx < segments.size
          seg = segments[idx]
          a = seg[:a]; b = seg[:b]
          d_vec  = b - a
          a_co   = d_vec.dot(d_vec)
          if a_co < 1.0e-12
            idx += 1
            next
          end
          offset = a - center
          b_co   = 2.0 * offset.dot(d_vec)
          c_co   = offset.dot(offset) - radius * radius
          disc   = b_co * b_co - 4.0 * a_co * c_co
          if disc < 0
            idx += 1
            next
          end
          sd     = Math.sqrt(disc)
          t_min  = (idx == start_idx) ? start_t : 0.0
          t_candidates = [(-b_co - sd) / (2.0 * a_co), (-b_co + sd) / (2.0 * a_co)]
          ts = t_candidates.select { |t| t > t_min + 1.0e-9 && t <= 1.0 + 1.0e-9 }.sort
          if ts.empty?
            idx += 1
            next
          end
          t = [ts.first, 1.0].min
          p = Geom::Point3d.linear_combination(1.0 - t, a, t, b)
          return [p, idx, t]
        end
        nil
      end

    end
  end
end