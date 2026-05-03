# ----------------------------------------------------------------
#  CA-Wall Panel — Metraj (Quantity Take-Off)
# ----------------------------------------------------------------
#  Modeldeki tüm Lambri Hatlarını gezer, profil + yükseklik + renk
#  bazında toplam panel sayısı, ön yüz uzunluğu (m), alan (m²),
#  gerekli standart parça sayısı ve fire (m) hesaplar.
#
#  Çıktı: HtmlDialog raporu (Yazdır → PDF) + CSV/Excel export.
# ----------------------------------------------------------------

require 'json'

module CAWorks
  module CAWallPanel
    module Metraj

      ATTR_DICT = 'caworks_ca_wall_panel'.freeze

      @dialog = nil

      # ------------------------------------------------------------
      def self.collect_runs(model = Sketchup.active_model)
        runs = []
        walk_entities(model.entities) do |e|
          next unless e.is_a?(Sketchup::Group) &&
                      e.get_attribute(ATTR_DICT, 'is_panel_run') == true

          mat       = e.material
          mat_name  = e.get_attribute(ATTR_DICT, 'material_name')
          mat_name  = mat.name if mat_name.to_s.empty? && mat
          mat_rgb   = e.get_attribute(ATTR_DICT, 'material_rgb')
          if (!mat_rgb.is_a?(Array) || mat_rgb.empty?) && mat && mat.color
            mat_rgb = [mat.color.red, mat.color.green, mat.color.blue]
          end
          mat_name  = '— Varsayılan —' if mat_name.to_s.empty?
          mat_rgb ||= [245, 245, 240]

          runs << {
            group:        e,
            name:         e.name,
            profile_code: e.get_attribute(ATTR_DICT, 'profile_code').to_s,
            profile_name: e.get_attribute(ATTR_DICT, 'profile_name').to_s,
            height_mm:    e.get_attribute(ATTR_DICT, 'height_mm').to_f,
            flip:         e.get_attribute(ATTR_DICT, 'flip') == true,
            panel_count:  e.get_attribute(ATTR_DICT, 'panel_count').to_i,
            panel_full:   e.get_attribute(ATTR_DICT, 'panel_full').to_i,
            panel_partial:e.get_attribute(ATTR_DICT, 'panel_partial').to_i,
            partial_mm:   e.get_attribute(ATTR_DICT, 'partial_mm').to_f,
            width_mm:     e.get_attribute(ATTR_DICT, 'width_mm').to_f,
            depth_mm:     e.get_attribute(ATTR_DICT, 'depth_mm').to_f,
            length_mm:    e.get_attribute(ATTR_DICT, 'length_mm').to_f,
            room_name:    e.get_attribute(ATTR_DICT, 'room_name').to_s,
            material_name: mat_name.to_s,
            material_rgb:  mat_rgb,
            texture_path:  e.get_attribute(ATTR_DICT, 'texture_path').to_s
          }
        end
        runs
      end

      def self.walk_entities(entities, &block)
        entities.each do |e|
          yield e
          if e.is_a?(Sketchup::Group)
            next if e.get_attribute(ATTR_DICT, 'is_panel_run') == true
            walk_entities(e.entities, &block)
          end
        end
      end

      # ------------------------------------------------------------
      def self.summary
        runs   = collect_runs
        groups = {}

        runs.each do |r|
          color_key = r[:material_rgb].is_a?(Array) ? r[:material_rgb].join(',') : 'default'
          room      = r[:room_name].to_s
          key = [r[:profile_code], r[:height_mm].round(3), color_key, room]
          g = (groups[key] ||= {
            profile_code:   r[:profile_code],
            profile_name:   r[:profile_name],
            height_mm:      r[:height_mm],
            width_mm:       r[:width_mm],
            depth_mm:       r[:depth_mm],
            length_mm:      r[:length_mm],
            room_name:      room,
            material_name:  r[:material_name],
            material_rgb:   r[:material_rgb],
            texture_path:   r[:texture_path],
            panel_count:    0,
            panel_full:     0,
            panel_partial:  0,
            run_count:      0,
            run_names:      []
          })
          g[:panel_count]   += r[:panel_count]
          g[:panel_full]    += r[:panel_full]
          g[:panel_partial] += r[:panel_partial]
          g[:run_count]     += 1
          g[:run_names]     << r[:name]
        end

        groups.values.map { |g| g.merge(calc_quantities(g)) }
      end

      # ------------------------------------------------------------
      #  SÜPÜRGELİK ÖZETİ (skirting summary)
      # ------------------------------------------------------------
      def self.skirting_summary
        rows = Skirting.collect_all
        groups = {}
        rows.each do |r|
          color_key = r[:material_rgb].is_a?(Array) ? r[:material_rgb].join(',') : 'default'
          room = r[:room_name].to_s
          key = [r[:skirting_code], color_key, room]
          g = (groups[key] ||= {
            skirting_code: r[:skirting_code],
            skirting_name: r[:skirting_name],
            height_mm:     r[:height_mm],
            depth_mm:      r[:depth_mm],
            length_mm:     r[:length_mm],
            room_name:     room,
            material_name: r[:material_name],
            material_rgb:  r[:material_rgb],
            total_length_mm: 0.0,
            run_count:     0
          })
          g[:total_length_mm] += r[:total_length_mm]
          g[:run_count]       += 1
        end

        groups.values.map do |g|
          total_m = g[:total_length_mm] / 1000.0
          area_m2 = total_m * (g[:height_mm] / 1000.0)
          stock_mm = g[:length_mm].to_f
          pieces = stock_mm > 0 ? (g[:total_length_mm] / stock_mm).ceil : 0
          waste_m = pieces > 0 ? ((pieces * stock_mm - g[:total_length_mm]) / 1000.0).round(3) : 0.0
          g.merge(total_m: total_m.round(3),
                  area_m2: area_m2.round(3),
                  pieces_needed: pieces,
                  waste_m: waste_m)
        end
      end

      # waste = pieces_needed * standard_length - panel_count * height
      def self.calc_quantities(g)
        panel_count = g[:panel_count].to_i
        width_mm    = g[:width_mm].to_f
        height_mm   = g[:height_mm].to_f
        stock_mm    = g[:length_mm].to_f

        total_front_m = (panel_count * width_mm) / 1000.0
        total_area_m2 = total_front_m * (height_mm / 1000.0)

        if stock_mm <= 0 || height_mm <= 0
          pieces  = panel_count
          waste_m = 0.0
          note    = 'standart boy bilinmiyor'
        elsif height_mm <= stock_mm
          pp = (stock_mm / height_mm).floor
          pp = 1 if pp < 1
          pieces  = (panel_count.to_f / pp).ceil
          stock_total = pieces * stock_mm
          used_total  = panel_count * height_mm
          waste_m = ((stock_total - used_total) / 1000.0).round(3)
          note    = "#{pp} panel/parça"
        else
          ppp = (height_mm / stock_mm).ceil
          pieces  = panel_count * ppp
          stock_total = pieces * stock_mm
          used_total  = panel_count * height_mm
          waste_m = ((stock_total - used_total) / 1000.0).round(3)
          note    = "#{ppp} parça/panel (ek gerekli)"
        end

        {
          total_front_m: total_front_m.round(3),
          total_area_m2: total_area_m2.round(3),
          pieces_needed: pieces.to_i,
          waste_m:       waste_m,
          note:          note
        }
      end

      # ------------------------------------------------------------
      #  RAPOR DİYALOĞU
      # ------------------------------------------------------------
      def self.show
        rows = summary
        html = render_html(rows)

        if @dialog && @dialog.visible?
          @dialog.set_html(html)
          @dialog.bring_to_front
          return
        end

        @dialog = UI::HtmlDialog.new(
          dialog_title:    'CA-Wall Panel — Metraj',
          preferences_key: 'caworks_ca_wall_panel_metraj',
          scrollable:      true,
          resizable:       true,
          width:           880,
          height:          660,
          min_width:       560,
          min_height:      380,
          style:           UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(html)

        @dialog.add_action_callback('refresh') do |_ctx|
          @dialog.set_html(render_html(summary))
        end

        @dialog.add_action_callback('export_csv') do |_ctx|
          export_csv(summary)
        end

        @dialog.show
      end

      # ------------------------------------------------------------
      #  CSV EXPORT (UTF-8 BOM, ';' ayraç, ',' ondalık → Excel-uyumlu)
      # ------------------------------------------------------------
      def self.export_csv(rows)
        default_name = "CA-Wall_Metraj_#{Time.now.strftime('%Y%m%d_%H%M')}.csv"
        path = UI.savepanel('Metraj CSV Kaydet', '', default_name)
        return unless path

        path = path + '.csv' unless path.downcase.end_with?('.csv')

        headers = [
          'Profil Kodu', 'Profil Adı', 'Genişlik (mm)', 'Derinlik (mm)',
          'Yükseklik (mm)', 'Renk/Materyal', 'Renk RGB',
          'Panel Sayısı', 'Ön Yüz (m)', 'Alan (m²)',
          'Standart Boy (mm)', 'Gereken Parça', 'Fire (m)', 'Not'
        ]

        sep = ';'
        bom = "\xEF\xBB\xBF".dup.force_encoding('UTF-8')

        File.open(path, 'wb') do |f|
          f.write(bom)
          f.write(headers.join(sep) + "\n")
          rows.sort_by { |r| [r[:profile_code], r[:height_mm], r[:material_name]] }.each do |r|
            rgb = r[:material_rgb].is_a?(Array) ? r[:material_rgb].join('-') : ''
            f.write([
              csv_q(r[:profile_code]),
              csv_q(r[:profile_name]),
              fmt_csv_num(r[:width_mm]),
              fmt_csv_num(r[:depth_mm]),
              fmt_csv_num(r[:height_mm]),
              csv_q(r[:material_name]),
              rgb,
              r[:panel_count],
              fmt_csv_num(r[:total_front_m], 3),
              fmt_csv_num(r[:total_area_m2], 3),
              fmt_csv_num(r[:length_mm]),
              r[:pieces_needed],
              fmt_csv_num(r[:waste_m], 3),
              csv_q(r[:note])
            ].join(sep) + "\n")
          end

          total_panels = rows.sum { |r| r[:panel_count].to_i }
          total_front  = rows.sum { |r| r[:total_front_m].to_f }
          total_area   = rows.sum { |r| r[:total_area_m2].to_f }
          total_pieces = rows.sum { |r| r[:pieces_needed].to_i }
          total_waste  = rows.sum { |r| r[:waste_m].to_f }
          f.write([
            'TOPLAM', '', '', '', '', '', '',
            total_panels,
            fmt_csv_num(total_front, 3),
            fmt_csv_num(total_area, 3),
            '', total_pieces,
            fmt_csv_num(total_waste, 3),
            ''
          ].join(sep) + "\n")
        end

        UI.messagebox("CSV kaydedildi:\n#{path}\n\n" \
                      "Excel ile aç: dosyayı çift tıklayın (UTF-8 BOM + ';' ayraç).")
      rescue StandardError => err
        UI.messagebox("CSV yazılamadı: #{err.message}")
      end

      def self.csv_q(s)
        s = s.to_s
        if s.include?(';') || s.include?('"') || s.include?("\n")
          '"' + s.gsub('"', '""') + '"'
        else
          s
        end
      end

      def self.fmt_csv_num(n, decimals = 0)
        return '' if n.nil?
        x = n.to_f
        if decimals > 0
          sprintf("%.#{decimals}f", x).sub('.', ',')
        elsif x == x.round
          x.round.to_s
        else
          sprintf('%.2f', x).sub('.', ',')
        end
      end

      # ------------------------------------------------------------
      def self.render_html(rows)
        total_panels = rows.sum { |r| r[:panel_count].to_i }
        total_front  = rows.sum { |r| r[:total_front_m].to_f }
        total_area   = rows.sum { |r| r[:total_area_m2].to_f }
        total_pieces = rows.sum { |r| r[:pieces_needed].to_i }
        total_waste  = rows.sum { |r| r[:waste_m].to_f }

        date_str   = Time.now.strftime('%d.%m.%Y %H:%M')
        model_name = (Sketchup.active_model.title.to_s.empty? ?
                      'İsimsiz Model' : Sketchup.active_model.title)

        rows_html = if rows.empty?
          '<tr><td colspan="12" class="empty">Modelde Lambri Hattı bulunamadı.</td></tr>'
        else
          rows.sort_by { |r| [r[:room_name].to_s, r[:profile_code], r[:height_mm], r[:material_name]] }.map do |r|
            rgb = r[:material_rgb].is_a?(Array) ? r[:material_rgb] : [200, 200, 200]
            tex = r[:texture_path].to_s.empty? ? '' :
                  ' <span class="tex" title="Doku: ' + e(r[:texture_path]) + '">🖼</span>'
            partial_str = (r[:panel_partial].to_i > 0) ?
                          "<span class='partial' title='Kesilmiş son lambri: #{r[:partial_mm].round}mm'>+½ (#{r[:partial_mm].round}mm)</span>" : ''
            full_str = r[:panel_full].to_i > 0 ? r[:panel_full].to_s : r[:panel_count].to_s
            <<~ROW
              <tr>
                <td>#{e(r[:room_name].to_s.empty? ? '—' : r[:room_name])}</td>
                <td>#{e(r[:profile_code])}</td>
                <td>#{e(r[:profile_name])}</td>
                <td class="num">#{fmt_dim(r[:width_mm])}×#{fmt_dim(r[:depth_mm])}</td>
                <td class="num">#{fmt_int(r[:height_mm])}</td>
                <td>
                  <span class="swatch" style="background:rgb(#{rgb[0]},#{rgb[1]},#{rgb[2]})"></span>
                  #{e(r[:material_name])}#{tex}
                </td>
                <td class="num">#{full_str} #{partial_str}</td>
                <td class="num">#{fmt_num(r[:total_front_m], 2)}</td>
                <td class="num">#{fmt_num(r[:total_area_m2], 2)}</td>
                <td class="num">#{fmt_int(r[:length_mm])} × #{r[:pieces_needed]}</td>
                <td class="num">#{fmt_num(r[:waste_m], 2)}</td>
                <td class="note">#{e(r[:note].to_s)}</td>
              </tr>
            ROW
          end.join("\n")
        end

        # ---- Süpürgelik özeti ----
        skirting_rows = (skirting_summary rescue [])
        skirt_total_m    = skirting_rows.sum { |r| r[:total_m].to_f }
        skirt_total_area = skirting_rows.sum { |r| r[:area_m2].to_f }
        skirt_total_p    = skirting_rows.sum { |r| r[:pieces_needed].to_i }
        skirt_total_w    = skirting_rows.sum { |r| r[:waste_m].to_f }
        skirting_html = if skirting_rows.empty?
          '<tr><td colspan="9" class="empty">Modelde süpürgelik bulunamadı.</td></tr>'
        else
          skirting_rows.sort_by { |r| [r[:room_name].to_s, r[:skirting_code]] }.map do |r|
            rgb = r[:material_rgb].is_a?(Array) ? r[:material_rgb] : [250, 250, 248]
            <<~SROW
              <tr>
                <td>#{e(r[:room_name].to_s.empty? ? '—' : r[:room_name])}</td>
                <td>#{e(r[:skirting_code])}</td>
                <td>#{e(r[:skirting_name])}</td>
                <td class="num">#{fmt_int(r[:height_mm])}×#{fmt_dim(r[:depth_mm])}</td>
                <td>
                  <span class="swatch" style="background:rgb(#{rgb[0]},#{rgb[1]},#{rgb[2]})"></span>
                  #{e(r[:material_name])}
                </td>
                <td class="num">#{fmt_num(r[:total_m], 2)}</td>
                <td class="num">#{fmt_num(r[:area_m2], 2)}</td>
                <td class="num">#{fmt_int(r[:length_mm])} × #{r[:pieces_needed]}</td>
                <td class="num">#{fmt_num(r[:waste_m], 2)}</td>
              </tr>
            SROW
          end.join("\n")
        end

        <<~HTML
          <!DOCTYPE html>
          <html lang="tr">
          <head>
          <meta charset="UTF-8">
          <title>CA-Wall Panel — Metraj</title>
          <style>
            * { box-sizing: border-box; }
            body {
              font-family: -apple-system, "Segoe UI", Tahoma, sans-serif;
              margin: 0; padding: 18px;
              background: #fafafa; color: #222;
              font-size: 12px;
            }
            header {
              display: flex; align-items: baseline; justify-content: space-between;
              border-bottom: 2px solid #f5a623; padding-bottom: 8px; margin-bottom: 14px;
            }
            header h1 { margin: 0; font-size: 18px; color: #b56a00; }
            header .meta { font-size: 11px; color: #666; }
            h2.section { margin: 18px 0 6px; font-size: 14px; color: #b56a00;
                        border-bottom: 1px solid #f5d76e; padding-bottom: 4px; }
            table { width: 100%; border-collapse: collapse; background: #fff;
                    margin-bottom: 8px; }
            th, td { border-bottom: 1px solid #eee; padding: 6px 8px; text-align: left;
                     vertical-align: middle; }
            th { background: #fff5e1; color: #6a4f00; font-weight: 600; font-size: 11px;
                 border-bottom: 2px solid #f5d76e; }
            td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
            td.note { color: #666; font-size: 11px; }
            tfoot td { font-weight: 700; background: #fff5e1; border-top: 2px solid #f5d76e; }
            td.empty { text-align: center; color: #888; padding: 20px; font-style: italic; }
            .swatch {
              display: inline-block; width: 18px; height: 18px; border-radius: 3px;
              border: 1px solid #999; margin-right: 6px; vertical-align: middle;
            }
            .partial { color: #b56a00; font-weight: 600; font-size: 10px; }
            .tex { color: #b56a00; }
            .controls { margin-top: 14px; display: flex; gap: 8px; flex-wrap: wrap; }
            button {
              padding: 8px 14px; font-size: 12px; font-weight: 600;
              border: none; border-radius: 4px; cursor: pointer;
              background: #f5a623; color: #fff;
            }
            button:hover { background: #d98e0a; }
            button.secondary { background: #555; }
            button.secondary:hover { background: #333; }
            button.tertiary { background: #888; }
            button.tertiary:hover { background: #666; }
            .legend { margin-top: 12px; font-size: 11px; color: #666; line-height: 1.6; }
            .legend strong { color: #444; }
            @media print {
              body { padding: 0; background: #fff; }
              .controls { display: none; }
              header { border-bottom-color: #000; }
              header h1 { color: #000; }
              th { background: #f0f0f0; color: #000; border-bottom-color: #000; }
              tfoot td { background: #f0f0f0; border-top-color: #000; }
            }
          </style>
          </head>
          <body>
            <header>
              <div>
                <h1>CA-Wall Panel · Metraj</h1>
                <div class="meta">#{e(model_name)}</div>
              </div>
              <div class="meta">#{date_str}<br>ca//works · Cihan Aydoğdu Mimarlık</div>
            </header>

            <h2 class="section">Lambri Hatları</h2>
            <table>
              <thead>
                <tr>
                  <th>Mekan</th>
                  <th>Profil Kodu</th>
                  <th>Ad</th>
                  <th class="num">Kesit (mm)</th>
                  <th class="num">Yükseklik (mm)</th>
                  <th>Renk / Materyal</th>
                  <th class="num">Panel</th>
                  <th class="num">Ön Yüz (m)</th>
                  <th class="num">Alan (m²)</th>
                  <th class="num">Standart Parça</th>
                  <th class="num">Fire (m)</th>
                  <th>Not</th>
                </tr>
              </thead>
              <tbody>
                #{rows_html}
              </tbody>
              <tfoot>
                <tr>
                  <td colspan="6">TOPLAM</td>
                  <td class="num">#{total_panels}</td>
                  <td class="num">#{fmt_num(total_front, 2)}</td>
                  <td class="num">#{fmt_num(total_area, 2)}</td>
                  <td class="num">#{total_pieces}</td>
                  <td class="num">#{fmt_num(total_waste, 2)}</td>
                  <td></td>
                </tr>
              </tfoot>
            </table>

            <h2 class="section">Süpürgelik Hatları</h2>
            <table>
              <thead>
                <tr>
                  <th>Mekan</th>
                  <th>Profil Kodu</th>
                  <th>Ad</th>
                  <th class="num">Kesit (mm)</th>
                  <th>Renk / Materyal</th>
                  <th class="num">Toplam (m)</th>
                  <th class="num">Alan (m²)</th>
                  <th class="num">Standart Parça</th>
                  <th class="num">Fire (m)</th>
                </tr>
              </thead>
              <tbody>
                #{skirting_html}
              </tbody>
              <tfoot>
                <tr>
                  <td colspan="5">TOPLAM</td>
                  <td class="num">#{fmt_num(skirt_total_m, 2)}</td>
                  <td class="num">#{fmt_num(skirt_total_area, 2)}</td>
                  <td class="num">#{skirt_total_p}</td>
                  <td class="num">#{fmt_num(skirt_total_w, 2)}</td>
                </tr>
              </tfoot>
            </table>

            <div class="controls">
              <button onclick="window.print()">🖨 Yazdır / PDF Kaydet</button>
              <button class="secondary" onclick="sketchup.export_csv()">⤓ CSV (Excel) İndir</button>
              <button class="tertiary" onclick="sketchup.refresh()">↻ Yenile</button>
            </div>

            <div class="legend">
              <strong>Mekan:</strong> uygulamada girilen oda/mekan adı (boş ise —).
              <strong>Ön Yüz (m):</strong> panel sayısı × profil genişliği.
              <strong>Alan (m²):</strong> ön yüz × yükseklik.
              <strong>Panel +½:</strong> son lambri tam yetmediğinde kesilmiş (yarım) parça.
              <strong>Süpürgelik:</strong> path boyunca tek parça (continuous extrusion); toplam uzunluk metrelik.
            </div>
          </body>
          </html>
        HTML
      end

      def self.e(s)
        s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
      end

      def self.fmt_num(n, decimals = 2)
        sprintf("%.#{decimals}f", n.to_f).sub('.', ',')
      end

      def self.fmt_int(n)
        n.to_f.round.to_s
      end

      def self.fmt_dim(n)
        x = n.to_f
        (x == x.round) ? x.round.to_s : sprintf('%.1f', x).sub('.', ',')
      end

    end
  end
end