# frozen_string_literal: true

require "open3" unless defined?(Open3)
require "tempfile" unless defined?(Tempfile)

# Parses generated Bash with `bash -n`.
#
# Most of what this provisioner produces is shell source, and a typo in a
# heredoc is invisible to a string comparison that was written from the same
# typo. Handing the script to bash itself catches the whole class of mistake.
module BashSyntax
  # @param script [String] shell source to parse
  # @return [Boolean] true when bash accepts the script
  # @raise [RSpec::Expectations::ExpectationNotMetError] via the caller, with
  #   bash's own error message, when it does not
  def bash_syntax_ok?(script)
    Tempfile.create(["habitat-spec", ".sh"]) do |file|
      file.write(script)
      file.flush
      _out, err, status = Open3.capture3("bash", "-n", file.path)
      raise "bash rejected the generated script:\n#{err}\n---\n#{script}" unless status.success?
    end
    true
  end
end

RSpec.configure { |config| config.include BashSyntax }
