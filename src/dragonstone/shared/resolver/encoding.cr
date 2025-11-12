require "./decoding"
require "./checks"

module Dragonstone
    module Encoding
        DEFAULT = "utf-8"

        struct Source
            getter path : String
            getter data : String
            getter encoding : String
            getter bom : Symbol?

            def initialize(@path : String, @data : String, @encoding : String = DEFAULT, @bom : Symbol? = nil)
            end
        end

        def self.read(path : String) : Source
            bytes = read_binary(path)
            stripped = Decoding.strip_bom(bytes)
            Checks.ensure_valid_utf8!(stripped.bytes, path)
            data = begin
                Decoding.decode_utf8(stripped.bytes)
            rescue ex : ArgumentError
                raise Checks.encoding_error(path, "Unable to decode #{File.basename(path)}: #{ex.message}")
            end
            Source.new(path, data, DEFAULT, stripped.bom)
        end

        def self.read_text(path : String) : String
            read(path).data
        end

        private def self.read_binary(path : String) : Bytes
            size = File.size(path)
            return Bytes.new(0) if size == 0

            buffer = Bytes.new(size.to_i32)
            File.open(path, "rb") do |io|
                io.read_fully(buffer)
            end
            buffer
        end
    end
end
