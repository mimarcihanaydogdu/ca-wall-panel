# ----------------------------------------------------------------
#  CA-Wall Panel — Main Entry
# ----------------------------------------------------------------

require 'json'
require 'sketchup.rb'

require File.join(File.dirname(__FILE__), 'profiles')
require File.join(File.dirname(__FILE__), 'components')
require File.join(File.dirname(__FILE__), 'apply_tool')
require File.join(File.dirname(__FILE__), 'draw_tool')
require File.join(File.dirname(__FILE__), 'metraj')
require File.join(File.dirname(__FILE__), 'isolate_tool')
require File.join(File.dirname(__FILE__), 'colorize_tool')
require File.join(File.dirname(__FILE__), 'updater')

module CAWorks
  module CAWallPanel

    @profile_dialog = nil
    @color_dialog   = nil

    def self.close_dialogs
      @profile_dialog&.close rescue nil
      @color_dialog&.close   rescue nil
      @profile_dialog = nil
      @color_dialog   = nil
    end

    # ------------------------------------------------------------
    #  PROFİL SEÇİM DİYALOĞU
    # ------------------------------------------------------------
    def self.show_profile_dialog(edit_run: nil)
      build_profile_dialog if @profile_dialog.nil?

      # Hatalı bir önceki edit referansını taşıma
      ApplyTool.editing_run = nil unless edit_run

      if @profile_dialog.visible?
        @profile_dialog.bring_to_front
      else
        @profile_dialog.show
      end

      send_profiles_to_dialog
      @profile_dialog.execute_script(
        "setDefaultHeight(#{ApplyTool.last_height_mm.to_f});"
      )
      @profile_dialog.execute_script("cancelEdit();") unless edit_run

      if edit_run
        ApplyTool.editing_run = edit_run
        edit_state = {
          run_name:     edit_run.name.to_s,
          profile_code: edit_run.get_attribute(ApplyTool::ATTR_DICT, 'profile_code').to_s,
          height_mm:    edit_run.get_attribute(ApplyTool::ATTR_DICT, 'height_mm').to_f,
          flip:         edit_run.get_attribute(ApplyTool::ATTR_DICT, 'flip') == true
        }
        @profile_dialog.execute_script(
          "setEditMode(#{edit_state.to_json.inspect});"
        )
      end
    end

    def self.send_profiles_to_dialog
      return unless @profile_dialog
      json = profiles_for_js.to_json
      @profile_dialog.execute_script("loadProfiles(#{json.inspect});")
      path = Profiles.custom_file rescue ''
      @profile_dialog.execute_script("setStoragePath(#{path.to_s.inspect});")
      send_recents_to_dialog
    end

    def self.send_recents_to_dialog
      return unless @profile_dialog
      json = Profiles.recent_codes.to_json
      @profile_dialog.execute_script("loadRecents(#{json.inspect});")
    end

    def self.profiles_for_js
      Profiles.all.map do |p|
        params_h = (p[:params] || {}).each_with_object({}) { |(k, v), o| o[k.to_s] = v }
        {
          code:      p[:code],
          name:      p[:name],
          width_mm:  p[:width_mm].to_f,
          depth_mm:  p[:depth_mm].to_f,
          length_mm: p[:length_mm].to_f,
          pattern:   p[:pattern].to_s,
          params:    params_h,
          custom:    p[:custom] == true
        }
      end
    end

    def self.build_profile_dialog
      html_path = File.join(File.dirname(__FILE__), 'dialog.html')

      @profile_dialog = UI::HtmlDialog.new(
        dialog_title:    'CA-Wall Panel',
        preferences_key: 'caworks_ca_wall_panel',
        scrollable:      true,
        resizable:       true,
        width:           480,
        height:          760,
        min_width:       360,
        min_height:      500,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @profile_dialog.set_file(html_path)

      @profile_dialog.add_action_callback('dialog_ready') do |_ctx|
        send_profiles_to_dialog
        @profile_dialog.execute_script(
          "setDefaultHeight(#{ApplyTool.last_height_mm.to_f});"
        )
        if (run = ApplyTool.editing_run)
          if run.respond_to?(:valid?) && run.valid?
            edit_state = {
              run_name:     run.name.to_s,
              profile_code: run.get_attribute(ApplyTool::ATTR_DICT, 'profile_code').to_s,
              height_mm:    run.get_attribute(ApplyTool::ATTR_DICT, 'height_mm').to_f,
              flip:         run.get_attribute(ApplyTool::ATTR_DICT, 'flip') == true
            }
            @profile_dialog.execute_script(
              "setEditMode(#{edit_state.to_json.inspect});"
            )
          else
            ApplyTool.editing_run = nil
          end
        end
      end

      @profile_dialog.add_action_callback('set_active_profile') do |_ctx, code|
        ApplyTool.active_profile_code = code
        Profiles.add_recent(code)
      end

      @profile_dialog.add_action_callback('apply_profile') do |_ctx, code, flip, height_mm|
        ApplyTool.active_profile_code = code
        ApplyTool.flip_orientation    = flip
        Profiles.add_recent(code)
        ApplyTool.run(height_mm.to_f)
      end

      @profile_dialog.add_action_callback('update_run') do |_ctx, code, flip, height_mm|
        run = ApplyTool.editing_run
        if run.nil? || !run.respond_to?(:valid?) || !run.valid?
          UI.messagebox("Düzenlenecek hat seçili değil.")
        else
          profile = Profiles.find(code) || Profiles.all.first
          ApplyTool.regenerate_run(run, profile, height_mm.to_f, flip)
        end
        ApplyTool.editing_run = nil
        @profile_dialog.execute_script("cancelEdit();") if @profile_dialog
      end

      @profile_dialog.add_action_callback('cancel_edit') do |_ctx|
        ApplyTool.editing_run = nil
      end

      @profile_dialog.add_action_callback('draw_with_profile') do |_ctx, code, flip, height_mm|
        ApplyTool.active_profile_code = code
        ApplyTool.flip_orientation    = flip
        ApplyTool.last_height_mm      = height_mm.to_f
        Sketchup.active_model.select_tool(
          DrawTool.new(height_mm: height_mm.to_f, flip: flip, profile_code: code)
        )
      end

      @profile_dialog.add_action_callback('edit_selected') do |_ctx|
        run = ApplyTool.find_selected_run
        if run.nil?
          UI.messagebox(
            "Düzenlemek için modelden bir Lambri Hattı seçin.\n" \
            "(Sağ-tık → Edit ile içine değil; bir kez tıklayarak grup olarak seçin.)"
          )
        else
          show_profile_dialog(edit_run: run)
        end
      end

      @profile_dialog.add_action_callback('open_metraj') do |_ctx|
        Metraj.show
      end

      @profile_dialog.add_action_callback('open_colors') do |_ctx|
        show_color_dialog
      end

      @profile_dialog.add_action_callback('save_custom_profile') do |_ctx, json_str|
        result = save_custom_profile_safely(json_str)
        @profile_dialog.execute_script("customSaveResult(#{result.to_json.inspect});")
      end

      @profile_dialog.add_action_callback('delete_custom_profile') do |_ctx, code|
        begin
          Profiles.delete_custom(code)
          send_profiles_to_dialog
        rescue StandardError => e
          UI.messagebox("Özel profil silinemedi: #{e.message}")
        end
      end
    end

    # save_custom_profile callback'inin tamamı bu fonksiyona alınmıştır →
    # her hata JSON sonucu olarak JS'e döner; dialog kilitlenmez.
    def self.save_custom_profile_safely(json_str)
      warn "[CA-Wall Panel] save_custom raw input: #{json_str.to_s[0, 400]}"
      data = JSON.parse(json_str.to_s)
      sym  = {
        code:      data['code'],
        name:      data['name'],
        width_mm:  data['width_mm'],
        depth_mm:  data['depth_mm'],
        length_mm: data['length_mm'],
        pattern:   (data['pattern'] || 'flat').to_sym,
        params:    (data['params']  || {})
      }
      ok, payload = Profiles.save_custom(sym)
      warn "[CA-Wall Panel] save_custom result: ok=#{ok} payload=#{payload.inspect}"
      if ok
        all_codes = Profiles.all.map { |p| p[:code] }
        warn "[CA-Wall Panel] all profile codes after save: #{all_codes.inspect}"
        send_profiles_to_dialog
        { ok: true,
          message:      "Özel profil kaydedildi: #{payload[:code]} " \
                        "(toplam özel: #{Profiles.custom_profiles.size})",
          profile_code: payload[:code] }
      else
        { ok: false, message: payload.to_s }
      end
    rescue JSON::ParserError => e
      warn "[CA-Wall Panel] JSON parse error: #{e.message}"
      { ok: false, message: "Form verisi okunamadı: #{e.message}" }
    rescue StandardError => e
      warn "[CA-Wall Panel] save error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { ok: false, message: "Kayıt hatası: #{e.message}" }
    end

    # ------------------------------------------------------------
    #  RENK SEÇİM DİYALOĞU
    # ------------------------------------------------------------
    def self.show_color_dialog
      if @color_dialog && @color_dialog.visible?
        @color_dialog.bring_to_front
        return
      end

      html_path = File.join(File.dirname(__FILE__), 'colors.html')

      @color_dialog = UI::HtmlDialog.new(
        dialog_title:    'CA-Wall Panel Renkler',
        preferences_key: 'caworks_ca_wall_panel_colors',
        scrollable:      true,
        resizable:       true,
        width:           380,
        height:          600,
        min_width:       300,
        min_height:      380,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @color_dialog.set_file(html_path)

      @color_dialog.add_action_callback('palette_ready') do |_ctx|
        @color_dialog.execute_script(
          "loadPalette(#{Colorize::PALETTE.to_json.inspect});"
        )
        send_recent_textures
      end

      @color_dialog.add_action_callback('apply_color') do |_ctx, name, r, g, b|
        Colorize.apply_to_selection(name, [r, g, b])
      end

      @color_dialog.add_action_callback('custom_color') do |_ctx|
        Colorize.apply_custom
      end

      @color_dialog.add_action_callback('load_texture') do |_ctx|
        Colorize.apply_texture_from_file
        send_recent_textures
      end

      @color_dialog.add_action_callback('apply_recent_texture') do |_ctx, path, name, tw, th|
        Colorize.apply_recent_texture(path, name, tw.to_f, th.to_f)
        send_recent_textures
      end

      @color_dialog.show
    end

    def self.send_recent_textures
      return unless @color_dialog
      json = Colorize.recent_textures.to_json
      @color_dialog.execute_script("loadRecents(#{json.inspect});")
    end

    # ------------------------------------------------------------
    #  KISAYOLLAR
    # ------------------------------------------------------------
    def self.start_draw_tool
      Sketchup.active_model.select_tool(
        DrawTool.new(
          height_mm:    ApplyTool.last_height_mm,
          flip:         ApplyTool.flip_orientation,
          profile_code: ApplyTool.active_profile_code
        )
      )
    end

    def self.edit_selected_run
      run = ApplyTool.find_selected_run
      if run.nil?
        UI.messagebox("Düzenlemek için modelden bir Lambri Hattı seçin.")
        return
      end
      show_profile_dialog(edit_run: run)
    end

    # Hızlı Uygula: diyalog açmadan, son kullanılan profil + yükseklik
    # ile seçili çizgiye lambri uygular.
    def self.quick_apply
      sel = Sketchup.active_model.selection.to_a.select { |e| e.is_a?(Sketchup::Edge) }
      if sel.empty?
        UI.messagebox("Hızlı Uygula: önce çizgi/yay seçin.\n\n" \
                      "Profil: #{ApplyTool.active_profile_code}\n" \
                      "Yükseklik: #{ApplyTool.last_height_mm.round} mm")
        return
      end
      Profiles.add_recent(ApplyTool.active_profile_code) if ApplyTool.active_profile_code
      ApplyTool.run(ApplyTool.last_height_mm)
    end

    # ------------------------------------------------------------
    #  MENÜ + TOOLBAR
    # ------------------------------------------------------------
    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins').add_submenu('CA-Wall Panel')
      menu.add_item('Profil Seç ve Uygula')  { show_profile_dialog }
      menu.add_item('Hızlı Uygula (Son Ayarlar)') { quick_apply }
      menu.add_item('Kalem ile Çiz')         { start_draw_tool }
      menu.add_item("Lambri'yi Düzenle")     { edit_selected_run }
      menu.add_separator
      menu.add_item('Metraj')                { Metraj.show }
      menu.add_item('Renklendir / Doku')     { show_color_dialog }
      menu.add_item('Yalnız Lambri Modu')    { IsolateTool.toggle }
      menu.add_separator
      menu.add_item('Güncellemeleri Kontrol Et') { Updater.check_now_with_prompt }
      menu.add_item('Şimdi Güncelle (Bekleyen)') { Updater.update_now! }
      menu.add_item('Hakkında') do
        UI.messagebox(
          "CA-Wall Panel v#{PLUGIN_VERSION}\n\n" \
          "ca//works · Cihan Aydoğdu Mimarlık\n\n" \
          "Yenilikler (0.5.0):\n" \
          " · Toolbar: yalnızca 2 ikon (CA-Wall Panel + Yalnız Lambri Modu).\n" \
          " · Tüm diğer komutlar ve güncelleme menü altına alındı.\n" \
          " · Yeni sürüm bulunduğunda otomatik bildirim (modal Y/N).\n" \
          " · Kesit havuzu genişletildi: 18 farklı profil; yeni 'Pahlı Düz',\n" \
          "   'Pahlı V-Kanal', 'Üçlü V', 'Geçmeli (T&G)' kesitleri eklendi.\n" \
          " · Diyalogda 'Son Kullanılanlar' şeridi (kalıcı).\n" \
          " · Hızlı Uygula: diyalog açmadan son ayarla seçili çizgiye uygular."
        )
      end

      tb = UI::Toolbar.new('CA-Wall Panel')

      icon_dir = File.join(File.dirname(__FILE__), 'icons')

      cmd_main = UI::Command.new('CA-Wall Panel') { show_profile_dialog }
      cmd_main.tooltip          = 'CA-Wall Panel — Profil/yükseklik diyaloğu'
      cmd_main.status_bar_text  = 'Profil seç, yükseklik gir; çizgi/yay'\
                                  ' veya Çiz aracıyla uygula'
      icon_main = File.join(icon_dir, 'panel.svg')
      if File.exist?(icon_main)
        cmd_main.large_icon = icon_main
        cmd_main.small_icon = icon_main
      end
      tb.add_item(cmd_main)

      cmd_iso = UI::Command.new('Yalnız Lambri Modu') { IsolateTool.toggle }
      cmd_iso.tooltip         = 'Lambri dışındaki üst-seviye nesneleri'\
                                ' geçici olarak gizle / geri aç'
      cmd_iso.status_bar_text = 'Plan/kesit incelemesi için izolasyon (toggle)'
      cmd_iso.set_validation_proc { IsolateTool.active? ? MF_CHECKED : MF_UNCHECKED }
      icon_iso = File.join(icon_dir, 'isolate.svg')
      if File.exist?(icon_iso)
        cmd_iso.large_icon = icon_iso
        cmd_iso.small_icon = icon_iso
      else
        # Fallback: color iconu kullan, en azından buton görünür
        icon_color = File.join(icon_dir, 'color.svg')
        if File.exist?(icon_color)
          cmd_iso.large_icon = icon_color
          cmd_iso.small_icon = icon_color
        end
      end
      tb.add_item(cmd_iso)

      tb.show

      Updater.boot

      file_loaded(__FILE__)
    end

  end
end