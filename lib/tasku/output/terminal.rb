# frozen_string_literal: true

require "pastel"
require "io/console"

module Tasku
  module Output
    class Terminal
      PRIORITY_HEX = {
        "none"   => "#6B7280",
        "low"    => "#06B6D4",
        "medium" => "#EAB308",
        "high"   => "#EF4444",
        "urgent" => "#E879F9"
      }.freeze

      STATUS_HEX = {
        "backlog"     => "#6B7280",
        "todo"        => "#3B82F6",
        "in_progress" => "#EAB308",
        "done"        => "#22C55E",
        "cancelled"   => "#EF4444",
        "archived"    => "#6B7280"
      }.freeze

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

      COL_SEP = " │ "
      # Maximum visible width of a due_cell value:
      # "Mmm DD (NNNd ago)" = 17 chars.
      DUE_COL_MIN_WIDTH = 17

      def initialize
        @pastel = Pastel.new
        @term_width = terminal_width
      end

      def render_list(tasks, colour_map: {}, spacing: "compact", bar: {}, cols_cfg: {})
        if tasks.empty?
          puts @pastel.yellow("  No tasks found.")
          return
        end

        rows = tasks.map { |t| build_columns(t, colour_map, bar, cols_cfg) }
        col_widths = compute_widths(rows, cols_cfg)
        total = col_widths.sum + (COL_SEP.length * (col_widths.length - 1))

        puts ""
        puts @pastel.dim("  #{"─" * total}")
        rows.each do |cols|
          line = cols.each_with_index.map { |c, i| ansi_ljust(c.to_s, col_widths[i]) }.join(COL_SEP)
          puts "  #{line}"
          puts "" if spacing == "spacious"
        end
        puts @pastel.dim("  #{"─" * total}")
        puts @pastel.dim("  #{tasks.length} task(s) found")
      end

      def render_show(task, colour_map: {})
        puts ""
        puts @pastel.bold("  Task ##{task.id}")
        puts @pastel.dim("  #{"─" * 60}")

        fields = [
          ["Name",       @pastel.bold(task.name)],
          ["Description", task.description ? @pastel.dim(task.description) : @pastel.dim("—")],
          ["Project",    project_str(task.project, colour_map)],
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

      def render_stats(tasks, colour_map: {})
        puts ""
        puts @pastel.bold("  Task Statistics")
        puts @pastel.dim("  #{"─" * 60}")

        total = tasks.length
        by_status = tasks.group_by(&:status).transform_values(&:length)
        by_priority = tasks.group_by(&:priority).transform_values(&:length)
        by_project = tasks.group_by(&:project).transform_values(&:length)
        overdue = tasks.count(&:overdue?)
        project_count = tasks.map(&:project).compact.uniq.length

        puts "  #{@pastel.dim("Total tasks:".ljust(20))} #{total}"
        puts "  #{@pastel.dim("Overdue:".ljust(20))} #{overdue.positive? ? @pastel.red(overdue.to_s) : @pastel.green("0")}"
        puts "  #{@pastel.dim("Projects:".ljust(20))} #{project_count}"
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
        puts "  #{@pastel.dim("By Project:")}"
        by_project.sort_by { |_, count| -count }.each do |name, count|
          label = name || @pastel.dim("(none)")
          coloured_name = name && colour_map[name] ? hex_colour_str(name, colour_map[name]) : label
          padding = " " * [20 - strip_ansi(coloured_name).length, 0].max
          puts "    #{coloured_name}#{padding} #{@pastel.dim(count.to_s.rjust(3))}"
        end
        puts ""
      end

      # Returns an array of pre-formatted row strings for MadoList.
      # Accounts for the "  [>] " prefix (6 extra chars) when computing widths.
      # Optional columns (project → priority → status, never due) are dropped
      # until ≥15 chars are available for task names.  Names are only truncated
      # if they still overflow after all optional columns have been tried.
      def build_mado_rows(tasks, colour_map = {}, bar = {}, cols_cfg = {})
        return { rows: [], row_width: 0 } if tasks.empty?

        orig_width  = @term_width
        @term_width = [orig_width - 6, 40].max

        cfg = cols_cfg.dup

        # Drop optional columns (project → category → priority → status) until names have room.
        %i[project category priority status].each do |drop_col|
          probe = tasks.map { |t| build_columns(t, colour_map, bar, cfg) }
          ws    = mado_max_col_widths(probe, cfg)
          break if mado_name_available(ws) >= 15
          next if cfg["col_#{drop_col}"] == "off"
          cfg["col_#{drop_col}"] = "off"
        end

        col_rows   = tasks.map { |t| build_columns(t, colour_map, bar, cfg) }
        col_widths = mado_max_col_widths(col_rows, cfg)
        col_widths = mado_apply_truncation(col_rows, col_widths)

        dim_sep = @pastel.dim(COL_SEP)
        result  = col_rows.map do |cols|
          cols.each_with_index.map { |c, i| ansi_ljust(c.to_s, col_widths[i]) }.join(dim_sep)
        end

        # Build header row aligned to col_widths.
        labels = ["ID", "Name"]
        %i[project category priority status due].each do |col|
          next if cfg["col_#{col}"] == "off"
          labels << { project: "Project", category: "Category",
                      priority: "Priority", status: "Status", due: "Due" }[col]
        end
        header = labels.each_with_index
                       .map { |lbl, i| ansi_ljust(@pastel.dim(lbl), col_widths[i]) }
                       .join(dim_sep)

        row_width = col_widths.sum + COL_SEP.length * (col_widths.length - 1)
        @term_width = orig_width
        { rows: result, row_width: row_width, header: header }
      end

      private

      def build_columns(task, colour_map = {}, bar = {}, cols_cfg = {})
        id_val = task.code && !task.code.empty? ? "#{task.code}-#{task.id}" : task.id.to_s

        segments = []
        if bar["bar_project"] != "off"
          proj_colour = task.project && colour_map[task.project]
          segments << (proj_colour ? hex_colour_str("█", proj_colour) : @pastel.dim("█"))
        end
        if bar["bar_priority"] != "off"
          segments << hex_colour_str("█", PRIORITY_HEX[task.priority] || PRIORITY_HEX["none"])
        end
        if bar["bar_status"] != "off"
          segments << hex_colour_str("█", STATUS_HEX[task.status] || STATUS_HEX["backlog"])
        end

        id_str = if segments.any?
                   "#{segments.join} #{@pastel.dim(id_val)}"
                 else
                   @pastel.dim(id_val)
                 end

        # ID (col 0) and Name (col 1) are always present.
        result = [id_str, @pastel.bold(task.name)]
        result << project_str(task.project, colour_map) unless cols_cfg["col_project"]  == "off"
        result << category_str(task.category)           unless cols_cfg["col_category"] == "off"
        result << priority_tag(task.priority)           unless cols_cfg["col_priority"] == "off"
        result << status_tag(task.status)               unless cols_cfg["col_status"]   == "off"
        result << due_cell(task)                        unless cols_cfg["col_due"]       == "off"
        result
      end

      def compute_widths(rows, cols_cfg = {})
        raw = rows.map { |cols| cols.map { |c| strip_ansi(c.to_s).length } }
        maxes = raw.transpose.map(&:max)

        # Track which array index each optional column landed at (after id=0, name=1).
        col_idx = {}
        i = 2
        %i[project category priority status due].each do |col|
          unless cols_cfg["col_#{col}"] == "off"
            col_idx[col] = i
            i += 1
          end
        end

        # Apply user-configured minimum widths for optional fixed columns.
        {
          priority: [cols_cfg["col_priority_min"].to_i, 4].max,
          status:   [cols_cfg["col_status_min"].to_i,   4].max,
          due:      [[cols_cfg["col_due_min"].to_i, DUE_COL_MIN_WIDTH].max]
        }.each do |col, mins|
          if (idx = col_idx[col])
            maxes[idx] = ([maxes[idx]] + Array(mins)).max
          end
        end

        sep_total = COL_SEP.length * (maxes.length - 1)
        # Fixed cols = everything except the name column (always at index 1).
        fixed_cols = maxes.each_with_index.sum { |m, i| i == 1 ? 0 : m }
        available_name = @term_width - fixed_cols - sep_total - 6

        # Truncate names that would overflow; use count-based slice to avoid
        # Ruby's negative-index wrapping when name_width is 0 or 1.
        name_width = [available_name, 0].max
        if maxes[1] > name_width
          rows.each do |cols|
            raw_str = strip_ansi(cols[1].to_s)
            if raw_str.length > name_width
              keep = [name_width - 1, 0].max
              cols[1] = keep > 0 ? "#{raw_str[0, keep]}#{@pastel.dim("…")}" : ""
            end
          end
        else
          name_width = maxes[1]
        end
        maxes[1] = name_width

        maxes
      end

      # Returns per-column max widths, applying configured minimums for
      # priority (≥4), status (≥4), and due (≥DUE_COL_MIN_WIDTH).
      # @term_width must already be reduced by 6 (the MadoList prefix).
      def mado_max_col_widths(rows, cols_cfg = {})
        raw   = rows.map { |cols| cols.map { |c| strip_ansi(c.to_s).length } }
        maxes = raw.transpose.map(&:max)

        col_idx = {}
        i = 2
        %i[project category priority status due].each do |col|
          next if cols_cfg["col_#{col}"] == "off"
          col_idx[col] = i
          i += 1
        end

        { priority: [cols_cfg["col_priority_min"].to_i, 4].max,
          status:   [cols_cfg["col_status_min"].to_i,   4].max,
          due:      [cols_cfg["col_due_min"].to_i, DUE_COL_MIN_WIDTH].max
        }.each do |col, min|
          maxes[col_idx[col]] = [maxes[col_idx[col]], min].max if col_idx[col]
        end

        maxes
      end

      # How many chars are available for the name column given a widths array.
      def mado_name_available(maxes)
        sep_total  = COL_SEP.length * (maxes.length - 1)
        fixed_cols = maxes.each_with_index.sum { |m, i| i == 1 ? 0 : m }
        @term_width - fixed_cols - sep_total
      end

      # Truncate name cells in-place if they exceed available space.
      # Always expands the name column to fill available space so the table
      # spans the full terminal width (short names are padded by ansi_ljust).
      # Returns the (possibly updated) widths array.
      def mado_apply_truncation(rows, maxes)
        avail  = mado_name_available(maxes)
        name_w = [avail, 0].max
        if maxes[1] > name_w
          rows.each do |cols|
            s = strip_ansi(cols[1].to_s)
            if s.length > name_w
              keep    = [name_w - 1, 0].max
              cols[1] = keep > 0 ? "#{s[0, keep]}#{@pastel.dim("…")}" : ""
            end
          end
        end
        # Always set name column to full available width so the table fills
        # the terminal — short names will be space-padded by ansi_ljust.
        maxes[1] = name_w
        maxes
      end

      def strip_ansi(str)
        str.gsub(/\e\[[0-9;]*m/, "")
      end

      # Pad an ANSI-coloured string to `width` visible characters.
      # String#ljust counts bytes (including escape codes), so we compute
      # the visible length ourselves and append plain spaces for the deficit.
      def ansi_ljust(str, width)
        deficit = width - strip_ansi(str).length
        deficit > 0 ? str + (" " * deficit) : str
      end

      def terminal_width
        # Mado writes the exact PTY column count to this file before running
        # tasku list, bypassing unreliable ioctl/winsize methods inside the PTY.
        cols_file = ENV["TASKU_COLS_FILE"] || "/tmp/tasku_mado_cols"
        cols = File.read(cols_file).strip.to_i rescue 0
        return cols if cols > 0

        `stty size 2>/dev/null`.split.last.to_i.tap { |w| return w if w > 0 }
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

      def hex_colour_str(text, hex)
        r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) }
        "\e[38;2;#{r};#{g};#{b}m#{text}\e[0m"
      end

      def category_str(category)
        category && !category.empty? ? @pastel.cyan(category) : @pastel.dim("—")
      end

      def project_str(project, colour_map)
        return @pastel.dim("—") unless project

        colour = colour_map[project]
        return project unless colour

        r, g, b = colour.delete("#").scan(/../).map { |c| c.to_i(16) }
        "\e[38;2;#{r};#{g};#{b}m#{project}\e[0m"
      end

      def due_cell(task)
        return @pastel.dim("—") unless task.due_day

        diff = (task.due_day - Date.today).to_i
        day = task.due_day.strftime("%b %d")
        if task.overdue?
          @pastel.red("#{day} (#{diff.abs}d ago)")
        elsif diff < 0
          # Past due but task is done/cancelled — show dimly, no alarm
          @pastel.dim("#{day} (#{diff.abs}d ago)")
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
