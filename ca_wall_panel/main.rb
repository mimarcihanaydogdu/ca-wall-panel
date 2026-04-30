# ----------------------------------------------------------------
#  CA-Wall Panel — Main Entry
# ----------------------------------------------------------------

require 'json'
require 'sketchup.rb'

require File.join(File.dirname(__FILE__), 'profiles')
require File.join(File.dirname(__FILE__), 'apply_tool')
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
    def self.show_profile_dialog
      if @profile_dialog && @profile_dialog.visible?
        @profile_dialog.bring_to_front
        return
      end

      html_path = File.join(File.dirname(__FILE__), 'dialog.html')

      @profile_dialog = UI::HtmlDialog.new(
        dialog_title:   'CA-Wall Panel',
        preferences_key: 'caworks_ca_wall_panel',
        scrollable:     true,
        resizable:      true,
        width:          440,
        height:         620,
        min_width:      320,
        min_height:     400,
        style:          UI::HtmlDialog::STYLE_DIALOG
      )
      @profile_dialog.set_file(html_path)

      @profile_dialog.add_action_callback('dialog_ready') do |_ctx|
        json = Profiles.all.to_json
        @profile_dialog.execute_script("loadProfiles(#{json.inspect});")
      end

      @profile_dialog.add_action_callback('set_active_profile') do |_ctx, code|
        ApplyTool.active_profile_code = code
      end

      @profile_dialog.add_action_callback('apply_profile') do |_ctx, code, flip|
        ApplyTool.active_profile_code = code
        ApplyTool.flip_orientation    = flip
        ApplyTool.run
      end

      @profile_dialog.add_action_callback('open_colors') do |_ctx|
        show_color_dialog
      end

      @profile_dialog.show
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
        dialog_title:   'CA-Wall Panel Renkler',
        preferences_key: 'caworks_ca_wall_panel_colors',
        scrollable:     true,
        resizable:      true,
        width:          340,
        height:         520,
        min_width:      260,
        min_height:     320,
        style:          UI::HtmlDialog::STYLE_DIALOG
      )
      @color_dialog.set_file(html_path)

      @color_dialog.add_action_callback('palette_ready') do |_ctx|
        json = Colorize::PALETTE.to_json
        @color_dialog.execute_script("loadPalette(#{json.inspect});")
      end

      @color_dialog.add_action_callback('apply_color') do |_ctx, name, r, g, b|
        Colorize.apply_to_selection(name, [r, g, b])
      end

      @color_dialog.add_action_callback('custom_color') do |_ctx|
        Colorize.apply_custom
      end

      @color_dialog.show
    end

    # ------------------------------------------------------------
    #  MENÜ + TOOLBAR
    # ------------------------------------------------------------
    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins').add_submenu('CA-Wall Panel')
      menu.add_item('Profil Seç ve Uygula') { show_profile_dialog }
      menu.add_item('Renklendir')           { show_color_dialog   }
      menu.add_separator
      menu.add_item('Güncelle Plugini')     { Updater.update_now! }
      menu.add_item('Hakkında') do
        UI.messagebox(
          "CA-Wall Panel v#{PLUGIN_VERSION}\n\n" \
          "ca//works · Cihan Aydoğdu Mimarlık\n\n" \
          "Kullanım:\n" \
          "1) 'Profil Seç ve Uygula' menüsünden bir profil seçin.\n" \
          "2) SketchUp'ta uygulamak istediğiniz çizgi/yay/daire/curve'ü seçin.\n" \
          "3) Diyalogdan 'Uygula' butonuna basın.\n" \
          "4) Renklendirmek için panel grubunu seçip 'Renklendir' menüsünü açın."
        )
      end

      tb = UI::Toolbar.new('CA-Wall Panel')

      icon_dir = File.join(File.dirname(__FILE__), 'icons')

      cmd1 = UI::Command.new('CA-Wall Panel') { show_profile_dialog }
      cmd1.tooltip          = 'CA-Wall Panel — Profil seç ve uygula'
      cmd1.status_bar_text  = 'Bir çizgi/yay/daire seçip duvar paneli profilini uygulayın'
      icon1 = File.join(icon_dir, 'panel.svg')
      if File.exist?(icon1)
        cmd1.large_icon = icon1
        cmd1.small_icon = icon1
      end
      tb.add_item(cmd1)

      cmd2 = UI::Command.new('Renklendir') { show_color_dialog }
      cmd2.tooltip         = 'Yerleştirilmiş CA-Wall Panel grubunu renklendir'
      cmd2.status_bar_text = 'Panel grubunu seçip rengini değiştirin'
      icon2 = File.join(icon_dir, 'color.svg')
      if File.exist?(icon2)
        cmd2.large_icon = icon2
        cmd2.small_icon = icon2
      end
      tb.add_item(cmd2)

      cmd3 = UI::Command.new('Güncelle Plugini') { Updater.update_now! }
      cmd3.tooltip          = 'CA-Wall Panel — Güncelle (yeniden başlatmadan)'
      cmd3.status_bar_text  = 'Yeni sürüm varsa anında indirir ve yükler'
      icon3 = File.join(icon_dir, 'update.svg')
      if File.exist?(icon3)
        cmd3.large_icon = icon3
        cmd3.small_icon = icon3
      end
      tb.add_item(cmd3)

      tb.show

      Updater.boot

      file_loaded(__FILE__)
    end

  end
end
