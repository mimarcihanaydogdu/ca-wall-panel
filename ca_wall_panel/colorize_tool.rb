# ----------------------------------------------------------------
#  CA-Wall Panel — Colorize / Texture Tool
#  Renk veya PNG texture'unu seçili Lambri Hattı + içindeki tüm
#  ComponentInstance'lara uygular. Render-ready: V-Ray/Enscape SU
#  materyalini doğrudan okur, texture'lı materyal ile çıktı renklenir.
# ----------------------------------------------------------------

require 'json'

module CAWorks
  module CAWallPanel
    module Colorize

      ATTR_DICT = 'caworks_ca_wall_panel'.freeze
      RECENT_TEXTURE_KEY = 'recent_textures_v1'.freeze

      PALETTE = [
        ['Beyaz HG',          [250, 250, 248]],
        ['Krem',              [235, 220, 195]],
        ['Bej',               [210, 190, 160]],
        ['Açık Gri',          [200, 200, 200]],
        ['Antrasit',          [55,  60,  65 ]],
        ['Siyah HG',          [25,  25,  25 ]],
        ['Doğal Meşe',        [180, 145, 100]],
        ['Koyu Ceviz',        [95,  60,  40 ]],
        ['Ahşap Açık',        [205, 175, 130]],
        ['Beton Gri',         [135, 135, 130]],
        ['Pastel Mavi',       [175, 195, 215]],
        ['Pastel Yeşil',      [180, 200, 175]],
        ['Bordo',             [110, 35,  45 ]],
        ['Hardal',            [195, 165, 55 ]]
      ].freeze

      DEFAULT_TILE_MM = [600, 600].freeze

      # ------------------------------------------------------------
      #  RENK
      # ------------------------------------------------------------
      def self.apply_to_selection(color_name, rgb)
        targets = collect_targets
        if targets.empty?
          UI.messagebox("Önce bir Lambri Hattı (veya panel) seçin.")
          return
        end

        model = Sketchup.active_model
        mat   = ensure_color_material(model, color_name, rgb)

        model.start_operation('CA-Wall Panel · Renk Uygula', true)
        affected = paint_targets(targets, mat, color_name, rgb, nil)
        model.commit_operation

        Sketchup.set_status_text("CA-Wall Panel: #{affected} öğe boyandı (#{color_name})")
      end

      def self.apply_custom
        targets = collect_targets
        if targets.empty?
          UI.messagebox("Önce bir Lambri Hattı seçin.")
          return
        end

        prompts  = ['R (0-255):', 'G (0-255):', 'B (0-255):', 'Renk Adı:']
        defaults = ['200', '200', '200', 'Custom']
        result   = UI.inputbox(prompts, defaults, 'CA-Wall Panel — Custom Renk')
        return unless result

        r, g, b = result[0].to_i, result[1].to_i, result[2].to_i
        name    = result[3].to_s.strip
        name    = 'Custom' if name.empty?
        apply_to_selection(name, [r, g, b])
      end

      # ------------------------------------------------------------
      #  TEXTURE
      # ------------------------------------------------------------
      def self.apply_texture_from_file
        targets = collect_targets
        if targets.empty?
          UI.messagebox("Önce bir Lambri Hattı seçin.")
          return
        end

        path = UI.openpanel('Texture PNG/JPG Seç', '', 'Image|*.png;*.jpg;*.jpeg;||')
        return unless path && File.exist?(path)

        size_input = UI.inputbox(
          ['Tile Genişliği (mm):', 'Tile Yüksekliği (mm):', 'Materyal Adı:'],
          [DEFAULT_TILE_MM[0].to_s, DEFAULT_TILE_MM[1].to_s, suggest_mat_name(path)],
          'CA-Wall Panel — Doku Boyutu'
        )
        return unless size_input

        tile_w = size_input[0].to_f
        tile_h = size_input[1].to_f
        name   = size_input[2].to_s.strip
        name   = suggest_mat_name(path) if name.empty?
        tile_w = DEFAULT_TILE_MM[0] if tile_w <= 0
        tile_h = DEFAULT_TILE_MM[1] if tile_h <= 0

        model = Sketchup.active_model
        mat   = ensure_texture_material(model, name, path, tile_w, tile_h)
        return unless mat

        model.start_operation('CA-Wall Panel · Doku Uygula', true)
        affected = paint_targets(targets, mat, name, nil, path)
        model.commit_operation

        remember_texture(path, name, tile_w, tile_h)
        Sketchup.set_status_text("CA-Wall Panel: #{affected} öğe '#{name}' dokusuyla boyandı")
      end

      def self.apply_recent_texture(path, name, tile_w, tile_h)
        targets = collect_targets
        if targets.empty?
          UI.messagebox("Önce bir Lambri Hattı seçin.")
          return
        end
        unless File.exist?(path)
          UI.messagebox("Doku dosyası bulunamadı:\n#{path}\n\nTekrar yükleyin.")
          remove_recent_texture(path)
          return
        end

        model = Sketchup.active_model
        mat   = ensure_texture_material(model, name, path, tile_w, tile_h)
        return unless mat

        model.start_operation('CA-Wall Panel · Doku Uygula', true)
        affected = paint_targets(targets, mat, name, nil, path)
        model.commit_operation

        Sketchup.set_status_text("CA-Wall Panel: #{affected} öğe '#{name}' dokusuyla boyandı")
      end

      # ------------------------------------------------------------
      #  HEDEF SEÇİMİ — Lambri Hattı'nı, içindeki tüm instance'ları kapsa
      # ------------------------------------------------------------
      def self.collect_targets
        sel = Sketchup.active_model.selection.to_a
        targets = []

        sel.each do |e|
          if panel_run?(e)
            targets << e
            e.entities.grep(Sketchup::ComponentInstance).each { |i| targets << i }
          elsif e.is_a?(Sketchup::ComponentInstance)
            targets << e
          elsif e.is_a?(Sketchup::Group) &&
                e.get_attribute(ATTR_DICT, 'profile_code')
            # legacy v0.2 grupları
            targets << e
          end
        end

        targets.uniq
      end

      def self.panel_run?(e)
        e.is_a?(Sketchup::Group) &&
          e.get_attribute(ATTR_DICT, 'is_panel_run') == true
      end

      def self.paint_targets(targets, mat, name, rgb, texture_path)
        affected = 0
        targets.each do |t|
          t.material = mat
          affected += 1
          if panel_run?(t)
            t.set_attribute(ATTR_DICT, 'material_name', name.to_s)
            t.set_attribute(ATTR_DICT, 'material_rgb',  rgb || mat_rgb(mat))
            t.set_attribute(ATTR_DICT, 'texture_path',  texture_path.to_s)
          end
        end
        affected
      end

      def self.mat_rgb(mat)
        c = mat&.color
        c ? [c.red, c.green, c.blue] : [200, 200, 200]
      end

      # ------------------------------------------------------------
      #  MATERYAL OLUŞTURMA
      # ------------------------------------------------------------
      def self.ensure_color_material(model, color_name, rgb)
        mat_name = "CAWallPanel_#{color_name.gsub(/[^\w]+/, '_')}"
        mat = model.materials[mat_name] || model.materials.add(mat_name)
        mat.color = Sketchup::Color.new(*rgb)
        mat.texture = nil if mat.texture
        mat
      end

      def self.ensure_texture_material(model, name, path, tile_w_mm, tile_h_mm)
        mat_name = "CAWallPanel_T_#{name.gsub(/[^\w]+/, '_')}"
        mat = model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture = path
        if mat.texture
          mat.texture.size = [tile_w_mm.mm, tile_h_mm.mm]
        end
        mat
      rescue StandardError => e
        UI.messagebox("Doku yüklenemedi: #{e.message}")
        nil
      end

      def self.suggest_mat_name(path)
        File.basename(path, File.extname(path)).gsub(/[^\w]+/, '_')[0, 40]
      end

      # ------------------------------------------------------------
      #  RECENT TEXTURES (Sketchup defaults)
      # ------------------------------------------------------------
      def self.recent_textures
        json = Sketchup.read_default(ATTR_DICT, RECENT_TEXTURE_KEY, '[]')
        arr = JSON.parse(json) rescue []
        arr.is_a?(Array) ? arr : []
      end

      def self.remember_texture(path, name, tile_w_mm, tile_h_mm)
        list = recent_textures.reject { |h| h['path'] == path }
        list.unshift({
          'path' => path, 'name' => name,
          'tile_w_mm' => tile_w_mm, 'tile_h_mm' => tile_h_mm
        })
        list = list.first(8)
        Sketchup.write_default(ATTR_DICT, RECENT_TEXTURE_KEY, JSON.generate(list))
      end

      def self.remove_recent_texture(path)
        list = recent_textures.reject { |h| h['path'] == path }
        Sketchup.write_default(ATTR_DICT, RECENT_TEXTURE_KEY, JSON.generate(list))
      end

    end
  end
end