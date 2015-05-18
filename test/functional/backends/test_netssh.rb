require 'helper'
require 'securerandom'
require 'benchmark'

module SSHKit

  module Backend

    class TestNetssh < FunctionalTest

      def setup
        super
        @output = String.new
        SSHKit.config.output_verbosity = :debug
        SSHKit.config.output = SSHKit::Formatter::SimpleText.new(@output)
      end

      def a_host
        VagrantWrapper.hosts['one']
      end

      def test_simple_netssh
        Netssh.new(a_host) do
          execute 'date'
          execute :ls, '-l'
          with rails_env: :production do
           within '/tmp' do
             as :root do
               execute :touch, 'restart.txt'
             end
           end
          end
        end.run

        command_lines = @output.lines.select { |line| line.start_with?('Command:') }
        assert_equal <<-EOEXPECTED.unindent, command_lines.join
          Command: /usr/bin/env date
          Command: /usr/bin/env ls -l
          Command: if test ! -d /tmp; then echo \"Directory does not exist '/tmp'\" 1>&2; false; fi
          Command: if ! sudo -u root whoami > /dev/null; then echo \"You cannot switch to user 'root' using sudo, please check the sudoers file\" 1>&2; false; fi
          Command: cd /tmp && ( RAILS_ENV=production sudo -u root RAILS_ENV=production -- sh -c '/usr/bin/env touch restart.txt' )
        EOEXPECTED
      end

      def test_capture
        captured_command_result = nil
        Netssh.new(a_host) do |host|
          captured_command_result = capture(:uname)
        end.run

        assert_includes %W(Linux Darwin), captured_command_result
      end

      def test_ssh_option_merge
        a_host.ssh_options = { paranoid: true }
        host_ssh_options = {}
        SSHKit::Backend::Netssh.config.ssh_options = { forward_agent: false }
        Netssh.new(a_host) do |host|
          capture(:uname)
          host_ssh_options = host.ssh_options
        end.run
        assert_equal({ forward_agent: false, paranoid: true }, host_ssh_options)
      end

      def test_execute_raises_on_non_zero_exit_status_and_captures_stdout_and_stderr
        err = assert_raises SSHKit::Command::Failed do
          Netssh.new(a_host) do |host|
            execute :echo, "'Test capturing stderr' 1>&2; false"
          end.run
        end
        assert_equal "echo exit status: 1\necho stdout: Nothing written\necho stderr: Test capturing stderr\n", err.message
      end

      def test_test_does_not_raise_on_non_zero_exit_status
        Netssh.new(a_host) do |host|
          test :false
        end.run
      end

      def test_upload_and_then_capture_file_contents
        actual_file_contents = ""
        file_name = File.join("/tmp", SecureRandom.uuid)
        File.open file_name, 'w+' do |f|
          f.write "Some Content\nWith a newline and trailing spaces    \n "
        end
        Netssh.new(a_host) do
          upload!(file_name, file_name)
          actual_file_contents = capture(:cat, file_name, strip: false)
        end.run
        assert_equal "Some Content\nWith a newline and trailing spaces    \n ", actual_file_contents
      end

      def test_upload_string_io
        file_contents = ""
        Netssh.new(a_host) do |host|
          file_name = File.join("/tmp", SecureRandom.uuid)
          upload!(StringIO.new('example_io'), file_name)
          file_contents = download!(file_name)
        end.run
        assert_equal "example_io", file_contents
      end

      def test_upload_large_file
        size      = 25
        fills     = SecureRandom.random_bytes(1024*1024)
        file_name = "/tmp/file-#{size}.txt"
        File.open(file_name, 'w') do |f|
          (size).times {f.write(fills) }
        end
        file_contents = ""
        Netssh.new(a_host) do
          upload!(file_name, file_name)
          file_contents = download!(file_name)
        end.run
        assert_equal File.open(file_name).read, file_contents
      end

      def test_interaction_handler
        captured_command_result = nil
        Netssh.new(a_host) do
          command = 'echo Enter Data; read the_data; echo Captured $the_data;'
          captured_command_result = capture(command, interaction_handler: {
            "Enter Data\n" => "SOME DATA\n",
            "Captured SOME DATA\n" => nil
          })
        end.run
        assert_equal("Enter Data\nCaptured SOME DATA", captured_command_result)
      end
    end

  end

end
