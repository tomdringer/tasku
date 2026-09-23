# frozen_string_literal: true

require "date"

module Tasku
  module TUI
    module Tabs
      class CalendarTab < Tab
        MONTHS = %w[January February March April May June July August September October November December].freeze
        MONTH_COUNT = 6
        COL_WIDTH = 22
        COL_GAP = 2
        COLS_PER_ROW = 3
        AGENDA_DAYS = 30

        def initialize
          super("Calendar")
          @today = Date.today
        end

        def render(pastel, width, height)
          tasks_by_day = load_tasks_by_day

          months = MONTH_COUNT.times.map { |i| @today >> i }
          groups = months.each_slice(COLS_PER_ROW).to_a

          lines = []
          row_width = COLS_PER_ROW * COL_WIDTH + (COLS_PER_ROW - 1) * COL_GAP
          left_pad = width > row_width ? ((width - row_width) / 2).clamp(0, width) : 0

          groups.each do |group|
            month_lines = group.map { |date| month_grid(pastel, date, tasks_by_day) }
            max_rows = month_lines.map(&:length).max

            max_rows.times do |i|
              row_cells = month_lines.map do |ml|
                i < ml.length ? pad_visible(ml[i], COL_WIDTH) : " " * COL_WIDTH
              end
              lines << (" " * left_pad) + row_cells.join(" " * COL_GAP)
            end

            lines << ""
          end

          lines << pastel.dim("Upcoming")
          lines << pastel.dim("─" * [width, 40].min)

          AGENDA_DAYS.times do |i|
            day = @today + i
            day_tasks = tasks_by_day[day] || []
            label = day == @today ? "Today" : day.strftime("%-d %b")
            weekday = day.strftime("%a")

            if day_tasks.empty?
              lines << "  #{pastel.dim("#{weekday} #{label.ljust(10)}")}"
            else
              lines << "  #{pastel.bold("#{weekday} #{label}")}"
              day_tasks.each do |t|
                overdue = t.due_day < @today && !%w[done cancelled].include?(t.status.to_s)
                name = t.name.to_s
                name = name.length > 40 ? "#{name[0..38]}…" : name
                bullet = overdue ? pastel.red("● ") : pastel.yellow("● ")
                lines << "    #{bullet}#{name}"
              end
            end
          end

          lines
        end

        private

        def load_tasks_by_day
          Task.dataset
              .exclude(due_day: nil)
              .where { due_day >= @today - 1 }
              .order(:due_day)
              .all
              .group_by(&:due_day)
        end

        def pad_visible(str, target)
          vis = str.gsub(/\e\[[0-9;]*m/, "").length
          pad = target - vis
          pad.positive? ? str + (" " * pad) : str
        end

        def month_grid(pastel, date, tasks_by_day)
          lines = []
          year = date.year
          month = date.month

          header = "#{MONTHS[month - 1]} #{year}"
          lines << header.center(COL_WIDTH)

          lines << "Mo Tu We Th Fr Sa Su"

          first = Date.new(year, month, 1)
          last = Date.new(year, month, -1)
          col = (first.wday + 6) % 7
          day_num = 1

          while day_num <= last.day
            week = "   " * col

            while day_num <= last.day
              d = Date.new(year, month, day_num)
              day_str = day_num.to_s.rjust(2, "0")
              is_today = d == @today
              has_tasks = tasks_by_day.key?(d)

              if is_today
                week += "#{pastel.on_blue.white.bold(day_str)} "
              elsif has_tasks
                overdue = tasks_by_day[d].any? { |t| d < @today && !%w[done cancelled].include?(t.status.to_s) }
                week += overdue ? "#{pastel.red(day_str)} " : "#{pastel.yellow(day_str)} "
              else
                week += "#{day_str} "
              end
              col += 1
              day_num += 1
              break if col == 7
            end

            lines << week
            col = 0
          end

          lines
        end
      end
    end
  end
end
