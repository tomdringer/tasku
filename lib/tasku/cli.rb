# frozen_string_literal: true

module Tasku
  module CLI
    LOGO = <<~LOGO
       _______        _          
      |__   __|      | |         
         | | __ _ ___| | ___   _ 
         | |/ _` / __| |/ / | | |
         | | (_| \\__ \\   <| |_| |
         |_|\\__,_|___/_|\\_\\\\__,_|
    LOGO

    TAGLINE = "\u30BF\u30B9\u30AF\u30EA\u30B9\u30C8 \u2014 terminal task manager"

    class App < Thor
      def self.start(args = ARGV, **opts)
        sql_index = args.index("--sql")
        if sql_index
          args.delete_at(sql_index)
          query = args[sql_index]
          if query.nil? || query.empty?
            puts pastel.red("  No query provided after --sql.")
            return
          end
          args.delete_at(sql_index)
          new.invoke(:sql, [query])
          return
        end

        super
      end

      class_option :db, type: :string, desc: "Path to SQLite database (default: ~/.tasku/tasks.db)", hide: true

      desc "sql QUERY", "Run a raw SQL query against the database"
      def sql(query)
        if query.strip.upcase.match?(/\A(SELECT|PRAGMA|EXPLAIN)/)
          dataset = Tasku::Database.db.fetch(query)
          rows = dataset.all

          if rows.empty?
            puts pastel.yellow("  Query returned no results.")
            return
          end

          raw_keys = rows.first.keys
          has_code = raw_keys.include?(:code)
          columns = raw_keys.reject { |c| %i[model_name created_at updated_at code].include?(c.to_sym) }

          display_cols = columns.map { |c| c == :id ? "CODE-ID" : c.to_s }
          code_id_keys = columns.include?(:id) && has_code

          col_widths = columns.each_with_index.map do |c, i|
            data_vals = rows.map do |r|
              v = if c == :id && code_id_keys && r[:code] && !r[:code].to_s.empty?
                    "#{r[:code]}-#{r[:id]}"
                  else
                    r[c].to_s
                  end
              v.length
            end
            [display_cols[i].length, data_vals.max || 0].max
          end

          puts ""
          header = display_cols.each_with_index.map { |c, i| pastel.bold(c.ljust(col_widths[i])) }
          puts "  #{header.join('  ')}"
          puts "  #{display_cols.each_with_index.map { |_c, i| pastel.dim("\u2500" * col_widths[i]) }.join('  ')}"

          rows.each do |row|
            cells = columns.each_with_index.map do |col, i|
              val = if col == :id && code_id_keys && row[:code] && !row[:code].to_s.empty?
                      "#{row[:code]}-#{row[:id]}"
                    else
                      row[col].to_s
                    end
              colour_cell(col, val.ljust(col_widths[i]), row)
            end
            puts "  #{cells.join('  ')}"
            puts "  #{display_cols.each_with_index.map { |_c, i| pastel.dim("\u2500" * col_widths[i]) }.join('  ')}"
          end
          puts ""
        else
          affected = Tasku::Database.db.run(query)
          puts pastel.green("  Query executed successfully.")
        end
      rescue Sequel::DatabaseError => e
        abort pastel.red("SQL error: #{e.message}")
      end

      desc "add", "Create a new task"
      option :name,        type: :string,  desc: "Task name", required: false
      option :description, type: :string,  desc: "Task description"
      option :project,     type: :string,  desc: "Project name"
      option :category,    type: :string,  desc: "Category"
      option :start,       type: :string,  desc: "Start date (YYYY-MM-DD)"
      option :due,         type: :string,  desc: "Due date (YYYY-MM-DD)"
      option :model,       type: :string,  desc: "Model identifier"
      option :priority,    type: :string,  desc: "Priority: none, low, medium, high, urgent"
      option :status,      type: :string,  desc: "Status: backlog, todo, in_progress, done, cancelled, archived"
      option :tags,        type: :string,  desc: "Comma-separated tags"
      option :hours,       type: :numeric, desc: "Estimated hours"
      option :code,        type: :string,  desc: "Code"
      option :interactive, type: :boolean, aliases: "-i", desc: "Interactive mode", default: false
      def add
        attrs = if options[:interactive] || options.values_at(:name, :description, :project, :category).all?(&:nil?)
                  interactive_add
                else
                  option_add
                end

        task = Task.create(attrs)
        terminal.render_added(task)
      rescue Sequel::ValidationFailed => e
        abort pastel.red("Validation error: #{e.message}")
      end

      desc "list", "List all tasks"
      option :status,   type: :string,  desc: "Filter by status"
      option :priority, type: :string,  desc: "Filter by priority"
      option :project,  type: :string,  desc: "Filter by project"
      option :category, type: :string,  desc: "Filter by category"
      option :tags,     type: :string,  desc: "Filter by tag (comma-separated)"
      option :overdue,  type: :boolean, desc: "Show only overdue tasks"
      option :sort,     type: :string,  desc: "Sort by: name, priority, due, status, created"
      option :order,    type: :string,  desc: "Order: asc, desc", default: "asc"
      def list
        dataset = Task.dataset

        dataset = dataset.where(status: options[:status]) if options[:status]
        dataset = dataset.where(priority: options[:priority]) if options[:priority]
        dataset = dataset.where(project: options[:project]) if options[:project]
        dataset = dataset.where(category: options[:category]) if options[:category]

        if options[:tags]
          tag_filter = options[:tags].split(",").map(&:strip)
          tag_filter.each do |t|
            dataset = dataset.where(Sequel.ilike(:tags, "%#{t}%"))
          end
        end

        if options[:overdue]
          today = Date.today
          dataset = dataset.where { due_day < today }.exclude(status: %w[done cancelled])
        end

        sort_col = case options[:sort]
                   when "name"     then :name
                   when "priority" then Sequel.case(Task::VALID_PRIORITIES.each_with_index.to_h, 999, :priority)
                   when "due"      then :due_day
                   when "status"   then Sequel.case(Task::VALID_STATUSES.each_with_index.to_h, 999, :status)
                   else :created_at
                   end

        order = options[:order] == "desc" ? Sequel.desc(sort_col) : Sequel.asc(sort_col)
        dataset = dataset.order(order)

        tasks = dataset.all
        terminal.render_list(tasks)
      end

      desc "show ID", "Show task details"
      def show(id)
        task = find_task(id)
        terminal.render_show(task)
      end

      desc "edit ID", "Edit a task"
      option :name,        type: :string,  desc: "Task name"
      option :description, type: :string,  desc: "Task description"
      option :project,     type: :string,  desc: "Project name"
      option :category,    type: :string,  desc: "Category"
      option :start,       type: :string,  desc: "Start date (YYYY-MM-DD)"
      option :due,         type: :string,  desc: "Due date (YYYY-MM-DD)"
      option :model,       type: :string,  desc: "Model identifier"
      option :priority,    type: :string,  desc: "Priority: none, low, medium, high, urgent"
      option :status,      type: :string,  desc: "Status: backlog, todo, in_progress, done, cancelled, archived"
      option :tags,        type: :string,  desc: "Comma-separated tags"
      option :hours,       type: :numeric, desc: "Estimated hours"
      option :code,        type: :string,  desc: "Code"
      option :clear,       type: :string,  desc: "Clear a field: description, start, due, model, tags, hours, code"
      def edit(id)
        task = find_task(id)

        attrs = option_edit
        if attrs.empty? && !options[:clear]
          puts pastel.yellow("No changes specified. Use --help to see available options.")
          return
        end

        if options[:clear]
          clear_fields = options[:clear].split(",").map(&:strip)
          clear_map = {
            "description" => :description,
            "start"       => :start_day,
            "due"         => :due_day,
            "model"       => :model_name,
            "tags"        => :tags,
            "hours"       => :estimated_hours,
            "code"        => :code
          }
          clear_fields.each do |f|
            col = clear_map[f]
            if col
              attrs[col] = nil
            else
              puts pastel.yellow("Unknown field to clear: #{f}")
            end
          end
        end

        task.update(attrs)
        terminal.render_updated(task)
      rescue Sequel::ValidationFailed => e
        abort pastel.red("Validation error: #{e.message}")
      end

      desc "done ID", "Mark a task as done"
      def done(id)
        task = find_task(id)
        task.update(status: "done")
        terminal.render_updated(task)
      end

      desc "delete ID", "Delete a task"
      option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation"
      def delete(id)
        task = find_task(id)

        unless options[:force]
          prompt = TTY::Prompt.new
          confirmed = prompt.yes?(pastel.red("Delete task ##{id} (#{task.name})?"))
          return unless confirmed
        end

        task.destroy
        terminal.render_deleted(task)
      end

      desc "stats", "Show task statistics"
      def stats
        tasks = Task.dataset.all
        terminal.render_stats(tasks) if tasks
      end

      desc "projects", "List all projects"
      def projects
        projects = Task.dataset.select(:project).where(Sequel.~(project: nil)).distinct.order(:project).map(:project)
        if projects.empty?
          puts pastel.yellow("  No projects found.")
          return
        end

        puts ""
        projects.each do |p|
          count = Task.where(project: p).count
          puts "  #{pastel.bold(p)} #{pastel.dim("(#{count} task(s))")}"
        end
        puts ""
      end

      desc "categories", "List all categories"
      def categories
        categories = Task.dataset.select(:category).where(Sequel.~(category: nil)).distinct.order(:category).map(:category)
        if categories.empty?
          puts pastel.yellow("  No categories found.")
          return
        end

        puts ""
        categories.each do |c|
          count = Task.where(category: c).count
          puts "  #{pastel.bold(c)} #{pastel.dim("(#{count} task(s))")}"
        end
        puts ""
      end

      desc "version", "Show version"
      def version
        puts "tasku #{Tasku::VERSION}"
      end

      no_commands do
        def terminal
          @terminal ||= Output::Terminal.new
        end

        def pastel
          @pastel ||= Pastel.new
        end

        def find_task(id)
          task = Task[id.to_i]
          abort pastel.red("Task ##{id} not found.") unless task
          task
        end

        def parse_date(str)
          return if str.nil? || str.strip.empty?

          Date.parse(str)
        rescue Date::Error
          abort pastel.red("Invalid date: '#{str}'. Use YYYY-MM-DD format.")
        end

        def interactive_add
          prompt = TTY::Prompt.new

          name = prompt.ask("Task name:", required: true) do |q|
            q.modify :strip
          end

          description = prompt.ask("Description:", default: "")
          description = nil if description&.empty?

          project = prompt.ask("Project:", default: "")
          project = nil if project&.empty?

          category = prompt.ask("Category:", default: "")
          category = nil if category&.empty?

          priority = prompt.select("Priority?", %w[none low medium high urgent], default: 1)
          status = prompt.select("Status?", %w[backlog todo in_progress], default: 2)

          start_day = prompt.ask("Start date (YYYY-MM-DD, optional):", default: "")
          start_day = nil if start_day&.empty?

          due_day = prompt.ask("Due date (YYYY-MM-DD, optional):", default: "")
          due_day = nil if due_day&.empty?

          model_name = prompt.ask("Model:", default: "")
          model_name = nil if model_name&.empty?

          code = prompt.ask("Code:", default: "")
          code = nil if code&.empty?

          tags = prompt.ask("Tags (comma-separated):", default: "")
          tags = nil if tags&.empty?

          hours = prompt.ask("Estimated hours:", default: "") do |q|
            q.convert(:float, "")
          end
          hours = nil if hours.is_a?(String) && hours.empty?

          {
            name: name,
            description: (description unless description&.empty?),
            project: (project unless project&.empty?),
            category: (category unless category&.empty?),
            start_day: parse_date(start_day),
            due_day: parse_date(due_day),
            model_name: (model_name unless model_name&.empty?),
            code: (code unless code&.empty?),
            priority: priority,
            status: status,
            tags: (tags unless tags&.empty?),
            estimated_hours: hours
          }.compact
        end

        def option_add
          validate_priority!(options[:priority]) if options[:priority]
          validate_status!(options[:status]) if options[:status]

          {
            name: (options[:name] or abort(pastel.red("Name is required. Use --name or -i for interactive mode."))),
            description: options[:description],
            project: options[:project],
            category: options[:category],
            start_day: parse_date(options[:start]),
            due_day: parse_date(options[:due]),
            model_name: options[:model],
            code: options[:code],
            priority: options[:priority] || "none",
            status: options[:status] || "todo",
            tags: options[:tags],
            estimated_hours: options[:hours]
          }.compact
        end

        def option_edit
          validate_priority!(options[:priority]) if options[:priority]
          validate_status!(options[:status]) if options[:status]

          {
            name: options[:name],
            description: options[:description],
            project: options[:project],
            category: options[:category],
            start_day: parse_date(options[:start]),
            due_day: parse_date(options[:due]),
            model_name: options[:model],
            code: options[:code],
            priority: options[:priority],
            status: options[:status],
            tags: options[:tags],
            estimated_hours: options[:hours]
          }.compact
        end

        def validate_priority!(value)
          return if Task::VALID_PRIORITIES.include?(value)

          abort pastel.red("Invalid priority '#{value}'. Valid: #{Task::VALID_PRIORITIES.join(', ')}")
        end

        def validate_status!(value)
          return if Task::VALID_STATUSES.include?(value)

          abort pastel.red("Invalid status '#{value}'. Valid: #{Task::VALID_STATUSES.join(', ')}")
        end

        PRIORITY_COLOURS = {
          "none"   => :dim,
          "low"    => :cyan,
          "medium" => :yellow,
          "high"   => :red,
          "urgent" => :bright_magenta
        }.freeze

        STATUS_COLOURS = {
          "backlog"     => :dim,
          "todo"        => :blue,
          "in_progress" => :yellow,
          "done"        => :green,
          "cancelled"   => :red,
          "archived"    => :dim
        }.freeze

        def colour_cell(col, padded_val, row)
          case col.to_s
          when "priority"
            colour = PRIORITY_COLOURS[row[col].to_s] || :dim
            pastel.send(colour, padded_val)
          when "status"
            colour = STATUS_COLOURS[row[col].to_s] || :dim
            pastel.send(colour, padded_val)
          else
            padded_val
          end
        end
      end
    end
  end
end
