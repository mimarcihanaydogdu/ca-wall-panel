# ----------------------------------------------------------------
#  CA-Wall Panel — Metraj (Quantity Take-Off)
# ----------------------------------------------------------------
#  Modeldeki tüm Lambri Hatlarını gezer, profil + yükseklik bazında
#  toplam panel sayısı, ön yüz uzunluğu (m), alan (m²), gerekli
#  standart parça sayısı ve fire (m) hesaplar. HtmlDialog'da rapor
#  açar; "Yazdır / PDF" butonu ile kullanıcı sistem print menüsünden
#  PDF olarak kaydedebilir.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module Metraj

      ATTR_DICT = 'caworks_ca_wall_panel'.freeze

      @dialog = nil

      # ------------------------------------------------------------
      def self.collect_runs(model = Sketchup.active_model)
        runs = []
        walk_entities(model.entities) do |e|
          if e.is_a?(Sketchup::Group) &&
             e.get_attribute(ATTR_DICT, 'is_panel_run') == true
            runs << {
              group:        e,
              name:         e.name,
              profile_code: e.get_attribute(ATTR_DICT, 'profile_code').to_s,
              profile_name: e.get_attribute(ATTR_DICT, 'profile_name').to_s,
              height_mm:    e.get_attribute(ATTR_DICT, 'height_mm').to_f,
              flip:         e.get_attribute(ATTR_DICT, 'flip') == true,
              panel_count:  e.get_attribute(ATTR_DICT, 'panel_count').to_i,
              width_mm:     e.get_attribute(ATTR_DICT, 'width_mm').to_f,
              depth_mm:     e.get_attribute(ATTR_DICT, 'depth_mm').to_f,
              length_mm:    e.get_attribute(ATTR_DICT, 'length_mm').to_f
            }
          end
        end
        runs
      end

      def self.walk_entities(entities, &block)
        entities.each do |e|
          yield e
          if e.is_a?(Sketchup::Group)
            walk_entities(e.entities, &block) unless e.get_attribute(ATTR_DICT, 'is_panel_run') == true
          elsif e.is_a?(Sketchup::ComponentInstance)
            # Lambri panel instance'ları içinde başka panel run beklemiyoruz; geçilebilir
          end
        end
      end

      # ------------------------------------------------------------
      def self.summary
        runs = collect_runs
        groups = {}

        runs.each do |r|
          key = [r[:profile_code], r[:height_mm].round(3)]
          g = (groups[key] ||= {
            profile_code: r[:profile_code],
            profile_name: r[:profile_name],
            height_mm:    r[:height_mm],
            width_mm:     r[:width_mm],
            depth_mm:     r[:depth_mm],
            length_mm:    r[:length_mm],
            panel_count:  0,
            run_count:    0,
            run_names:    []
          })
          g[:panel_count] += r[:panel_count]
          g[:run_count]   += 1
          g[:run_names]   << r[:name]
        end

        rows = groups.values.map do |g|
          panel_count        = g[:panel_count].to_i
          width_mm           = g[:width_mm].to_f
          height_mm          = g[:height_mm].to_f
          standard_length_mm = g[:length_mm].to_f

          total_front_m = (panel_count * width_mm) / 1000.0
          total_area_m2 = total_front_m * (height_mm / 1000.0)

          if standard_length_mm <= 0
            pieces_needed = panel_count
            waste_m       = 0.0
            note          = 'standart boy bilinmiyor'
          elsif height_mm <= standard_length_mm
            panels_per_piece = (standard_length_mm / height_mm).floor
            panels_per_piece = 1 if panels_per_piece < 1
            pieces_needed    = (panel_count.to_f / panels_per_piece).ceil
            used_mm          = panels_per_piece * height_mm
            waste_per_piece  = standard_length_mm - used_mm
            tail_panels      = panel_count - (pieces_needed - 1) * panels_per_piece
            tail_used        = tail_panels * height_mm
            tail_waste       = standard_length_mm - tail_used
            full_waste       = waste_per_piece * (pieces_needed - 1)
            waste_m          = (full_waste + tail_waste) / 1000.0
            note             = "#{panels_per_piece} panel/parça"
          else
            pieces_per_panel = (height_mm / standard_length_mm).ceil
            pieces_needed    = panel_count * pieces_per_panel
            total_used_mm    = panel_count * height_mm
            total_stock_mm   = pieces_needed * standard_length_mm
            waste_m          = (total_stock_mm - total_used_mm) / 1000.0
            note             = "#{pieces_per_panel} parça/panel (ek gerekli)"
          end

          g.merge(
            total_front_m:  total_front_m.round(3),
            total_area_m2:  total_area_m2.round(3),
            pieces_needed:  pieces_needed.to_i,
            waste_m:        waste_m.round(3),
            note:           note
          )
        end

        rows
      end

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
          width:           780,
          height:          640,
          min_width:       520,
          min_height:      360,
          style:           UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(html)

        @dialog.add_action_callback('refresh') do |_ctx|
          rows2 = summary
          @dialog.set_html(render_html(rows2))
        end

        @dialog.show
      end

      def self.render_html(rows)
        total_panels = rows.sum { |r| r[:panel_count].to_i }
        total_front  = rows.sum { |r| r[:total_front_m].to_f }
        total_area   = rows.sum { |r| r[:total_area_m2].to_f }
        total_pieces = rows.sum { |r| r[:pieces_needed].to_i }
        total_waste  = rows.sum { |r| r[:waste_m].to_f }

        date_str = Time.now.strftime('%d.%m.%Y %H:%M')
        model_name = (Sketchup.active_model.title.to_s.empty? ?
                      'İsimsiz Model' : Sketchup.active_model.title)

        rows_html = if rows.empty?
          '<tr><td colspan="9" class="empty">Modelde Lambri Hattı bulunamadı.</td></tr>'
        else
          rows.sort_by { |r| [r[:profile_code], r[:height_mm]] }.map do |r|
            <<~ROW
              <tr>
                <td>#{e(r[:profile_code])}</td>
                <td>#{e(r[:profile_name])}</td>
                <td class="num">#{fmt_dim(r[:width_mm])}×#{fmt_dim(r[:depth_mm])}</td>
                <td class="num">#{fmt_int(r[:height_mm])}</td>
                <td class="num">#{r[:panel_count]}</td>
                <td class="num">#{fmt_num(r[:total_front_m], 2)}</td>
                <td class="num">#{fmt_num(r[:total_area_m2], 2)}</td>
                <td class="num">#{fmt_int(r[:length_mm])} × #{r[:pieces_needed]}</td>
                <td class="num">#{fmt_num(r[:waste_m], 2)}</td>
              </tr>
            ROW
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
            table { width: 100%; border-collapse: collapse; background: #fff; }
            th, td { border-bottom: 1px solid #eee; padding: 6px 8px; text-align: left; }
            th { background: #fff5e1; color: #6a4f00; font-weight: 600; font-size: 11px;
                 border-bottom: 2px solid #f5d76e; }
            td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
            tfoot td { font-weight: 700; background: #fff5e1; border-top: 2px solid #f5d76e; }
            td.empty { text-align: center; color: #888; padding: 20px; font-style: italic; }
            .controls { margin-top: 14px; display: flex; gap: 8px; }
            button {
              padding: 8px 14px; font-size: 12px; font-weight: 600;
              border: none; border-radius: 4px; cursor: pointer;
              background: #f5a623; color: #fff;
            }
            button:hover { background: #d98e0a; }
            button.secondary { background: #555; }
            button.secondary:hover { background: #333; }
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

            <table>
              <thead>
                <tr>
                  <th>Profil Kodu</th>
                  <th>Ad</th>
                  <th class="num">Kesit (mm)</th>
                  <th class="num">Yükseklik (mm)</th>
                  <th class="num">Panel</th>
                  <th class="num">Ön Yüz (m)</th>
                  <th class="num">Alan (m²)</th>
                  <th class="num">Standart Parça</th>
                  <th class="num">Fire (m)</th>
                </tr>
              </thead>
              <tbody>
                #{rows_html}
              </tbody>
              <tfoot>
                <tr>
                  <td colspan="4">TOPLAM</td>
                  <td class="num">#{total_panels}</td>
                  <td class="num">#{fmt_num(total_front, 2)}</td>
                  <td class="num">#{fmt_num(total_area, 2)}</td>
                  <td class="num">#{total_pieces}</td>
                  <td class="num">#{fmt_num(total_waste, 2)}</td>
                </tr>
              </tfoot>
            </table>

            <div class="controls">
              <button onclick="window.print()">🖨 Yazdır / PDF Kaydet</button>
              <button class="secondary" onclick="sketchup.refresh()">↻ Yenile</button>
            </div>

            <div class="legend">
              <strong>Ön Yüz (m):</strong> panel sayısı × profil genişliği.
              <strong>Alan (m²):</strong> ön yüz × yükseklik.
              <strong>Standart Parça:</strong> profil standart boyu × gereken parça sayısı
              (yükseklik > standart boy ise her panel için ek parça hesaplanır).
              <strong>Fire (m):</strong> kullanılmayan toplam malzeme (yükseklik bazında).
            </div>

            <script>
              // sketchup.refresh callback'i Ruby tarafında tanımlı.
            </script>
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