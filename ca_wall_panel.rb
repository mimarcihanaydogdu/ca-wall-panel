# ----------------------------------------------------------------
#  CA-Wall Panel — Loader
#  ca//works · Cihan Aydoğdu Mimarlık
# ----------------------------------------------------------------
#  Bu dosyayı SketchUp Plugins klasörüne, "ca_wall_panel" klasörü
#  ile birlikte kopyalayın:
#
#    Windows: C:/Users/<USER>/AppData/Roaming/SketchUp/SketchUp 20XX/SketchUp/Plugins/
#    macOS:   ~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins/
#
#  Kopyalandıktan sonra SketchUp'ı yeniden başlatın.
#  Eklentiler menüsünde "CA-Wall Panel" göreceksiniz.
# ----------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

module CAWorks
  module CAWallPanel

    PLUGIN_ID      = 'caworks_ca_wall_panel'.freeze
    PLUGIN_NAME    = 'CA-Wall Panel'.freeze
    PLUGIN_VERSION = '0.5.0'.freeze
    PLUGIN_AUTHOR  = 'ca//works (Cihan Aydoğdu)'.freeze

    PLUGIN_ROOT = File.dirname(__FILE__)
    PLUGIN_DIR  = File.join(PLUGIN_ROOT, 'ca_wall_panel')

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_DIR, 'main'))
      ext.description = 'Lambri/duvar paneli profillerini çizgi/yay/daire/curve '\
                        'boyunca, component instance olarak yan yana dik dizer; '\
                        'metraj ve özel profil özellikleri içerir.'
      ext.version     = PLUGIN_VERSION
      ext.creator     = PLUGIN_AUTHOR
      ext.copyright   = "© 2026 #{PLUGIN_AUTHOR}"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end

  end
end