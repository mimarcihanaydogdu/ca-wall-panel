# ----------------------------------------------------------------
#  CA-Wall Panel — Colorize Tool
#  Yerleştirilmiş panel gruplarının materyalini değiştirir.
#  Hazır renk paleti veya custom RGB.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module Colorize

      ATTR_DICT = 'caworks_ca_wall_panel'.freeze

      # Genel-amaçlı renk paleti — High Gloss & Mat tonlarından temsili örnek.
      # Pratik kullanım için yaklaşıktır. Kullanıcı kendi RGB'sini de girebilir.
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

      def self.apply_to_selection(color_name, rgb)
        model = Sketchup.active_model
        sel   = model.selection.to_a

        groups = sel.select do |e|
          e.is_a?(Sketchup::Group) &&
            e.get_attribute(ATTR_DICT, 'profile_code')
        end

        if groups.empty?
          UI.messagebox("Önce bir CA-Wall Panel grubu seçin.")
          return
        end

        mat_name = "CAWallPanel_#{color_name.gsub(/\s+/, '_')}"
        mat = model.materials[mat_name] || model.materials.add(mat_name)
        mat.color = Sketchup::Color.new(*rgb)

        model.start_operation('CA-Wall Panel Renk', true)
        groups.each { |g| g.material = mat }
        model.commit_operation
      end

      def self.apply_custom
        model = Sketchup.active_model
        sel   = model.selection.to_a.select do |e|
          e.is_a?(Sketchup::Group) &&
            e.get_attribute(ATTR_DICT, 'profile_code')
        end

        if sel.empty?
          UI.messagebox("Önce bir CA-Wall Panel grubu seçin.")
          return
        end

        prompts  = ['R (0-255):', 'G (0-255):', 'B (0-255):', 'Renk Adı:']
        defaults = ['200', '200', '200', 'Custom']
        result   = UI.inputbox(prompts, defaults, 'CA-Wall Panel — Custom Renk')
        return unless result

        r, g, b = result[0].to_i, result[1].to_i, result[2].to_i
        name = result[3].to_s.strip
        name = 'Custom' if name.empty?

        apply_to_selection(name, [r, g, b])
      end

    end
  end
end
