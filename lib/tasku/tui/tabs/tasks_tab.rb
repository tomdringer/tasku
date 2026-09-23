# frozen_string_literal: true

module Tasku
  module TUI
    module Tabs
      class TasksTab < Tab
        PRIORITY_MARKS = {
          "none"   => [:dim, " "],
          "low"    => [:cyan, "v"],
          "medium" => [:yellow, "o"],
          "high"   => [:red, "^"],
          "urgent" => [:bright_magenta, "!"]
        }.freeze

        STATUS_MARKS = {
          "backlog"     => [:dim, "o"],
          "todo"        => [:blue, "o"],
          "in_progress" => [:yellow, "O"],
          "done"        => [:green, "x"],
          "cancelled"   => [:red, "X"],
          "archived"    => [:dim, "-"]
        }.freeze

        def initialize
          super("Tasks")
        end

        def render(pastel, width, height)
          tasks = Task.dataset.order(Sequel.desc(:created_at)).limit(height - 2).all

          if tasks.empty?
            return [pastel.dim("No tasks yet. Use 'tasku add' to create one.")]
          end

          col_id = 10
          col_name = 28
          col_prio = 10
          col_stat = 14

          lines = []
          header = pastel.dim(
            "  #{'ID'.ljust(col_id)} #{'Name'.ljust(col_name)} #{'Priority'.ljust(col_prio)} #{'Status'.ljust(col_stat)}"
          )
          lines << header

          tasks.each do |t|
            id_str = t.code ? "#{t.code}-#{t.id}" : t.id.to_s
            id_cell = pastel.dim(id_str.ljust(col_id))

            name = t.name.to_s
            disp = name.length > col_name ? "#{name[0..col_name - 2]}." : name.ljust(col_name)

            prio_mark = PRIORITY_MARKS[t.priority] || PRIORITY_MARKS["none"]
            prio_cell = pastel.send(prio_mark[0], "#{prio_mark[1]} #{t.priority.capitalize}".ljust(col_prio))

            stat_mark = STATUS_MARKS[t.status] || STATUS_MARKS["backlog"]
            stat_cell = pastel.send(stat_mark[0], "#{stat_mark[1]} #{t.status.tr('_', ' ').capitalize}".ljust(col_stat))

            lines << "  #{id_cell} #{disp} #{prio_cell} #{stat_cell}"
          end

          lines
        end
      end
    end
  end
end
