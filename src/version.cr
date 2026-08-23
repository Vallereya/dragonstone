# -------------------------------------
# -------------- Version --------------
# -------------------------------------
module Dragonstone
    # Grabs the version from the shard.yml file.
    VERSION = {{`shards version #{__DIR__}`.chomp.stringify}}

    # Runs the version to the core to make the version.h file.
    {{run("./dragonstone/core/generate_version.cr", VERSION)}}

    # Creates a VERSION file in the src directory with the current version of Dragonstone.
    version = VERSION
    output_path = File.join(__DIR__, "VERSION")
    File.write(output_path, version)
end
