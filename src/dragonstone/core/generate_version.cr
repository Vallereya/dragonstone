# ---------------------------------
# ------------ Version ------------
# ---------------------------------
version = `shards version`.chomp

File.write(File.join(__DIR__, "version.h"), <<-HEADER
    #pragma once
    #define DRAGONSTONE_VERSION "#{version}"
    HEADER
)