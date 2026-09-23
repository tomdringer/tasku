# frozen_string_literal: true

require "io/console"
require "shellwords"
require "pastel"
require_relative "mado_log"

module Tasku
  module TUI
    # Interactive cursor-based task list for the Mado terminal multiplexer.
    # Triggered when ENV["MADO"] == "1". Arrow keys move the cursor; the
    # selected task's ID is written to ENV["TASKU_SEL_FILE"] so that Mado
    # button handlers can inject it into commands like `tasku edit <id>`.
    class MadoList
      HINT = "  ↑↓ navigate   a add   e/↵ edit   d delete   s stats   q quit"

      def initialize(tasks, colour_map: {}, bar: {}, cols_cfg: {}, project: nil, list_cmd: nil)
        @tasks      = tasks
        @cursor     = 0
        @pastel     = Pastel.new
        @sel_file   = ENV["TASKU_SEL_FILE"]
        @running    = true
        @inline_cmd = nil
        @list_cmd   = list_cmd || (project ? "tasku list --project #{Shellwords.shellescape(project)}" : "tasku list")

        # Pre-render row content once so key-press redraws are cheap.
        table      = Output::Terminal.new.build_mado_rows(tasks, colour_map, bar, cols_cfg)
        @rows      = table[:rows]
        @row_width = table[:row_width]
        @header    = table[:header]

        MadoLog.log("init tasks=#{tasks.length} cols_file=#{ENV["TASKU_COLS_FILE"]&.then { |f| File.read(f).strip rescue "?" }}")
      end

      def run
        MadoLog.log("run tasks=#{@tasks.length}")
        write_selection unless @tasks.empty?

        $stdout.print "\e[?25l"  # hide cursor
        at_exit { restore_terminal }
        trap("INT") { MadoLog.log("SIGINT received"); @running = false }

        $stdin.raw do |io|
          full_render
          while @running
            prev = @cursor
            key  = read_key(io)
            MadoLog.log("key=#{key.inspect} cursor=#{@cursor} tasks=#{@tasks.length}") unless key.nil?
            handle_key(key)
            full_render if @running && @cursor != prev
          end
        end
        MadoLog.log("run exited normally")
      end

      private

      def write_selection
        return unless @sel_file
        File.write(@sel_file, @tasks[@cursor].id.to_s)
      rescue StandardError
        nil
      end

      # Full clear + repaint (initial draw or after a command).
      def full_render
        $stdout.print "\e[3J\e[H\e[2J"
        if @tasks.empty?
          $stdout.print "\r\n  #{@pastel.dim("No tasks found.")}\r\n"
          $stdout.print "\r\n#{@pastel.dim("  Press any key to return to list…")}\r\n"
          $stdout.flush
          return
        end
        border = @pastel.dim("  " + "─" * (@row_width + 4))
        $stdout.print "#{border}\r\n"
        $stdout.print "  #{@pastel.dim("   ")} #{@header}\r\n" if @header
        $stdout.print "#{border}\r\n"
        @rows.each_with_index do |row, i|
          if i == @cursor
            marker  = @pastel.bright_blue("[>]")
            # Re-apply the highlight background after every ANSI reset so it
            # persists through pre-rendered colour codes embedded in the row.
            content = "  #{marker} #{row}".gsub("\e[0m", "\e[0m\e[48;5;236m")
            $stdout.print "\e[48;5;236m#{content}\e[48;5;236m\e[K\e[0m\r\n"
          else
            marker = @pastel.dim("[ ]")
            $stdout.print "  #{marker} #{row}\r\n"
          end
        end
        $stdout.print "#{border}\r\n"
        $stdout.print "#{@pastel.dim("  #{@tasks.length} task(s) found")}\r\n"
        $stdout.print "\r\n#{@pastel.dim(HINT)}\r\n"
        $stdout.flush
      end

      def read_key(io)
        byte = io.getbyte
        case byte
        when 0x02 # STX — inline exec protocol from Mado buttons.
                  # Read the command string until newline; store it and
                  # return :inline_exec so handle_key can exec it directly
                  # without relying on the shell to pick up buffered input.
          cmd = "".b
          loop do
            b = io.getbyte
            break if b.nil? || b == 0x0A
            cmd << b
          end
          @inline_cmd = cmd.force_encoding("UTF-8").scrub
          :inline_exec
        when 0x1B
          second = io.getbyte
          if second == 0x5B
            case io.getbyte
            when 0x41 then :up
            when 0x42 then :down
            else nil
            end
          else
            :escape
          end
        when 0x03       then :ctrl_c
        when 0x0D, 0x0A then :enter    # Return / Enter
        when 0x61       then :add      # a
        when 0x64       then :delete   # d
        when 0x65       then :edit     # e
        when 0x71       then :q        # q
        when 0x73       then :stats    # s
        else nil
        end
      end

      def handle_key(key)
        if @tasks.empty?
          case key
          when :ctrl_c, :escape
            @running = false
          else
            run_command("true")  # any other key → exec tasku list
          end
          return
        end
        case key
        when :up
          @cursor = [@cursor - 1, 0].max
          write_selection
        when :down
          @cursor = [@cursor + 1, @tasks.length - 1].min
          write_selection
        when :q, :ctrl_c, :escape
          @running = false
        when :add
          run_command("tasku add -i")
        when :edit, :enter
          return if @tasks.empty?
          run_command("tasku edit #{@tasks[@cursor].id} -i")
        when :delete
          return if @tasks.empty?
          run_command("tasku delete #{@tasks[@cursor].id} -f")
        when :stats
          run_and_show("tasku stats")
        when :inline_exec
          cmd = @inline_cmd.to_s
          MadoLog.log("inline_exec cmd=#{cmd.inspect}")
          if cmd == "SQL"
            run_sql
          elsif cmd.start_with?("tasku list")
            # exec directly so the new MadoList initialises with the correct
            # @list_cmd (project filter, status filter, etc.).  Using
            # run_command would nest a subprocess and then re-exec @list_cmd
            # (no filter) when the subprocess exits — losing the filter.
            # Must restore terminal + cooked mode before exec so the new
            # process doesn't inherit raw-mode terminal attributes.
            @running = false
            restore_terminal
            $stdin.cooked!
            MadoLog.log("inline_exec tasku list → exec #{cmd.inspect}")
            exec(cmd)
          else
            run_command(cmd)
          end
        end
      end

      # Restore the terminal, run a tasku command interactively, then re-exec
      # `tasku list` so the MadoList restarts fresh with updated data.
      def run_command(cmd)
        MadoLog.log("run_command cmd=#{cmd.inspect}")
        @running = false
        restore_terminal
        $stdin.cooked!
        system(cmd)
        MadoLog.log("run_command finished cmd=#{cmd.inspect} → exec #{@list_cmd}")
        exec(@list_cmd)
      end

      # Run a non-interactive display command, wait for any keypress via
      # getch (works in cooked mode — no raw-mode setup needed), then
      # re-exec `tasku list`.
      def run_and_show(cmd)
        MadoLog.log("run_and_show cmd=#{cmd.inspect}")
        @running = false
        restore_terminal
        $stdin.cooked!
        system(cmd)
        $stdout.print "\r\n\e[2m  Press any key to return to list…\e[0m\r\n"
        $stdout.flush
        $stdin.getch
        MadoLog.log("run_and_show keypress received → exec #{@list_cmd}")
        exec(@list_cmd)
      end

      # Show a SQL prompt, run the query, wait for keypress, then re-exec list.
      def run_sql
        MadoLog.log("run_sql")
        @running = false
        restore_terminal
        $stdin.cooked!
        $stdout.print "\r\n\e[36m  SELECT * FROM tasks WHERE status = 'todo'\e[0m\r\n\r\n"
        $stdout.print "\e[2m  SQL> \e[0m"
        $stdout.flush
        q = $stdin.gets&.chomp
        if q && !q.empty?
          system("tasku", "sql", q)
          $stdout.print "\r\n\e[2m  Press any key to return to list…\e[0m\r\n"
          $stdout.flush
          $stdin.getch
        end
        MadoLog.log("run_sql done → exec #{@list_cmd}")
        exec(@list_cmd)
      end

      def restore_terminal
        $stdout.print "\e[?25h\e[0m"
      rescue IOError
        nil
      end
    end
  end
end
