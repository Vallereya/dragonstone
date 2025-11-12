module Dragonstone
    module Encoding
        module Decoding
            UTF8_BOM_PREFIX = {0xEF_u8, 0xBB_u8, 0xBF_u8}

            struct Result
                getter bytes : Bytes
                getter bom : Symbol?

                def initialize(@bytes : Bytes, @bom : Symbol?)
                end
            end

            def self.strip_bom(bytes : Bytes) : Result
                return Result.new(bytes, nil) unless has_utf8_bom?(bytes)
                Result.new(bytes[UTF8_BOM_PREFIX.size, bytes.size - UTF8_BOM_PREFIX.size], :utf8)
            end

            def self.decode_utf8(bytes : Bytes) : String
                String.new(bytes)
            end

            private def self.has_utf8_bom?(bytes : Bytes) : Bool
                return false if bytes.size < UTF8_BOM_PREFIX.size
                UTF8_BOM_PREFIX.each_with_index do |byte, index|
                    return false unless bytes[index] == byte
                end
                true
            end
        end
    end
end
