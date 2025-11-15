# ---------------------------------
# ------------ Version ------------
# ---------------------------------
version = `shards version`.chomp

output_path = File.join(__DIR__, "runtime/include/dragonstone/core/version.h")
File.write(output_path, <<-HEADER
    #pragma once
    #define DRAGONSTONE_VERSION "#{version}"
    HEADER
)
