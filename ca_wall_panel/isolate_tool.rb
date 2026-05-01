require 'set'

# ----------------------------------------------------------------
#  CA-Wall Panel — Isolate Tool ("Yalnız Lambri Modu")
#  Tek tuş toggle:
#   AÇIK : caworks_ca_wall_panel/is_panel_run attribute'una sahip
#          OLMAYAN tüm üst-seviye entity'ler gizlenir.
#   KAPALI: bu mod tarafından gizlenenler geri açılır
#          (kullanıcının manuel gizlediklerine dokunulmaz).
#  Durum + gizlenenlerin persistent_id listesi modelin attribute
#  dictionary'sinde tutulur → SketchUp dosyasını kapatıp açtığınızda
#  bile mod hatırlanır.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module IsolateTool

      ATTR_DICT      = 'caworks_ca_wall_panel'.freeze
      STATE_KEY      = 'isolate_active'.freeze
      HIDDEN_IDS_KEY = 'isolate_hidden_ids'.freeze

      def self.active?
        Sketchup.active_model.get_attribute(ATTR_DICT, STATE_KEY) == true
      end

      def self.toggle
        active? ? restore : isolate
      end

      def self.isolate
        model = Sketchup.active_model
        hidden_ids = []

        model.start_operation('CA-Wall Panel · Yalnız Lambri Modu (AÇ)', true)
        begin
          model.entities.each do |e|
            next unless e.respond_to?(:hidden?)
            next if e.hidden?
            next if panel_run?(e)

            e.hidden = true
            hidden_ids << e.persistent_id
          end

          model.set_attribute(ATTR_DICT, STATE_KEY, true)
          model.set_attribute(ATTR_DICT, HIDDEN_IDS_KEY, hidden_ids)
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Yalnız Lambri Modu açılamadı: #{e.message}")
          return
        end

        Sketchup.set_status_text(
          "Yalnız Lambri Modu: AÇIK · #{hidden_ids.size} öğe gizlendi"
        )
      end

      def self.restore
        model = Sketchup.active_model
        ids   = model.get_attribute(ATTR_DICT, HIDDEN_IDS_KEY) || []
        id_set = ids.to_set

        model.start_operation('CA-Wall Panel · Yalnız Lambri Modu (KAPAT)', true)
        begin
          if id_set.empty?
            # Fallback: bilinmeyen durum, tüm üst-seviye gizlilikleri açma
            UI.messagebox("Önceki gizleme listesi bulunamadı; gizlemelere dokunulmadı.")
          else
            model.entities.each do |e|
              next unless e.respond_to?(:hidden?)
              if id_set.include?(e.persistent_id) && e.hidden?
                e.hidden = false
              end
            end
          end

          model.set_attribute(ATTR_DICT, STATE_KEY, false)
          model.set_attribute(ATTR_DICT, HIDDEN_IDS_KEY, [])
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Mod kapatılamadı: #{e.message}")
          return
        end

        Sketchup.set_status_text("Yalnız Lambri Modu: KAPALI")
      end

      def self.panel_run?(e)
        e.is_a?(Sketchup::Group) &&
          e.get_attribute(ATTR_DICT, 'is_panel_run') == true
      end

    end
  end
end