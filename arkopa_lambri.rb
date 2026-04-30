# ----------------------------------------------------------------
#  Arkopa Lambri Plugin — Loader
#  ca//works / Cihan Aydoğdu Mimarlık
# ----------------------------------------------------------------
#  Bu dosyayı SketchUp Plugins klasörüne, "arkopa_lambri" klasörü
#  ile birlikte kopyalayın:
#
#    Windows: C:/Users/<USER>/AppData/Roaming/SketchUp/SketchUp 20XX/SketchUp/Plugins/
#    macOS:   ~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins/
#
#  Kopyalandıktan sonra SketchUp'ı yeniden başlatın.
#  Eklentiler menüsünde "Arkopa Lambri" göreceksiniz.
# ----------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

module CAWorks
  module ArkopaLambri

    PLUGIN_ID      = 'caworks_arkopa_lambri'.freeze
    PLUGIN_NAME    = 'Arkopa Lambri'.freeze
    PLUGIN_VERSION = '0.1.0'.freeze
    PLUGIN_AUTHOR  = 'ca//works (Cihan Aydoğdu)'.freeze

    PLUGIN_ROOT = File.dirname(__FILE__)
    PLUGIN_DIR  = File.join(PLUGIN_ROOT, 'arkopa_lambri')

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_DIR, 'main'))
      ext.description = 'Arkopa lambri profillerini çizgi/yay/daire boyunca '\
                        'follow-me ile yerleştirir, renklendirir.'
      ext.version     = PLUGIN_VERSION
      ext.creator     = PLUGIN_AUTHOR
      ext.copyright   = "© 2026 #{PLUGIN_AUTHOR}"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end

  end
end
