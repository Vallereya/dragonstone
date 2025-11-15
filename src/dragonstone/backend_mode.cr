module Dragonstone
    enum BackendMode
        Auto
        Native
        Core

        def self.parse(input : String) : BackendMode
            normalized = input.strip.downcase
            case normalized
            when "", "auto"
                BackendMode::Auto
            when "native", "interp", "interpreter"
                BackendMode::Native
            when "core", "vm", "compiler"
                BackendMode::Core
            else
                raise ArgumentError.new("Unknown backend '#{input}' (expected auto, native, or core)")
            end
        end

        def label : String
            case self
            when BackendMode::Auto
                "auto"
            when BackendMode::Native
                "native"
            when BackendMode::Core
                "core"
            else
                "auto"
            end
        end
    end
end
