# ----------------------------------------------------------------
#  Arkopa Lambri — Apply Tool
#  Kullanıcı bir veya daha fazla bağlantılı edge (line/arc/circle/curve)
#  seçer; aktif profile göre kesit yüzü, ilk edge'in başlangıç noktasına
#  ve tanjantına göre dik düzlemde oluşturulur; follow-me ile path
#  boyunca uzatılır. Sonuç bir grup (Group) olarak yerleştirilir.
# ----------------------------------------------------------------

module CAWorks
  module ArkopaLambri
    module ApplyTool

      # Modül-değişkenleri (UI'dan ayarlanır)
      @active_profile_code = '18126-46'
      @flip_orientation    = false  # kesit dış yöne mi iç yöne mi baksın

      class << self
        attr_accessor :active_profile_code, :flip_orientation
      end

      # ------------------------------------------------------------
      #  GİRİŞ: Komut çalışınca seçimi alıp uygulama yapar
      # ------------------------------------------------------------
      def self.run
        model = Sketchup.active_model
        sel   = model.selection.to_a.select { |e| e.is_a?(Sketchup::Edge) }

        if sel.empty?
          UI.messagebox("Önce uygulanacak çizgi(ler)i seçin.\n\n"\
                        "Tek bir çizgi, bir yay (arc), bir daire veya birbirine "\
                        "bağlı edge'lerden oluşan bir polyline / freehand seçebilirsiniz.")
          return
        end

        profile = Profiles.find(@active_profile_code)
        unless profile
          UI.messagebox("Aktif profil bulunamadı: #{@active_profile_code}")
          return
        end

        # Seçimi sıralı/yönlü bir path'e dönüştür
        ordered = order_edges(sel)
        if ordered.nil? || ordered.empty?
          UI.messagebox("Seçili edge'ler birbirine bağlı tek bir path "\
                        "oluşturmuyor. Lütfen bağlantılı edge'leri seçin.")
          return
        end

        # Tüm edge'lerin aynı parent içinde olduğundan emin ol
        parent_entities = ordered.first.parent.entities
        unless ordered.all? { |e| e.parent.entities == parent_entities }
          UI.messagebox("Seçili edge'ler farklı bağlamlarda (grup/component) "\
                        "olamaz. Hepsi aynı düzeyde olmalı.")
          return
        end

        model.start_operation('Arkopa Lambri Uygula', true)
        begin
          group = build_lambri(model, parent_entities, ordered, profile)
          if group
            model.selection.clear
            model.selection.add(group)
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Hata: #{e.message}\n\n#{e.backtrace.first(5).join("\n")}")
        end
      end

      # ------------------------------------------------------------
      #  EDGE SIRALAMA — bağlantılı edge dizisini, ilk uçtan son uca
      #  yürüyecek biçimde sıralar. Kapalı (daire) ise herhangi bir
      #  edge'den başlar.
      # ------------------------------------------------------------
      def self.order_edges(edges)
        return [] if edges.empty?
        return edges if edges.size == 1

        # Komşuluk grafiğini kur (uç noktaları string key olarak)
        adjacency = Hash.new { |h, k| h[k] = [] }
        edges.each do |e|
          adjacency[pt_key(e.start.position)] << e
          adjacency[pt_key(e.end.position)]   << e
        end

        # Uç (degree 1) bul — açık path için
        endpoint_keys = adjacency.select { |_, es| es.size == 1 }.keys

        # Açık path
        if endpoint_keys.any?
          ordered = []
          visited = {}
          current_key = endpoint_keys.first
          while ordered.size < edges.size
            candidates = adjacency[current_key].reject { |e| visited[e] }
            break if candidates.empty?
            edge          = candidates.first
            visited[edge] = true
            ordered      << edge
            other = (pt_key(edge.start.position) == current_key) ?
                    edge.end.position : edge.start.position
            current_key = pt_key(other)
          end
          return ordered.size == edges.size ? ordered : nil
        end

        # Kapalı path (daire/closed curve) — herhangi bir edge'den başla
        ordered = []
        visited = {}
        edge    = edges.first
        ordered << edge
        visited[edge] = true
        current_key = pt_key(edge.end.position)
        while ordered.size < edges.size
          candidates = adjacency[current_key].reject { |e| visited[e] }
          break if candidates.empty?
          edge          = candidates.first
          visited[edge] = true
          ordered      << edge
          other = (pt_key(edge.start.position) == current_key) ?
                  edge.end.position : edge.start.position
          current_key = pt_key(other)
        end
        ordered.size == edges.size ? ordered : nil
      end

      # Nokta hash'lemek için tolerans-li string key
      def self.pt_key(pt, tol = 1.0e-3)
        format('%.4f,%.4f,%.4f', (pt.x / tol).round * tol,
                                  (pt.y / tol).round * tol,
                                  (pt.z / tol).round * tol)
      end

      # ------------------------------------------------------------
      #  ANA İNŞA — kesit yüzünü kur, follow-me uygula
      # ------------------------------------------------------------
      def self.build_lambri(model, entities, ordered_edges, profile)
        # Path yönünü doğru belirle
        start_pt, next_pt = determine_path_direction(ordered_edges)

        tangent = next_pt - start_pt
        if tangent.length.to_f < 1.0e-6
          UI.messagebox("Path başlangıç tanjantı hesaplanamadı.")
          return nil
        end
        tangent.normalize!

        # Yukarı (Z) referansı — kesit "yüzey" yönü için.
        z = Geom::Vector3d.new(0, 0, 1)
        up_ref = (tangent.parallel?(z)) ? Geom::Vector3d.new(1, 0, 0) : z

        # Kesit düzleminin eksenleri:
        #   x_axis: tanjanta ve up_ref'e dik (yüzey boyunca = profil genişliği)
        #   y_axis: x_axis × tangent  (derinlik = duvardan dışa)
        x_axis = up_ref * tangent
        x_axis.normalize!
        y_axis = x_axis * tangent
        y_axis.normalize!

        x_axis.reverse! if @flip_orientation

        # Kesit noktalarını dünya koordinatına dönüştür (path ortalanmış)
        local_pts = Profiles.build_profile_points(profile)
        w_inch    = profile[:width_mm].mm

        world_pts = local_pts.map do |lp|
          ox = lp.x - w_inch / 2.0  # path'i kesit ortasına ortala
          oy = lp.y                 # derinlik = +y_axis
          dx = x_axis.clone
          if ox.abs > 1.0e-9
            dx.length = ox.abs
            dx.reverse! if ox < 0
          else
            dx = Geom::Vector3d.new(0, 0, 0)
          end
          dy = y_axis.clone
          if oy.abs > 1.0e-9
            dy.length = oy.abs
            dy.reverse! if oy < 0
          else
            dy = Geom::Vector3d.new(0, 0, 0)
          end
          start_pt + dx + dy
        end

        # ÖNCESİ/SONRASI farkı için entities snapshot'ını al
        before_entities = entities.to_a

        # Kesit yüzünü direkt parent entities'e ekle.
        face = entities.add_face(world_pts)
        if face.nil?
          UI.messagebox("Kesit yüzü oluşturulamadı.\n"\
                        "Profil noktalarının düzlemsel ve geçerli olduğunu kontrol edin.")
          return nil
        end

        # Yüz normalini path tanjantına bakacak şekilde çevir.
        face.reverse! if face.normal.dot(tangent) < 0

        # follow-me uygula — kesiti path edge'leri boyunca süpür
        success = face.followme(ordered_edges)
        unless success
          UI.messagebox("follow-me başarısız oldu. "\
                        "Path geometrisi (örn. sıfır-uzunluk edge) hatalı olabilir.")
          face.erase! if face.valid?
          return nil
        end

        # Yeni oluşan entity'leri snapshot farkı ile bul
        after_entities = entities.to_a
        new_ents = after_entities - before_entities

        # Path edge'lerini gruba dahil etme (kullanıcının orijinal çizgisi
        # referans olarak yerinde kalmalı — ama follow-me bunları tükettiyse
        # zaten new_ents'te olmazlar)
        original_edge_set = ordered_edges.each_with_object({}) { |e, h| h[e] = true }
        lambri_ents = new_ents.reject { |e| original_edge_set[e] }

        if lambri_ents.empty?
          UI.messagebox("Lambri geometrisi üretilemedi.")
          return nil
        end

        group = entities.add_group(lambri_ents)
        group.name = "Arkopa #{profile[:code]}"

        # Grup attribute'una profil kodunu yaz (sonradan renklendirme için)
        group.set_attribute('caworks_arkopa', 'profile_code', profile[:code])
        group.set_attribute('caworks_arkopa', 'profile_name', profile[:name])
        group.set_attribute('caworks_arkopa', 'width_mm',  profile[:width_mm])
        group.set_attribute('caworks_arkopa', 'depth_mm',  profile[:depth_mm])

        # Varsayılan beyaz materyal
        apply_default_material(group)

        group
      end

      # Path yönünü doğru belirle: ilk edge'in hangi vertex'i ikinci edge'le
      # ortak değilse o vertex 'start'tır.
      def self.determine_path_direction(ordered_edges)
        first = ordered_edges.first
        return [first.start.position, first.end.position] if ordered_edges.size == 1

        second = ordered_edges[1]
        e_pos  = first.end.position
        s2     = second.start.position
        e2     = second.end.position

        # İlk edge'in son ucu ikinci edge'in başlangıcı veya bitişi olmalı
        if pt_key(e_pos) == pt_key(s2) || pt_key(e_pos) == pt_key(e2)
          [first.start.position, first.end.position]  # ileri yön
        else
          [first.end.position, first.start.position]  # ters yön
        end
      end

      # Varsayılan beyaz mat material
      def self.apply_default_material(group)
        model = Sketchup.active_model
        mat   = model.materials['Arkopa_Default'] ||
                model.materials.add('Arkopa_Default')
        mat.color = Sketchup::Color.new(245, 245, 240) # off-white
        group.material = mat
      end

    end
  end
end
