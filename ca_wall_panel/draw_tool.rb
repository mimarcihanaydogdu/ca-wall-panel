# ----------------------------------------------------------------
#  CA-Wall Panel — Draw Tool (Kalem)
#  ----------------------------------------------------------------
#  Kullanıcı tıklayarak nokta nokta polyline çizer; Enter veya sağ
#  tık ile bitirir, Esc ile iptal eder. Bitirince çizilen edge'ler
#  modele eklenir ve ApplyTool.run_from_edges ile lambri uygulanır.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    class DrawTool

      VK_RETURN_KEYS = [13, 0x0D, 10].freeze
      VK_ESC_KEYS    = [27, 0x1B].freeze

      def initialize(height_mm:, flip:)
        @height_mm  = height_mm.to_f
        @flip       = !!flip
        @points     = []
        @hover_pt   = nil
        @input_pt   = Sketchup::InputPoint.new
        @cursor_id  = nil
      end

      def activate
        Sketchup.set_status_text(
          'CA Kalem · Sol tık: nokta ekle  |  Enter / Sağ tık: bitir  |  Esc: iptal',
          SB_PROMPT
        )
        @points = []
        view = Sketchup.active_model.active_view
        view.invalidate if view
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @input_pt.pick(view, x, y)
        @hover_pt = @input_pt.position
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @input_pt.pick(view, x, y)
        pt = @input_pt.position
        @points << pt
        view.invalidate
      end

      def onRButtonDown(_flags, _x, _y, _view)
        finish_path
      end

      def onLButtonDoubleClick(_flags, _x, _y, _view)
        finish_path
      end

      def onKeyDown(key, _repeat, _flags, _view)
        if VK_RETURN_KEYS.include?(key)
          finish_path
        elsif VK_ESC_KEYS.include?(key)
          cancel
        end
      end

      def onCancel(_reason, _view)
        cancel
      end

      def cancel
        @points = []
        Sketchup.active_model.active_view.invalidate
        Sketchup.active_model.select_tool(nil)
      end

      def finish_path
        if @points.size < 2
          UI.messagebox("En az 2 nokta gerekli.")
          @points = []
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
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Çizim hatası: #{e.message}")
          cancel
          return
        end

        ApplyTool.run_from_edges(edges, @height_mm, @flip)
        @points = []
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
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

    end
  end
end