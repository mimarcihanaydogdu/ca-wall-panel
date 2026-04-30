# ----------------------------------------------------------------
#  CA-Wall Panel — GitHub Auto-Updater
#  ----------------------------------------------------------------
#  Mantık:
#  1) SketchUp açılışında: Plugins/.cawp_pending/ klasörü varsa
#     onu aç, dosyaları yerine taşı, klasörü sil, changelog'u göster.
#  2) Sonra arka planda GitHub'ın Releases API'sine sor:
#     yeni bir tag varsa → .rbz asset'ini indir → .cawp_pending/'e
#     açılmış halde yaz.
#  3) Bir sonraki SketchUp açılışında 1. adım çalışır → güncelleme aktif.
#
#  "Güncelle Plugini" butonu ile canlı güncelleme:
#  - .rbz indirilir, doğrudan Plugins/ klasörüne açılır,
#  - tüm .rb dosyaları load() ile yeniden yüklenir.
#  - SketchUp'ı kapatmaya gerek yoktur.
# ----------------------------------------------------------------

require 'sketchup.rb'
require 'json'
require 'fileutils'

module CAWorks
  module CAWallPanel
    module Updater

      # ---- KONFİGÜRASYON ----------------------------------------
      GITHUB_OWNER = 'mimarcihanaydogdu'.freeze
      GITHUB_REPO  = 'ca-wall-panel'.freeze

      API_URL = "https://api.github.com/repos/#{GITHUB_OWNER}/#{GITHUB_REPO}/releases/latest".freeze

      PLUGINS_DIR = File.dirname(File.dirname(__FILE__)).freeze
      PENDING_DIR  = File.join(PLUGINS_DIR, '.cawp_pending').freeze
      STATE_FILE   = File.join(PLUGINS_DIR, '.cawp_updater_state').freeze
      CHECK_INTERVAL_HOURS = 6

      # ---- GİRİŞ NOKTASI ----------------------------------------
      def self.boot
        apply_pending_if_any

        return unless should_check_now?
        Thread.new { check_for_update_silently }
      end

      # ---- BEKLEYEN GÜNCELLEMEYİ UYGULA -------------------------
      def self.apply_pending_if_any
        return unless File.directory?(PENDING_DIR)

        version_file = File.join(PENDING_DIR, '__version__')
        notes_file   = File.join(PENDING_DIR, '__notes__')
        new_version  = File.exist?(version_file) ? File.read(version_file).strip : 'yeni'
        notes        = File.exist?(notes_file)   ? File.read(notes_file).strip   : ''

        meta_files = [version_file, notes_file]

        Dir.glob(File.join(PENDING_DIR, '**', '*')).each do |src|
          next if meta_files.include?(src)
          next if File.directory?(src)

          rel = src.sub(PENDING_DIR + File::SEPARATOR, '')
          dst = File.join(PLUGINS_DIR, rel)
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(src, dst)
        end

        FileUtils.rm_rf(PENDING_DIR)

        save_state('installed_version' => new_version,
                   'last_check'        => Time.now.to_i)

        UI.messagebox(
          "✓ CA-Wall Panel güncellendi → v#{new_version}\n\n" \
          "#{notes.empty? ? '(değişiklik notu yok)' : notes}\n\n" \
          "Yeni sürüm bu oturumdan itibaren aktiftir."
        )
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] apply_pending hatası: #{e.message}"
        FileUtils.rm_rf(PENDING_DIR) rescue nil
      end

      def self.should_check_now?
        state = load_state
        last  = state['last_check'].to_i
        return true if last.zero?
        (Time.now.to_i - last) >= CHECK_INTERVAL_HOURS * 3600
      end

      # ---- GitHub API'sine SOR ----------------------------------
      def self.check_for_update_silently
        request = Sketchup::Http::Request.new(API_URL, Sketchup::Http::GET)
        request.headers = {
          'Accept'     => 'application/vnd.github+json',
          'User-Agent' => "CAWallPanel/#{CAWallPanel::PLUGIN_VERSION}"
        }

        request.start do |req, response|
          handle_release_response(response)
        end
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] kontrol hatası: #{e.message}"
        save_state('last_check' => Time.now.to_i)
      end

      def self.handle_release_response(response)
        save_state('last_check' => Time.now.to_i)

        return unless response.status_code == 200

        data = JSON.parse(response.body) rescue nil
        return unless data.is_a?(Hash)

        latest_tag = data['tag_name'].to_s.sub(/^v/, '')
        return if latest_tag.empty?
        return unless newer?(latest_tag, CAWallPanel::PLUGIN_VERSION)

        asset = (data['assets'] || []).find do |a|
          name = a['name'].to_s.downcase
          name.end_with?('.rbz') || name.end_with?('.zip')
        end
        return unless asset

        notes = data['body'].to_s
        download_and_stage(asset['browser_download_url'], latest_tag, notes)
      end

      # ---- INDIR + STAGE (arka plan) ----------------------------
      def self.download_and_stage(url, version, notes)
        request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
        request.headers = {
          'User-Agent' => "CAWallPanel/#{CAWallPanel::PLUGIN_VERSION}"
        }

        tmp_zip = File.join(PLUGINS_DIR, ".cawp_dl_#{Time.now.to_i}.rbz")

        request.set_download_progress_callback do |current, total|
        end

        request.start do |req, response|
          if response.status_code != 200
            warn "[CA-Wall Panel Updater] indirme başarısız: #{response.status_code}"
            next
          end

          File.open(tmp_zip, 'wb') { |f| f.write(response.body) }

          if extract_to_pending(tmp_zip, version, notes)
            File.delete(tmp_zip) rescue nil
          else
            warn "[CA-Wall Panel Updater] zip açma başarısız"
            File.delete(tmp_zip) rescue nil
          end
        end
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] download_and_stage hatası: #{e.message}"
      end

      # ---- ZIP AÇMA ---------------------------------------------
      def self.extract_zip_to(zip_path, dest_dir)
        if defined?(Sketchup::Zip) && Sketchup::Zip.respond_to?(:extract)
          Sketchup::Zip.extract(zip_path, dest_dir)
        else
          return extract_zip_pure_ruby(zip_path, dest_dir)
        end
        true
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] extract_zip_to hatası: #{e.message}"
        false
      end

      def self.extract_to_pending(zip_path, version, notes)
        FileUtils.rm_rf(PENDING_DIR)
        FileUtils.mkdir_p(PENDING_DIR)

        return false unless extract_zip_to(zip_path, PENDING_DIR)

        File.write(File.join(PENDING_DIR, '__version__'), version)
        File.write(File.join(PENDING_DIR, '__notes__'),   notes.to_s)
        true
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] extract hatası: #{e.message}"
        false
      end

      def self.extract_zip_pure_ruby(zip_path, dest_dir)
        require 'zlib'
        File.open(zip_path, 'rb') do |f|
          loop do
            sig = f.read(4)
            break if sig.nil? || sig != "PK\x03\x04".b

            f.read(2)
            gp_flag = f.read(2).unpack1('v')
            method  = f.read(2).unpack1('v')
            f.read(4)
            f.read(4)
            comp_size = f.read(4).unpack1('V')
            uncomp_size = f.read(4).unpack1('V')
            name_len  = f.read(2).unpack1('v')
            extra_len = f.read(2).unpack1('v')
            name      = f.read(name_len)
            f.read(extra_len)

            data = f.read(comp_size)

            if gp_flag.anybits?(0x08)
              warn "[CA-Wall Panel Updater] streaming zip entry desteklenmiyor: #{name}"
              return false
            end

            content =
              if method == 0
                data
              elsif method == 8
                Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data)
              else
                warn "[CA-Wall Panel Updater] bilinmeyen zip metodu #{method}: #{name}"
                return false
              end

            out_path = File.join(dest_dir, name)
            if name.end_with?('/')
              FileUtils.mkdir_p(out_path)
            else
              FileUtils.mkdir_p(File.dirname(out_path))
              File.open(out_path, 'wb') { |o| o.write(content) }
            end
          end
        end
        true
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] saf-ruby unzip hatası: #{e.message}"
        false
      end

      # ---- SÜRÜM KARŞILAŞTIRMA ----------------------------------
      def self.newer?(remote, local)
        rp = remote.split('.').map { |s| s.to_i }
        lp = local .split('.').map { |s| s.to_i }
        max = [rp.size, lp.size].max
        rp.fill(0, rp.size...max)
        lp.fill(0, lp.size...max)
        (rp <=> lp) > 0
      end

      # ---- STATE I/O --------------------------------------------
      def self.load_state
        return {} unless File.exist?(STATE_FILE)
        JSON.parse(File.read(STATE_FILE))
      rescue StandardError
        {}
      end

      def self.save_state(updates)
        state = load_state.merge(updates)
        File.write(STATE_FILE, JSON.generate(state))
      rescue StandardError => e
        warn "[CA-Wall Panel Updater] state kaydı: #{e.message}"
      end

      # ---- GÜNCELLE BUTONU — CANLI GÜNCELLEME (yeniden başlatma gerekmez) ---
      def self.update_now!
        Sketchup.status_text = 'CA-Wall Panel: güncelleme kontrol ediliyor…'

        request = Sketchup::Http::Request.new(API_URL, Sketchup::Http::GET)
        request.headers = {
          'Accept'     => 'application/vnd.github+json',
          'User-Agent' => "CAWallPanel/#{CAWallPanel::PLUGIN_VERSION}"
        }

        request.start do |_req, response|
          Sketchup.status_text = ''
          save_state('last_check' => Time.now.to_i)

          unless response.status_code == 200
            UI.messagebox("Güncelleme sunucusuna ulaşılamadı (HTTP #{response.status_code}).")
            next
          end

          data = JSON.parse(response.body) rescue nil
          unless data.is_a?(Hash)
            UI.messagebox('Güncelleme yanıtı okunamadı.')
            next
          end

          latest_tag = data['tag_name'].to_s.sub(/^v/, '')
          if latest_tag.empty?
            UI.messagebox('Sürüm bilgisi alınamadı.')
            next
          end

          unless newer?(latest_tag, CAWallPanel::PLUGIN_VERSION)
            UI.messagebox("✓ Zaten güncel — v#{CAWallPanel::PLUGIN_VERSION}")
            next
          end

          asset = (data['assets'] || []).find do |a|
            name = a['name'].to_s.downcase
            name.end_with?('.rbz') || name.end_with?('.zip')
          end
          unless asset
            UI.messagebox("v#{latest_tag} bulundu fakat indirilebilir dosya yok.")
            next
          end

          notes = data['body'].to_s
          download_and_apply_live(asset['browser_download_url'], latest_tag, notes)
        end
      rescue StandardError => e
        Sketchup.status_text = ''
        UI.messagebox("Güncelleme hatası: #{e.message}")
      end

      def self.download_and_apply_live(url, version, notes)
        Sketchup.status_text = "CA-Wall Panel: v#{version} indiriliyor…"
        tmp_zip = File.join(PLUGINS_DIR, ".cawp_dl_#{Time.now.to_i}.rbz")

        request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
        request.headers = { 'User-Agent' => "CAWallPanel/#{CAWallPanel::PLUGIN_VERSION}" }

        request.start do |_req, response|
          Sketchup.status_text = ''

          unless response.status_code == 200
            UI.messagebox("İndirme başarısız (HTTP #{response.status_code}).")
            next
          end

          File.open(tmp_zip, 'wb') { |f| f.write(response.body) }

          if extract_zip_to(tmp_zip, PLUGINS_DIR)
            File.delete(tmp_zip) rescue nil
            save_state('installed_version' => version, 'last_check' => Time.now.to_i)
            hot_reload!(version, notes)
          else
            File.delete(tmp_zip) rescue nil
            UI.messagebox('Dosyalar açılamadı. Manuel kurulum gerekebilir.')
          end
        end
      rescue StandardError => e
        Sketchup.status_text = ''
        File.delete(tmp_zip) rescue nil if defined?(tmp_zip)
        UI.messagebox("İndirme hatası: #{e.message}")
      end

      # Dosyaları yerinde yükler — SketchUp'ı kapatmaya gerek yok.
      def self.hot_reload!(version, notes)
        plugin_dir = File.join(PLUGINS_DIR, 'ca_wall_panel')

        CAWorks::CAWallPanel.close_dialogs rescue nil

        verbose = $VERBOSE
        $VERBOSE = nil
        load(File.join(PLUGINS_DIR, 'ca_wall_panel.rb'))
        $VERBOSE = verbose

        %w[profiles.rb apply_tool.rb colorize_tool.rb updater.rb main.rb].each do |f|
          load(File.join(plugin_dir, f)) rescue warn "[CA-Wall Panel] reload: #{f}"
        end

        msg  = "✓ CA-Wall Panel güncellendi → v#{version}\n\n"
        msg += notes.empty? ? '(değişiklik notu yok)' : notes
        UI.messagebox(msg)
      rescue StandardError => e
        UI.messagebox("Reload hatası: #{e.message}\nDeğişiklikler bir sonraki açılışta aktif olur.")
      end

    end
  end
end
