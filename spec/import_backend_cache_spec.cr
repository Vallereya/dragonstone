require "spec"
require "file_utils"
require "../src/dragonstone"

describe "Import caching across backend fallback" do
  it "does not reuse a core-compiled import when retrying on native backend" do
    dir = File.join(Dir.tempdir, "dragonstone-import-cache-#{Random::Secure.hex(8)}")
    FileUtils.mkdir_p(dir)
    begin
      header_dir = File.join(dir, "version_test")
      header_file = File.join(header_dir, "test_file.h")
      toml_path = File.expand_path("examples/test.toml", Dir.current)

      File.tempfile("dragonstone-import-cache", suffix: ".ds", dir: dir) do |file|
        file.print <<-DS
        use "file_utilities"
        use "toml"

        LOCATION = #{header_dir.inspect}
        Path.create(LOCATION)

        HEADER_FILE = #{header_file.inspect}
        File.create(HEADER_FILE, "#pragma once\\n", true)

        test_config = TOML.parse_file(#{toml_path.inspect})
        test_name = test_config["TEST"].as_h["name"].as_s
        File.append(HEADER_FILE, test_name, true)

        echo File.read(HEADER_FILE)
        DS
        file.flush

        result = Dragonstone.run_file(file.path, backend: Dragonstone::BackendMode::Auto)
        result.output.should contain("Test Name")
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
