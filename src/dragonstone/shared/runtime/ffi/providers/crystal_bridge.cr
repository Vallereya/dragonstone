module Dragonstone
    module FFI
        module Providers
            module CrystalBridge
                def self.call(function_name : String, arguments : Array(Dragonstone::FFI::InteropValue)) : Dragonstone::FFI::InteropValue
                    Dragonstone::Host.call(function_name, arguments)
                end
            end
        end
    end
end
