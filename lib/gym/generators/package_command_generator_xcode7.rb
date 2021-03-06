# encoding: utf-8
# from http://stackoverflow.com/a/9857493/445598
# because of
# `incompatible encoding regexp match (UTF-8 regexp with ASCII-8BIT string) (Encoding::CompatibilityError)`

module Gym
  # Responsible for building the fully working xcodebuild command
  class PackageCommandGeneratorXcode7
    class << self
      def generate
        print_legacy_information unless Helper.fastlane_enabled?

        parts = ["/usr/bin/xcrun xcodebuild -exportArchive"]
        parts += options
        parts += pipe

        File.write(config_path, config_content) # overwrite everytime. Could be optimized

        parts
      end

      def options
        options = []

        options << "-exportOptionsPlist '#{config_path}'"
        options << "-archivePath '#{BuildCommandGenerator.archive_path}'"
        options << "-exportPath '#{temporary_output_path}'"

        options
      end

      def pipe
        [""]
      end

      # We export the ipa into this directory, as we can't specify the ipa file directly
      def temporary_output_path
        Gym.cache[:temporary_output_path] ||= File.join("/tmp", Time.now.to_i.to_s)
      end

      def ipa_path
        unless Gym.cache[:ipa_path]
          path = Dir[File.join(temporary_output_path, "*.ipa")].last
          ErrorHandler.handle_empty_archive unless path

          Gym.cache[:ipa_path] = File.join(temporary_output_path, "#{Gym.config[:output_name]}.ipa")
          FileUtils.mv(path, Gym.cache[:ipa_path]) if File.expand_path(path).downcase != File.expand_path(Gym.cache[:ipa_path]).downcase
        end
        Gym.cache[:ipa_path]
      end

      # The path the the dsym file for this app. Might be nil
      def dsym_path
        Dir[BuildCommandGenerator.archive_path + "/**/*.app.dSYM"].last
      end

      # The path the config file we use to sign our app
      def config_path
        Gym.cache[:config_path] ||= "/tmp/gym_config_#{Time.now.to_i}.plist"
        return Gym.cache[:config_path]
      end

      private

      def config_content
        require 'plist'

        hash = { method: Gym.config[:export_method] }

        if Gym.config[:export_method] == 'app-store'
          hash[:uploadSymbols] = (Gym.config[:include_symbols] ? true : false)
          hash[:uploadBitcode] = (Gym.config[:include_bitcode] ? true : false)
        end
        hash[:teamID] = Gym.config[:export_team_id] if Gym.config[:export_team_id]

        hash.to_plist
      end

      def print_legacy_information
        if Gym.config[:provisioning_profile_path]
          Helper.log.info "You're using Xcode 7, the `provisioning_profile_path` value will be ignored".yellow
          Helper.log.info "Please follow the Code Signing Guide: https://github.com/KrauseFx/fastlane/blob/master/docs/CodeSigning.md".yellow
        end
      end
    end
  end
end
