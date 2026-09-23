# frozen_string_literal: true

module Tasku
  module TUI
    # Minimal append-only logger shared with the Mado Rust process.
    # Both sides write to /tmp/tasku_mado.log so button presses and
    # MadoList state transitions can be correlated in one place.
    module MadoLog
      LOG_FILE = "/tmp/tasku_mado.log"

      def self.log(msg)
        File.open(LOG_FILE, "a") { |f| f.puts "[#{Time.now.to_i}] tasku: #{msg}" }
      rescue StandardError
        nil
      end
    end
  end
end
