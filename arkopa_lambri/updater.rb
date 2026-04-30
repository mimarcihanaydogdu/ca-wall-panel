# ----------------------------------------------------------------
#  Arkopa Lambri — GitHub Auto-Updater
#  ----------------------------------------------------------------
#  Mantık:
#  1) SketchUp açılışında: Plugins/.arkopa_pending/ klasörü varsa
#     onu aç, dosyaları yerine taşı, klasörü sil, changelog'u göster.
#  2) Sonra arka planda GitHub'ın Releases API'sine sor:
#     yeni bir tag varsa → .rbz asset'ini indir → .arkopa_pending/'e
#     açılmış halde yaz. (Aktif kod değişmez; bu sefer hiçbir şey görünmez.)
#  3) Bir sonraki SketchUp açılışında 1. adım çalışır → güncelleme aktif.
#
#  Plugins/ klasörü SketchUp çalışırken dosyaları kilitler; o yüzden
#  "indirme şimdi, aktivasyon sonraki açılışta" pratikte tek güvenli yol.
# ----------------------------------------------------------------

require 'sketchup.rb'
require 'json'
require 'fileutils'

module CAWorks
  module ArkopaLambri
    module Updater

      # ---- KONFİGÜRASYON ----------------------------------------
      # GitHub repo: cihanaydogdu/arkopa-lambri (örnek — değiştir)
      GITHUB_OWNER = 'mimarcihanaydogdu'.freeze
      GITHUB_REPO  = 'arkopa-lambri'.freeze

      API_URL = "https://api.github.com/repos/#{GITHUB_OWNER}/#{GITHUB_REPO}/releases/latest".freeze

      # Plugins klasörü yolu (extension yüklendiği yer)
      PLUGINS_DIR = File.dirname(File.dirname(__FILE__)).freeze
      # Bekleyen güncelleme klasörü — bir sonraki açılışta uygulanacak
      PENDING_DIR  = File.join(PLUGINS_DIR, '.arkopa_pending').freeze
      # Son kontrol zamanı / son sürüm bilgisi (tekrarlı kontrolleri önle)
      STATE_FILE   = File.join(PLUGINS_DIR, '.arkopa_updater_state').freeze
      # En az kaç saatte bir kontrol edilsin (kullanıcının ağını yormamak için)
      CHECK_INTERVAL_HOURS = 6

      # ---- GİRİŞ NOKTASI ----------------------------------------
      # main.rb yüklendiğinde çağrılır.
      def self.boot
        # 1) Bekleyen güncelleme varsa önce onu uygula
        apply_pending_if_any

        # 2) Sonra arka planda yeni sürüm kontrolü
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

        # __* meta dosyalarını taşımayacağız
        meta_files = [version_file, notes_file]

        # Pending klasöründeki her şeyi Plugins/ köküne kopyala
        # (arkopa_lambri.rb + arkopa_lambri/ klasörü)
        Dir.glob(File.join(PENDING_DIR, '**', '*')).each do |src|
          next if meta_files.include?(src)
          next if File.directory?(src)

          rel = src.sub(PENDING_DIR + File::SEPARATOR, '')
          dst = File.join(PLUGINS_DIR, rel)
          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(src, dst)
        end

        # Pending klasörünü sil
        FileUtils.rm_rf(PENDING_DIR)

        # State dosyasını güncelle
        save_state('installed_version' => new_version,
                   'last_check'        => Time.now.to_i)

        # Kullanıcıya değişiklik notunu göster (engaging değil; sadece bilgilendirme)
        UI.messagebox(
          "✓ Arkopa Lambri güncellendi → v#{new_version}\n\n" \
          "#{notes.empty? ? '(değişiklik notu yok)' : notes}\n\n" \
          "Yeni sürüm bu oturumdan itibaren aktiftir."
        )
      rescue StandardError => e
        # Sessiz hata: kullanıcıyı rahatsız etme, sadece logla
        warn "[Arkopa Updater] apply_pending hatası: #{e.message}"
        # Bozuk pending klasörünü temizle ki sonraki açılışta tekrar denemesin
        FileUtils.rm_rf(PENDING_DIR) rescue nil
      end

      # ---- ZAMANI GELDİ Mİ? -------------------------------------
      def self.should_check_now?
        state = load_state
        last  = state['last_check'].to_i
        return true if last.zero?
        (Time.now.to_i - last) >= CHECK_INTERVAL_HOURS * 3600
      end

      # ---- GitHub API'sine SOR ----------------------------------
      def self.check_for_update_silently
        # SketchUp::Http SketchUp 2017+ ile geldi. Async ve UI'yi bloklamaz.
        request = Sketchup::Http::Request.new(API_URL, Sketchup::Http::GET)
        request.headers = {
          'Accept'     => 'application/vnd.github+json',
          'User-Agent' => "ArkopaLambri/#{ArkopaLambri::PLUGIN_VERSION}"
        }

        request.start do |req, response|
          handle_release_response(response)
        end
      rescue StandardError => e
        warn "[Arkopa Updater] kontrol hatası: #{e.message}"
        save_state('last_check' => Time.now.to_i)
      end

      def self.handle_release_response(response)
        save_state('last_check' => Time.now.to_i)

        return unless response.status_code == 200

        data = JSON.parse(response.body) rescue nil
        return unless data.is_a?(Hash)

        latest_tag = data['tag_name'].to_s.sub(/^v/, '')
        return if latest_tag.empty?
        return unless newer?(latest_tag, ArkopaLambri::PLUGIN_VERSION)

        # .rbz veya .zip asset'ini bul
        asset = (data['assets'] || []).find do |a|
          name = a['name'].to_s.downcase
          name.end_with?('.rbz') || name.end_with?('.zip')
        end
        return unless asset

        notes = data['body'].to_s
        download_and_stage(asset['browser_download_url'], latest_tag, notes)
      end

      # ---- INDIR + STAGE ----------------------------------------
      def self.download_and_stage(url, version, notes)
        request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
        request.headers = {
          'User-Agent' => "ArkopaLambri/#{ArkopaLambri::PLUGIN_VERSION}"
        }

        # Indirileni temp dosyaya yaz, sonra pending klasörüne aç
        tmp_zip = File.join(PLUGINS_DIR, ".arkopa_dl_#{Time.now.to_i}.rbz")

        request.set_download_progress_callback do |current, total|
          # Sessiz indirme — istenirse buradan toolbar'a progress yazılabilir
        end

        request.start do |req, response|
          if response.status_code != 200
            warn "[Arkopa Updater] indirme başarısız: #{response.status_code}"
            next
          end

          File.open(tmp_zip, 'wb') { |f| f.write(response.body) }

          if extract_to_pending(tmp_zip, version, notes)
            File.delete(tmp_zip) rescue nil
          else
            warn "[Arkopa Updater] zip açma başarısız"
            File.delete(tmp_zip) rescue nil
          end
        end
      rescue StandardError => e
        warn "[Arkopa Updater] download_and_stage hatası: #{e.message}"
      end

      # ---- ZIP AÇMA ---------------------------------------------
      # SketchUp'ın yerleşik zip extractor'ı: Sketchup::Zip (SU 2018+).
      # Yoksa shell unzip'e düşeceğiz.
      def self.extract_to_pending(zip_path, version, notes)
        FileUtils.rm_rf(PENDING_DIR)
        FileUtils.mkdir_p(PENDING_DIR)

        success = false
        if defined?(Sketchup::Zip) && Sketchup::Zip.respond_to?(:extract)
          # SketchUp 2018+ yerleşik zip
          Sketchup::Zip.extract(zip_path, PENDING_DIR)
          success = true
        else
          # Eski sürüm fallback — Ruby standart kütüphanesinden mini-unzip
          success = extract_zip_pure_ruby(zip_path, PENDING_DIR)
        end

        return false unless success

        File.write(File.join(PENDING_DIR, '__version__'), version)
        File.write(File.join(PENDING_DIR, '__notes__'),   notes.to_s)
        true
      rescue StandardError => e
        warn "[Arkopa Updater] extract hatası: #{e.message}"
        false
      end

      # Saf-Ruby zip extractor (bağımlılık olmadan, sadece store + deflate)
      def self.extract_zip_pure_ruby(zip_path, dest_dir)
        require 'zlib'
        File.open(zip_path, 'rb') do |f|
          loop do
            sig = f.read(4)
            break if sig.nil? || sig != "PK\x03\x04".b

            f.read(2) # version
            gp_flag = f.read(2).unpack1('v')
            method  = f.read(2).unpack1('v')
            f.read(4) # mod time/date
            f.read(4) # crc
            comp_size = f.read(4).unpack1('V')
            uncomp_size = f.read(4).unpack1('V')
            name_len  = f.read(2).unpack1('v')
            extra_len = f.read(2).unpack1('v')
            name      = f.read(name_len)
            f.read(extra_len)

            data = f.read(comp_size)

            # ZIP64 / streaming entries — bu mini-extractor desteklemez
            if gp_flag.anybits?(0x08)
              warn "[Arkopa Updater] streaming zip entry desteklenmiyor: #{name}"
              return false
            end

            content =
              if method == 0      # store
                data
              elsif method == 8   # deflate
                Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data)
              else
                warn "[Arkopa Updater] bilinmeyen zip metodu #{method}: #{name}"
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
        warn "[Arkopa Updater] saf-ruby unzip hatası: #{e.message}"
        false
      end

      # ---- SÜRÜM KARŞILAŞTIRMA ----------------------------------
      # Semantic versioning: "1.2.3" > "1.2.0"
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
        warn "[Arkopa Updater] state kaydı: #{e.message}"
      end

      # ---- ELLE TETİKLEME (debug menü için) ---------------------
      def self.check_now!
        UI.messagebox("Güncelleme kontrolü başlatıldı (sessiz). " \
                      "Yeni sürüm varsa indirilip bir sonraki açılışta uygulanacak.")
        Thread.new { check_for_update_silently }
      end

    end
  end
end
