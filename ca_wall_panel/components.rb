# ----------------------------------------------------------------
#  CA-Wall Panel — Component Definition Manager
# ----------------------------------------------------------------
#  Profil + yükseklik kombinasyonu için tek bir ComponentDefinition
#  oluşturulur ve cache'lenir. Aynı kombinasyona ait tüm paneller bu
#  definition'ın instance'larıdır → kullanıcı definition içine girip
#  değişiklik yapınca tüm paneller birlikte güncellenir.
#
#  Önemli: definition içindeki yüzlere materyal atanmaz; renklendirme
#  ComponentInstance üzerine yapılır → kullanıcı renk değiştirdiğinde
#  görünür.
# ----------------------------------------------------------------

module CAWorks
  module CAWallPanel
    module Components

      ATTR_DICT = 'caworks_ca_wall_panel'.freeze

      def self.def_name(profile, height_mm)
        "CA-Lambri #{profile[:code]} h#{height_mm.round}mm"
      end

      def self.find_definition(profile, height_mm)
        Sketchup.active_model.definitions[def_name(profile, height_mm)]
      end

      def self.get_or_create(profile, height_mm)
        model = Sketchup.active_model
        name  = def_name(profile, height_mm)
        defn  = model.definitions[name]
        return defn if defn && defn.entities.length > 0

        defn ||= model.definitions.add(name)
        defn.entities.clear! if defn.entities.length > 0

        local_pts   = Profiles.build_profile_points(profile)
        height_inch = height_mm.mm

        face = defn.entities.add_face(local_pts)
        if face.nil?
          raise "Profil yüzeyi oluşturulamadı: #{profile[:code]}"
        end

        z_up = Geom::Vector3d.new(0, 0, 1)
        face.reverse! if face.normal.dot(z_up) < 0
        face.pushpull(height_inch)

        defn.set_attribute(ATTR_DICT, 'profile_code', profile[:code])
        defn.set_attribute(ATTR_DICT, 'profile_name', profile[:name])
        defn.set_attribute(ATTR_DICT, 'width_mm',  profile[:width_mm].to_f)
        defn.set_attribute(ATTR_DICT, 'depth_mm',  profile[:depth_mm].to_f)
        defn.set_attribute(ATTR_DICT, 'height_mm', height_mm.to_f)
        defn.set_attribute(ATTR_DICT, 'pattern',   profile[:pattern].to_s)

        defn.description = "CA-Wall Panel · #{profile[:name]} · " \
                           "#{profile[:width_mm]}×#{profile[:depth_mm]}× " \
                           "h:#{height_mm.round}mm"

        # Yüzlere materyal atanmaz → ComponentInstance / Group materyali görünür.
        defn
      end

    end
  end
end