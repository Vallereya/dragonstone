# ---------------------------------
# ------------ Version ------------
# ---------------------------------
module Dragonstone
    # Grabs the version from the shard.yml file.
    VERSION = {{`shards version #{__DIR__}`.chomp.stringify}}

    # Runs the version to the core to make the version.h file.
    {{run("./dragonstone/core/generate_version.cr", VERSION)}}
end