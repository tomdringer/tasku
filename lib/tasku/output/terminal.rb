# frozen_string_literal: true

require "pastel"

module Tasku
  module Output
    class Terminal
      PRIORITY_STYLES = {
        "none"   => { color: :dim,    symbol: " " },
        "low"    => { color: :cyan,   symbol: "↓" },
        "medium" => { color: :yellow, symbol: "■" },
        "high"   => { color: :red,    symbol: "▲" },
        "urgent" => { color: :bright_magenta, symbol: "‼" }
      }.freeze

      STATUS_STYLES = {
        "backlog"     => { color: :dim,    symbol: "○" },
        "todo"        => { color: :blue,   symbol: "○" },
        "in_progress" => { color: :yellow, symbol: "◉" },
        "done"        => { color: :green,  symbol: "✓" },
        "cancelled"   => { color: :red,    symbol: "✗" },
        "archived"    => { color: :dim,    symbol: "⊘" }
      }.freeze

      COL_SEP = "  "

      def initialize
        @pastel = Pastel.new
        @term_width = [terminal_width, 80].min
      end

      def render_list(tasks)
        if tasks.empty?
          puts @pastel.yellow("  No tasks found.")
          return
        end

        rows = tasks.map { |t| build_columns(t) }
        col_widths = compute_widths(rows)
        total = col_widths.sum + (COL_SEP.length * (col_widths.length - 1))

        puts ""
        puts @pastel.dim("  #{"─" * total}")
        rows.each do |cols|
          line = cols.each_with_index.map { |c, i| c.to_s.ljust(col_widths[i]) }.join(COL_SEP)
          puts "  #{line}"
        end
        puts @pastel.dim("  #{"─" * total}")
        puts @pastel.dim("  #{tasks.length} task(s) found")
      end

      def render_show(task)
        puts ""
        puts @pastel.bold("  Task ##{task.id}")
        puts @pastel.dim("  #{"─" * 60}")

        fields = [
          ["Name",       @pastel.bold(task.name)],
          ["Description", task.description ? @pastel.dim(task.description) : @pastel.dim("—")],
          ["Project",    task.project || @pastel.dim("—")],
          ["Category",   task.category || @pastel.dim("—")],
          ["Priority",   priority_tag(task.priority)],
          ["Status",     status_tag(task.status)],
          ["Start Day",  task.start_day ? task.start_day.to_s : @pastel.dim("—")],
          ["Due Day",    due_cell(task)],
          ["Code",       task.code || @pastel.dim("—")],
          ["Model",      task.model_name || @pastel.dim("—")],
          ["Tags",       task.tag_list.empty? ? @pastel.dim("—") : task.tag_list.join(", ")],
          ["Est. Hours", task.estimated_hours ? task.estimated_hours.to_s : @pastel.dim("—")],
          ["Created",    task.created_at&.strftime("%Y-%m-%d %H:%M") || @pastel.dim("—")],
          ["Updated",    task.updated_at&.strftime("%Y-%m-%d %H:%M") || @pastel.dim("—")]
        ]

        max_label = fields.map { |l, _| l.length }.max
        fields.each do |label, value|
          puts "  #{@pastel.dim(label.ljust(max_label))}  #{value}"
        end
        puts ""
      end

      def render_added(task)
        puts @pastel.green("  ✓ Task ##{task.id} created") + " — #{@pastel.bold(task.name)}"
      end

      def render_updated(task)
        puts @pastel.green("  ✓ Task ##{task.id} updated") + " — #{@pastel.bold(task.name)}"
      end

      def render_deleted(task)
        puts @pastel.red("  ✗ Task ##{task.id} deleted") + " — #{@pastel.bold(task.name)}"
      end

      def render_stats(tasks)
        puts ""
        puts @pastel.bold("  Task Statistics")
        puts @pastel.dim("  #{"─" * 60}")

        total = tasks.length
        by_status = tasks.group_by(&:status).transform_values(&:length)
        by_priority = tasks.group_by(&:priority).transform_values(&:length)
        overdue = tasks.count(&:overdue?)
        projects = tasks.map(&:project).compact.uniq.length

        puts "  #{@pastel.dim("Total tasks:".ljust(20))} #{total}"
        puts "  #{@pastel.dim("Overdue:".ljust(20))} #{overdue.positive? ? @pastel.red(overdue.to_s) : @pastel.green("0")}"
        puts "  #{@pastel.dim("Projects:".ljust(20))} #{projects}"
        puts ""

        puts "  #{@pastel.dim("By Status:")}"
        Tasku::Task::VALID_STATUSES.each do |s|
          count = by_status[s] || 0
          next if count.zero?

          puts "    #{status_tag(s)} #{@pastel.send(STATUS_STYLES.dig(s, :color) || :dim, count.to_s.rjust(3))}"
        end

        puts ""
        puts "  #{@pastel.dim("By Priority:")}"
        Tasku::Task::VALID_PRIORITIES.each do |p|
          count = by_priority[p] || 0
          next if count.zero?

          puts "    #{priority_tag(p)} #{@pastel.send(PRIORITY_STYLES.dig(p, :color) || :dim, count.to_s.rjust(3))}"
        end
        puts ""
      end

      private

      def build_columns(task)
        id_val = task.code && !task.code.empty? ? "#{task.code}-#{task.id}" : task.id.to_s
        id_str = @pastel.dim(id_val)
        name_str = @pastel.bold(task.name)
        proj_str = task.project || @pastel.dim("—")
        prio_str = priority_tag(task.priority)
        stat_str = status_tag(task.status)
        due_str = due_cell(task)
        [id_str, name_str, proj_str, prio_str, stat_str, due_str]
      end

      def compute_widths(rows)
        raw = rows.map { |cols| cols.map { |c| strip_ansi(c.to_s).length } }
        maxes = raw.transpose.map(&:max)
        sep_total = COL_SEP.length * (maxes.length - 1)
        fixed_cols = maxes[0] + maxes[2] + maxes[3] + maxes[4] + maxes[5]
        available_name = @term_width - fixed_cols - sep_total - 4
        min_name = 20

        if maxes[1] > available_name || maxes[1] < min_name
          name_width = [available_name, min_name].max
          rows.each_with_index do |cols, _ri|
            raw_str = strip_ansi(cols[1].to_s)
            if raw_str.length > name_width
              cols[1] = "#{raw_str[0..name_width - 2]}#{@pastel.dim("…")}"
            end
          end
          maxes[1] = name_width
        end

        maxes
      end

      def strip_ansi(str)
        str.gsub(/\e\[[0-9;]*m/, "")
      end

      def terminal_width
        IO.console&.winsize&.[](1) || 80
      rescue
        80
      end

      def priority_tag(priority)
        style = PRIORITY_STYLES[priority] || PRIORITY_STYLES["none"]
        @pastel.send(style[:color], "#{style[:symbol]} #{priority.capitalize}")
      end

      def status_tag(status)
        style = STATUS_STYLES[status] || STATUS_STYLES["backlog"]
        label = status.tr("_", " ").capitalize
        @pastel.send(style[:color], "#{style[:symbol]} #{label}")
      end

      def due_cell(task)
        return @pastel.dim("—") unless task.due_day

        diff = (task.due_day - Date.today).to_i
        day = task.due_day.strftime("%b %d")
        if task.overdue?
          @pastel.red("#{day} (#{diff.abs}d ago)")
        elsif diff.zero?
          @pastel.yellow("#{day} (today)")
        elsif diff <= 7
          @pastel.yellow("#{day} (+#{diff}d)")
        else
          @pastel.green(day)
        end
      end
    end
  end
end
