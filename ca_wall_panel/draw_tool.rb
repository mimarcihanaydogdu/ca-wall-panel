# ----------------------------------------------------------------
#  CA-Wall Panel — Draw Tool (Kalem)
#  ----------------------------------------------------------------
#  Tıklayarak nokta nokta polyline çiz; Enter / sağ tık bitirir,
#  Esc iptal eder. Bitirince edge'ler modele eklenir ve
#  ApplyTool.run_from_edges çalışır.
#
#  • Eksen-snap: ikinci ve sonraki noktalarda InputPoint inferencing
#    referansıyla pick — kırmızı / yeşil / mavi eksenlere kilitlenir
#    (SU'nun standart line tool davranışı).
#  • VCB: yükseklik input'u ile değiştirilebilir (örn. "3000" yazıp
#    Enter → yükseklik 3000 mm). Mevcut yükseklik status bar'da görünür.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    class DrawTool

      VK_RETURN_KEYS = [13, 0x0D, 10].freeze
      VK_ESC_KEYS    = [27, 0x1B].freeze

      def initialize(height_mm:, flip:)
        @height_mm = height_mm.to_f
        @flip      = !!flip
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

      # ---- INPUT ---------------------------------------------------
      def enableVCB?; true; end

      def onUserText(text, view)
        s = text.to_s.strip.gsub(',', '.')
        # Yükseklikte mm bekleniyor; "2800mm" / "2800" ikisi de OK.
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

      # ---- ACTIONS -------------------------------------------------
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
        # InputPoint kendi inferencing renklerini çiziyor (eksen rehberleri vb.)
        @input_pt.draw(view) if @input_pt.display?

        return if @points.empty?

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(245, 166, 35)
        if @points.size >= 2
          view.draw(GL_LINE_STRIP, @points)
        end

        if @hover_pt
          view.line_width    = 1
          view.line_stipple  = '-'
          view.drawing_color = Sketchup::Color.new(160, 160, 160)
          view.draw(GL_LINES, [@points.last, @hover_pt])
          view.line_stipple  = ''
        end

        view.draw_points(@points, 8, 2, Sketchup::Color.new(245, 166, 35))
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(Sketchup.active_model.bounds.min) if Sketchup.active_model.bounds
        @points.each { |p| bb.add(p) }
        bb.add(@hover_pt) if @hover_pt
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