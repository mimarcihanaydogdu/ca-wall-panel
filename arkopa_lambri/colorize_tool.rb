# ----------------------------------------------------------------
#  Arkopa Lambri — Colorize Tool
#  Yerleştirilmiş lambri gruplarının materyalini değiştirir.
#  Arkopa renk kütüphanesinden hazır renkler veya custom renk.
# ----------------------------------------------------------------

module CAWorks
  module ArkopaLambri
    module Colorize

      # Arkopa renk paleti — High Gloss & Mat tonlarından temsili örnek.
      # Bu renkler katalogla bire bir aynı olmayabilir; pratik kullanım
      # için yaklaşıktır. Kullanıcı kendi RGB'sini de girebilir.
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

      # Bir grup ve renk al, materyal uygula
      def self.apply_to_selection(color_name, rgb)
        model = Sketchup.active_model
        sel   = model.selection.to_a

        groups = sel.select do |e|
          e.is_a?(Sketchup::Group) &&
            e.get_attribute('caworks_arkopa', 'profile_code')
        end

        if groups.empty?
          UI.messagebox("Önce bir Arkopa lambri grubu seçin.")
          return
        end

        mat_name = "Arkopa_#{color_name.gsub(/\s+/, '_')}"
        mat = model.materials[mat_name] || model.materials.add(mat_name)
        mat.color = Sketchup::Color.new(*rgb)

        model.start_operation('Arkopa Lambri Renk', true)
        groups.each { |g| g.material = mat }
        model.commit_operation
      end

      # Custom renk seçici (SketchUp'un built-in color picker'ı)
      def self.apply_custom
        model = Sketchup.active_model
        sel   = model.selection.to_a.select do |e|
          e.is_a?(Sketchup::Group) &&
            e.get_attribute('caworks_arkopa', 'profile_code')
        end

        if sel.empty?
          UI.messagebox("Önce bir Arkopa lambri grubu seçin.")
          return
        end

        prompts  = ['R (0-255):', 'G (0-255):', 'B (0-255):', 'Renk Adı:']
        defaults = ['200', '200', '200', 'Custom']
        result   = UI.inputbox(prompts, defaults, 'Arkopa Lambri — Custom Renk')
        return unless result

        r, g, b = result[0].to_i, result[1].to_i, result[2].to_i
        name = result[3].to_s.strip
        name = 'Custom' if name.empty?

        apply_to_selection(name, [r, g, b])
      end

    end
  end
end
