# ----------------------------------------------------------------
#  CA-Wall Panel — Draw Tool (Kalem)
#  ----------------------------------------------------------------
#  Tıklayarak nokta nokta polyline çiz; Enter / sağ tık bitirir,
#  Esc iptal eder. Bitirince edge'ler modele eklenir ve
#  ApplyTool.run_from_edges çalışır.
#
#  • Eksen-snap: ikinci ve sonraki noktalarda InputPoint inferencing
#    referansıyla pick — kırmızı / yeşil / mavi eksenlere kilitlenir.
#  • Renkli eksen kılavuzu: hover ile son nokta arasındaki çizgi
#    eksen yönündeyse o eksenin rengiyle (kırmızı / yeşil / mavi)
#    çizilir. Aksi halde gri.
#  • Soft panel ön-izleme: çizilen polyline boyunca her panel için
#    yarı-saydam wireframe kutusu görünür → kullanıcı yerleşimi
#    çizmeden görür.
#  • VCB: yükseklik input'u ile değiştirilebilir.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    class DrawTool

      VK_RETURN_KEYS = [13, 0x0D, 10].freeze
      VK_ESC_KEYS    = [27, 0x1B].freeze

      AXIS_TOL_DEG = 2.0
      RED_AXIS     = Geom::Vector3d.new(1, 0, 0)
      GREEN_AXIS   = Geom::Vector3d.new(0, 1, 0)
      BLUE_AXIS    = Geom::Vector3d.new(0, 0, 1)

      def initialize(height_mm:, flip:, profile_code: nil)
        @height_mm     = height_mm.to_f
        @flip          = !!flip
        @profile_code  = profile_code
        if profile_code
          p = Profiles.find(profile_code)
          if p
            @profile_w_mm = p[:width_mm].to_f
            @profile_d_mm = p[:depth_mm].to_f
          end
        end
        @profile_w_mm ||= 126.0
        @profile_d_mm ||= 18.0

        @points    = []
        @hover_pt  = nil
        @input_pt  = Sketchup::InputPoint.new
        @last_ip   = Sketchup::InputPoint.new
        @has_last  = false
      end

      def activate
        update_status_and_vcb
        @points    = []
        @has_last  = false
        view = Sketchup.active_model.active_view
        view.invalidate if view
      end

      def deactivate(view); view.invalidate; end
      def resume(view);     view.invalidate; end
      def suspend(view);    view.invalidate; end

      # ---- INPUT --------------------------------------------------
      def enableVCB?; true; end

      def onUserText(text, view)
        s = text.to_s.strip.gsub(',', '.')
        m = s.match(/^([0-9]+(?:\.[0-9]+)?)\s*(mm)?$/i)
        if m
          h = m[1].to_f
          if h > 0
            @height_mm = h
            update_status_and_vcb
            view.invalidate
          else
            UI.beep
          end
        else
          UI.beep
        end
      rescue StandardError
        UI.beep
      end

      def onMouseMove(_flags, x, y, view)
        if @has_last
          @input_pt.pick(view, x, y, @last_ip)
        else
          @input_pt.pick(view, x, y)
        end
        @hover_pt = @input_pt.position
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        if @has_last
          @input_pt.pick(view, x, y, @last_ip)
        else
          @input_pt.pick(view, x, y)
        end
        pt = @input_pt.position
        @points << pt
        @last_ip.copy!(@input_pt) if @last_ip.respond_to?(:copy!)
        @has_last = true
        view.invalidate
      end

      def onRButtonDown(_flags, _x, _y, _view); finish_path; end
      def onLButtonDoubleClick(_flags, _x, _y, _view); finish_path; end

      def onKeyDown(key, _repeat, _flags, _view)
        if VK_RETURN_KEYS.include?(key)
          finish_path
        elsif VK_ESC_KEYS.include?(key)
          cancel
        end
      end

      def onCancel(_reason, _view); cancel; end

      # ---- ACTIONS ------------------------------------------------
      def cancel
        @points    = []
        @has_last  = false
        Sketchup.active_model.active_view.invalidate
        Sketchup.active_model.select_tool(nil)
      end

      def finish_path
        if @points.size < 2
          UI.messagebox("En az 2 nokta gerekli.")
          @points = []
          @has_last = false
          Sketchup.active_model.active_view.invalidate
          return
        end

        model = Sketchup.active_model
        model.start_operation('CA-Wall Panel · Kalem ile Çiz', true)

        edges = []
        begin
          (0...(@points.size - 1)).each do |i|
            e = model.entities.add_line(@points[i], @points[i + 1])
            edges << e if e
          end
          if edges.empty?
            model.abort_operation
            cancel
            return
          end

          model.commit_operation
        rescue StandardError => err
          model.abort_operation
          UI.messagebox("Çizim hatası: #{err.message}")
          cancel
          return
        end

        ApplyTool.last_height_mm  = @height_mm
        ApplyTool.flip_orientation = @flip
        ApplyTool.run_from_edges(edges, @height_mm, @flip)
        @points = []
        @has_last = false
        Sketchup.active_model.select_tool(nil)
      end

      # ---- DRAW ---------------------------------------------------
      def draw(view)
        # InputPoint inferencing rehberlerini çizdirmeyi her zaman dene
        # (display? false döndürse bile axis snap işaretleri görünür)
        @input_pt.draw(view) rescue nil

        # Mevcut polyline turuncu
        if @points.size >= 2
          view.line_width = 2
          view.drawing_color = Sketchup::Color.new(245, 166, 35)
          view.draw(GL_LINE_STRIP, @points)
        end

        # Hover'a giden çizgi — eksen yönünde ise o renk
        if @hover_pt && !@points.empty?
          view.line_width = 2
          color = axis_color(@points.last, @hover_pt)
          if color
            view.line_stipple  = ''
            view.drawing_color = color
          else
            view.line_stipple  = '-'
            view.drawing_color = Sketchup::Color.new(160, 160, 160)
          end
          view.draw(GL_LINES, [@points.last, @hover_pt])
          view.line_stipple = ''
        end

        # Soft 3D panel ön-izleme (wireframe kutular)
        draw_panel_preview(view)

        # Tıklanan nokta noktalar
        view.draw_points(@points, 8, 2, Sketchup::Color.new(245, 166, 35)) unless @points.empty?
      end

      def axis_color(from, to)
        v = to - from
        return nil if v.length < 1.0e-6
        v = v.clone
        v.normalize!
        cos_tol = Math.cos(AXIS_TOL_DEG * Math::PI / 180.0)

        if v.dot(RED_AXIS).abs > cos_tol
          Sketchup::Color.new(220, 30, 30)
        elsif v.dot(GREEN_AXIS).abs > cos_tol
          Sketchup::Color.new(30, 170, 30)
        elsif v.dot(BLUE_AXIS).abs > cos_tol
          Sketchup::Color.new(40, 60, 220)
        else
          nil
        end
      end

      def draw_panel_preview(view)
        return unless @profile_w_mm && @profile_d_mm

        all_pts = @points.dup
        all_pts << @hover_pt if @hover_pt
        return if all_pts.size < 2

        panel_w_inch = @profile_w_mm.mm
        panel_d_inch = @profile_d_mm.mm
        height_inch  = @height_mm.mm
        return if panel_w_inch <= 0 || panel_d_inch <= 0 || height_inch <= 0

        # Polyline'dan segmentler ve toplam uzunluk
        segs = []
        cumulative = 0.0
        (0...(all_pts.size - 1)).each do |i|
          a = all_pts[i]; b = all_pts[i + 1]
          len = (b - a).length
          next if len < 1.0e-9
          segs << { a: a, b: b, length: len, cum_start: cumulative }
          cumulative += len
        end
        return if segs.empty?

        # ApplyTool.walk_chord_points'i kullan (aynı algoritma → tutarlı)
        chord_pts = ApplyTool.walk_chord_points(segs, panel_w_inch)
        return if chord_pts.size < 2

        z_up = Geom::Vector3d.new(0, 0, 1)
        soft_color = Sketchup::Color.new(245, 166, 35, 90)
        view.line_width = 1
        view.drawing_color = soft_color
        view.line_stipple = ''

        (0...(chord_pts.size - 1)).each do |i|
          p_a = chord_pts[i]
          p_b = chord_pts[i + 1]
          x_axis = p_b - p_a
          next if x_axis.length < 1.0e-9
          x_axis.normalize!
          y_axis = z_up * x_axis
          next if y_axis.length < 1.0e-9
          y_axis.normalize!
          y_axis.reverse! if @flip

          dy = y_axis.clone; dy.length = panel_d_inch
          dz = z_up.clone;   dz.length = height_inch

          bl = p_a
          br = p_b
          fl = bl.offset(dy)
          fr = br.offset(dy)
          bl_t = bl.offset(dz)
          br_t = br.offset(dz)
          fl_t = fl.offset(dz)
          fr_t = fr.offset(dz)

          # 12 kenarlı kutu
          view.draw(GL_LINE_LOOP, [bl, br, fr, fl])
          view.draw(GL_LINE_LOOP, [bl_t, br_t, fr_t, fl_t])
          view.draw(GL_LINES, [bl, bl_t, br, br_t, fr, fr_t, fl, fl_t])
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(Sketchup.active_model.bounds.min) if Sketchup.active_model.bounds
        @points.each { |p| bb.add(p) }
        bb.add(@hover_pt) if @hover_pt
        # Preview kutular için ekstra yükseklik dahil et
        if @hover_pt && @height_mm
          top = @hover_pt.offset(Geom::Vector3d.new(0, 0, @height_mm.mm))
          bb.add(top)
        end
        bb
      end

      # ---- STATUS / VCB -------------------------------------------
      def update_status_and_vcb
        Sketchup.set_status_text(
          "CA Kalem · Sol tık: nokta · Enter/Sağ tık: bitir · Esc: iptal · " \
          "VCB: yükseklik (mm)",
          SB_PROMPT
        )
        Sketchup.set_status_text("Yükseklik:", SB_VCB_LABEL)
        Sketchup.set_status_text("#{@height_mm.round} mm",  SB_VCB_VALUE)
      end

    end
  end
end