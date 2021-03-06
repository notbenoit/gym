require 'pty'
require 'open3'
require 'fileutils'

module Gym
  class Runner
    # @return (String) The path to the resulting ipa
    def run
      clear_old_files
      build_app
      verify_archive

      FileUtils.mkdir_p(Gym.config[:output_directory])

      if Gym.project.ios?
        package_app
        fix_package
        compress_and_move_dsym
        move_ipa
      elsif Gym.project.mac?
        compress_and_move_dsym
        move_mac_app
      else
        # For tvOS Build, use iOS
        package_app
        fix_package
        compress_and_move_dsym
        move_ipa
      end
    end

    #####################################################
    # @!group Printing out things
    #####################################################

    # @param [Array] An array containing all the parts of the command
    def print_command(command, title)
      rows = command.map do |c|
        current = c.to_s.dup
        next unless current.length > 0

        match_default_parameter = current.match(/(-.*) '(.*)'/)
        if match_default_parameter
          # That's a default parameter, like `-project 'Name'`
          match_default_parameter[1, 2]
        else
          current.gsub!("| ", "\| ") # as the | will somehow break the terminal table
          [current, ""]
        end
      end

      puts Terminal::Table.new(
        title: title.green,
        headings: ["Option", "Value"],
        rows: rows.delete_if { |c| c.to_s.empty? }
      )
    end

    private

    #####################################################
    # @!group The individual steps
    #####################################################

    def clear_old_files
      return unless Gym.config[:use_legacy_build_api]
      if File.exist?(PackageCommandGenerator.ipa_path)
        File.delete(PackageCommandGenerator.ipa_path)
      end
    end

    def fix_package
      return unless Gym.config[:use_legacy_build_api]
      Gym::XcodebuildFixes.swift_library_fix
      Gym::XcodebuildFixes.watchkit_fix
      Gym::XcodebuildFixes.watchkit2_fix
    end

    # Builds the app and prepares the archive
    def build_app
      command = BuildCommandGenerator.generate
      print_command(command, "Generated Build Command") if $verbose
      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: !Gym.config[:silent],
                                              error: proc do |output|
                                                ErrorHandler.handle_build_error(output)
                                              end)

      Helper.log.info("Successfully stored the archive. You can find it in the Xcode Organizer.".green)
      Helper.log.info("Stored the archive in: ".green + BuildCommandGenerator.archive_path) if $verbose
    end

    # Makes sure the archive is there and valid
    def verify_archive
      # from https://github.com/fastlane/gym/issues/115
      if (Dir[BuildCommandGenerator.archive_path + "/*"]).count == 0
        ErrorHandler.handle_empty_archive
      end
    end

    def package_app
      command = PackageCommandGenerator.generate
      print_command(command, "Generated Package Command") if $verbose

      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: !Gym.config[:silent],
                                              error: proc do |output|
                                                ErrorHandler.handle_package_error(output)
                                              end)
    end

    def compress_and_move_dsym
      return unless PackageCommandGenerator.dsym_path

      # Compress and move the dsym file
      containing_directory = File.expand_path("..", PackageCommandGenerator.dsym_path)

      available_dsyms = Dir.glob("#{containing_directory}/*.dSYM")

      Helper.log.info "Compressing #{available_dsyms.count} dSYM(s)"

      output_path = File.expand_path(File.join(Gym.config[:output_directory], Gym.config[:output_name] + ".app.dSYM.zip"))
      command = "cd '#{containing_directory}' && zip -r '#{output_path}' *.dSYM"
      Helper.log.info command.yellow unless Gym.config[:silent]
      command_result = `#{command}`
      Helper.log.info command_result if $verbose

      puts "" # new line

      Helper.log.info "Successfully exported and compressed dSYM file".green
    end

    # Moves over the binary and dsym file to the output directory
    # @return (String) The path to the resulting ipa file
    def move_ipa
      FileUtils.mv(PackageCommandGenerator.ipa_path, File.expand_path(Gym.config[:output_directory]), force: true)
      ipa_path = File.expand_path(File.join(Gym.config[:output_directory], File.basename(PackageCommandGenerator.ipa_path)))

      Helper.log.info "Successfully exported and signed the ipa file:".green
      Helper.log.info ipa_path
      ipa_path
    end

    # Move the .app from the archive into the output directory
    def move_mac_app
      app_path = Dir[File.join(BuildCommandGenerator.archive_path, "Products/Applications/*.app")].last
      raise "Couldn't find application in '#{BuildCommandGenerator.archive_path}'".red unless app_path

      FileUtils.mv(app_path, File.expand_path(Gym.config[:output_directory]), force: true)
      app_path = File.join(Gym.config[:output_directory], File.basename(app_path))

      Helper.log.info "Successfully exported the .app file:".green
      Helper.log.info app_path
      app_path
    end

    private

    def find_archive_path
      if Gym.config[:use_legacy_build_api]
        BuildCommandGenerator.archive_path
      else
        Dir.glob(File.join(BuildCommandGenerator.build_path, "*.ipa")).last
      end
    end
  end
end
