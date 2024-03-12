module Secretariat
  module Versioner
    def by_version(version, v1, v2_or_v3)
      if version == 1
        v1
      elsif version == 2 || version == 3
        v2_or_v3
      else
        raise "Unsupported Version: #{version}"
      end
    end
  end
end
