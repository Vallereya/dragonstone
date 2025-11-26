require "../../../backend_mode"
require "yaml"

module Dragonstone
    module Stdlib
        enum ModuleRequirement
            Shared
            Native
            Core

            def self.parse(value : String) : ModuleRequirement
                case value.downcase
                when "shared"
                    ModuleRequirement::Shared
                when "native", "interpreter"
                    ModuleRequirement::Native
                when "core", "compiler", "vm"
                    ModuleRequirement::Core
                else
                    raise ArgumentError.new("Unknown stdlib module requirement '#{value}' (expected shared, native, or core)")
                end
            end

            def supports_backend?(backend : BackendMode) : Bool
                case self
                when ModuleRequirement::Shared
                    true
                when ModuleRequirement::Native
                    backend != BackendMode::Core
                when ModuleRequirement::Core
                    backend != BackendMode::Native
                else
                    false
                end
            end

            def label : String
                case self
                when ModuleRequirement::Shared
                    "shared"
                when ModuleRequirement::Native
                    "native"
                when ModuleRequirement::Core
                    "core"
                else
                    "unknown"
                end
            end

            def native_only? : Bool
                self == ModuleRequirement::Native
            end

            def core_only? : Bool
                self == ModuleRequirement::Core
            end
        end

        class ModuleMetadata
            FILE_NAME = ".dragonstone-module.yml"

            getter name : String
            getter entry : String
            getter requirement : ModuleRequirement
            getter source_path : String

            def initialize(@name : String, @entry : String, @requirement : ModuleRequirement, @source_path : String)
            end

            def self.load(path : String) : ModuleMetadata
                data = parse_yaml(path)
                name = extract_required_string(data, "name", path)
                entry = extract_string(data, "entry") || "module.ds"
                requirement = extract_string(data, "requires")
                    .try { |value| ModuleRequirement.parse(value) } || ModuleRequirement::Shared
                ModuleMetadata.new(name, entry, requirement, path)
            end

            def supports_backend?(backend : BackendMode) : Bool
                requirement.supports_backend?(backend)
            end

            def native_only? : Bool
                requirement.native_only?
            end

            def core_only? : Bool
                requirement.core_only?
            end

            def entry_path(root : String) : String
                File.expand_path(entry, root)
            end

            def description : String
                "#{name} (#{requirement.label})"
            end

            def self.metadata_path_for_entry(entry_path : String) : String?
                directory_candidate = File.join(File.dirname(entry_path), FILE_NAME)
                return directory_candidate if File.file?(directory_candidate)
                base = entry_path.rpartition(".").first
                inline_candidate = "#{base}.#{FILE_NAME}"
                return inline_candidate if File.file?(inline_candidate)
                nil
            end

            private def self.parse_yaml(path : String) : YAML::Any
                YAML.parse(File.read(path))
            rescue ex : YAML::ParseException
                raise RuntimeError.new(
                    "Invalid stdlib module metadata in #{path}: #{ex.message}",
                    hint: "Ensure the YAML is valid."
                )
            rescue ex : IO::Error
                raise RuntimeError.new("Failed to read stdlib module metadata at #{path}: #{ex.message}")
            end

            private def self.extract_required_string(data : YAML::Any, key : String, path : String) : String
                extract_string(data, key) || raise(
                    RuntimeError.new("Missing '#{key}' in stdlib module metadata #{path}")
                )
            end

            private def self.extract_string(data : YAML::Any, key : String) : String?
                value = data[key]?
                return nil unless value
                value.as_s?
            end
        end
    end
end
