# frozen_string_literal: true

require "io/console"
require "pastel"

require_relative "tab"
require_relative "tabs/calendar_tab"
require_relative "tabs/tasks_tab"
require_relative "tabs/notes_tab"
require_relative "tabs/weather_tab"

module Tasku
  module TUI
    class App
      MIN_WIDTH = 80
      MIN_HEIGHT = 10

      def initialize
        @pastel = Pastel.new
        @tabs = [
          Tabs::CalendarTab.new,
          Tabs::TasksTab.new,
          Tabs::NotesTab.new,
          Tabs::WeatherTab.new
        ]
        @active_tab = 0
        @running = true
      end

      def run
        check_terminal_size

        unless $stdin.tty?
          puts "Tasku TUI requires an interactive terminal."
          exit 1
        end

        $stdout.print "\e[?25l\e[2J"
        at_exit { restore_terminal }
        trap("INT") { @running = false }

        $stdin.raw do |io|
          render
          while @running
            key = read_key(io)
            handle_key(key)
            render unless key.nil?
          end
        end
      end

      private

      def check_terminal_size
        w = IO.console&.winsize&.[](1) || 80
        h = IO.console&.winsize&.[](0) || 24
        if w < MIN_WIDTH
          puts "Error: terminal needs at least #{MIN_WIDTH} columns wide (currently #{w})."
          exit 1
        end
        if h < MIN_HEIGHT
          puts "Error: terminal needs at least #{MIN_HEIGHT} rows tall (currently #{h})."
          exit 1
        end
      end

      def restore_terminal
        $stdout.print "\e[?25h\e[0m\e[2J\e[H"
      rescue IOError
      end

      def render
        rows = []
        rows << render_titlebar
        rows << render_tab_bar
        rows << pastel_dash_line
        rows.concat(render_content)
        rows << ""
        rows << @pastel.dim("  <- -> / 1-4: switch tab  |  q: quit")

        $stdout.print "\e[H\e[J"
        $stdout.print rows.join("\r\n")
        $stdout.flush
      end

      def render_titlebar
        title = "  Tasku  "
        right = "  #{Time.now.strftime('%H:%M')}  "
        padding = MIN_WIDTH - visible_width(title) - visible_width(right) - 4
        middle = padding.positive? ? " " * padding : ""
        @pastel.on_blue.white.bold("  #{title}#{middle}#{right}  ")
      end

      def render_tab_bar
        tabs = @tabs.each_with_index.map do |tab, i|
          if i == @active_tab
            @pastel.on_blue.white.bold("  #{tab.name}  ")
          else
            @pastel.dim("  #{tab.name}  ")
          end
        end

        total = tabs.sum { |t| visible_width(t) }
        padding = MIN_WIDTH - total - 2
        pad = padding.positive? ? " " * padding : ""
        " #{tabs.join}#{pad}"
      end

      def pastel_dash_line
        @pastel.dim("-" * MIN_WIDTH)
      end

      def render_content
        tab = @tabs[@active_tab]
        available = (IO.console&.winsize&.[](0) || 24) - 5
        available = [available, 3].max
        tab.render(@pastel, MIN_WIDTH, available)
      end

      def read_key(io)
        byte = io.getbyte
        case byte
        when 0x1B
          bracket = io.getbyte
          if bracket == 0x5B
            case io.getbyte
            when 0x43 then :right
            when 0x44 then :left
            when 0x41 then :up
            when 0x42 then :down
            else nil
            end
          elsif bracket == 0x1B
            nil
          else
            :escape
          end
        when 0x03 then :ctrl_c
        when 0x71 then :q
        when 0x31 then :one
        when 0x32 then :two
        when 0x33 then :three
        when 0x34 then :four
        when 0x09 then :tab
        else nil
        end
      end

      def handle_key(key)
        case key
        when :right, :tab
          @active_tab = (@active_tab + 1) % @tabs.length
        when :left
          @active_tab = (@active_tab - 1) % @tabs.length
        when :one   then @active_tab = 0
        when :two   then @active_tab = 1
        when :three then @active_tab = 2
        when :four  then @active_tab = 3
        when :q, :ctrl_c, :escape
          @running = false
        end
      end

      def visible_width(str)
        str.gsub(/\e\[[0-9;]*m/, "").length
      end
    end
  end
end
