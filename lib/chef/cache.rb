#
# Copyright:: Copyright (c) 2016 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fileutils"
require "chef/project_manifest"
require "mixlib/install/product"
require "open-uri"

class Chef
  class Cache
    class MissingManifestFile < StandardError; end

    KNOWN_PROJECTS = PRODUCT_MATRIX.products

    KNOWN_CHANNELS = %w(
      current
      stable
    )

    attr_reader :metadata_dir

    #
    # Initializer for the cache.
    #
    # @param [String] metadata_dir
    #   the directory which will be used to create files in & read files from.
    # @param [Boolean] unified_backend
    #   flag to enable unified_backend feature.
    #
    def initialize(metadata_dir = "./metadata_dir", unified_backend = false)
      @metadata_dir = metadata_dir

      # We have this logic here because we would like to be able to easily
      # write a spec against this.
      if unified_backend
        ENV["ARTIFACTORY_ENDPOINT"] = "https://packages-acceptance.chef.io"
        ENV["MIXLIB_INSTALL_UNIFIED_BACKEND"] = "true"
      else
        ENV.delete("ARTIFACTORY_ENDPOINT")
        ENV.delete("MIXLIB_INSTALL_UNIFIED_BACKEND")
      end

      KNOWN_CHANNELS.each do |channel|
        FileUtils.mkdir_p(File.join(metadata_dir, channel))
      end
    end

    #
    # Updates the cache
    #
    # @return [void]
    #
    def update
      KNOWN_PROJECTS.each do |project|
        next unless project == 'chef'
        KNOWN_CHANNELS.each do |channel|
          next unless channel == 'stable'
          manifest = ProjectManifest.new(project, channel)
          manifest.generate

          #if settings.mirror
            downloads = []
            manifest.manifest.each do |foo, platform|
              platform.each do |foo, version|
                version.each do |foo, arch|
                  arch.each do |foo, pkg|
                    downloads.push(pkg)
                  end
                end
              end
            end

            downloads.each do |d|
              mirror_package(d[:url])
            end
          #end

          File.open(project_manifest_path(project, channel), "w") do |f|
            # TODO: replace urls if settings.mirror
            f.puts manifest.serialize
          end
        end
      end
    end

    def mirror_package(uri)
      # TODO: return if file exists with good checksum
      path = "./packages#{URI(uri).path}"
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless File.exists?(dir)

      puts "Downloading #{uri}"
      IO.copy_stream(open(uri), path)
    end

    #
    # Returns the file path for the manifest file that belongs to the given
    # project & channel.
    #
    # @parameter [String] project
    # @parameter [String] channel
    #
    # @return [String]
    #   File path of the manifest file.
    #
    def project_manifest_path(project, channel)
      File.join(metadata_dir, channel, "#{project}-manifest.json")
    end

    #
    # Returns the manifest for a given project and channel from the cache.
    #
    # @parameter [String] project
    # @parameter [String] channel
    #
    # @return
    #   [Hash] contents of the manifest file
    #
    def manifest_for(project, channel)
      manifest_path = project_manifest_path(project, channel)

      if File.exist?(manifest_path)
        JSON.parse(File.read(manifest_path))
      else
        raise MissingManifestFile, "Can not find the manifest file for '#{project}' - '#{channel}'"
      end
    end

    #
    # Returns the last updated time of the manifest for a given project and channel.
    #
    # @parameter [String] project
    # @parameter [String] channel
    #
    # @return
    #   [String] timestamp for the last modified time.
    #
    def last_modified_for(project, channel)
      manifest_path = project_manifest_path(project, channel)

      if File.exist?(manifest_path)
        manifest = JSON.parse(File.read(manifest_path))
        manifest["run_data"]["timestamp"]
      else
        raise MissingManifestFile, "Can not find the manifest file for '#{project}' - '#{channel}'"
      end
    end

  end
end
