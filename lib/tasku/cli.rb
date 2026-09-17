# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"

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

    class ConfigApp < Thor
      desc "list", "Show all preferences and their current values"
      def list
        pastel = Pastel.new
        puts ""
        Tasku::Config::VALID_KEYS.each do |key, meta|
          current = Tasku::Config.get(key)
          if meta[:range]
            options_str = pastel.bold(pastel.green(current)) + pastel.dim("  (#{meta[:range].min}–#{meta[:range].max})")
          else
            options_str = meta[:values].map { |v| v == current ? pastel.bold(pastel.green(v)) : pastel.dim(v) }.join(", ")
          end
          puts "  #{pastel.bold(key.ljust(20))} #{options_str}  #{pastel.dim("— #{meta[:description]}")}"
        end
        puts ""
      end

      desc "set KEY VALUE", "Set a preference value"
      def set(key, value)
        pastel = Pastel.new
        meta = Tasku::Config::VALID_KEYS[key]
        abort pastel.red("Unknown preference '#{key}'. Run `tasku config list` to see available keys.") unless meta
        begin
          Tasku::Config.set(key, value)
        rescue ArgumentError => e
          abort pastel.red("  #{e.message}")
        end
        puts pastel.green("  ✓ #{key} set to '#{value}'.")
      end

      desc "get KEY", "Get the current value of a preference"
      def get(key)
        pastel = Pastel.new
        meta = Tasku::Config::VALID_KEYS[key]
        abort pastel.red("Unknown preference '#{key}'. Run `tasku config list` to see available keys.") unless meta
        puts "  #{key}: #{pastel.bold(Tasku::Config.get(key))}"
      end

      desc "open", "Open the config file in $EDITOR"
      def open
        path = Tasku::Config::CONFIG_PATH
        FileUtils.mkdir_p(File.dirname(path))
        # Seed file with all defaults so every key is visible for editing.
        current = Tasku::Config.all
        seeded = Tasku::Config::VALID_KEYS.transform_values { |meta| meta[:default] }.merge(current)
        File.write(path, JSON.pretty_generate(seeded))
        editor = ENV["EDITOR"] || ENV["VISUAL"] || "vi"
        exec(editor, path)
      end
    end

    class CloudApp < Thor
      desc "login TOKEN", "Authenticate with Tasku Cloud using an API token"
      option :url, type: :string, desc: "Tasku Cloud URL (default: #{Tasku::Config::CLOUD_URL_DEFAULT})"
      def login(token)
        pastel = Pastel.new
        url = options[:url] || Tasku::Config.cloud_url

        puts pastel.dim("  Verifying token with #{url}...")

        begin
          uri = URI.join(url, "/api/v1/sync")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 10
          http.read_timeout = 10

          req = Net::HTTP::Post.new(uri.path, {
            "Content-Type"  => "application/json",
            "Authorization" => "Bearer #{token}"
          })
          req.body = JSON.generate({ tasks: [], last_synced_at: nil })

          res = http.request(req)
        rescue Errno::ECONNREFUSED, Errno::ENOENT, SocketError, Net::OpenTimeout => e
          abort pastel.red("  Could not connect to #{url}: #{e.message}")
        end

        if res.code == "200"
          Tasku::Config.cloud_token = token
          Tasku::Config.cloud_url = url if options[:url]
          puts ""
          puts pastel.green("  ✓ Logged in to Tasku Cloud.")
          puts pastel.dim("  Token saved to ~/.tasku/config.json")
          puts pastel.dim("  Run `tasku cloud sync` to sync your tasks.")
          puts ""
        elsif res.code == "401"
          abort pastel.red("  Invalid token. Check it and try again.")
        else
          abort pastel.red("  Unexpected response from server (#{res.code}).")
        end
      end

      desc "status", "Show Tasku Cloud connection status"
      def status
        pastel = Pastel.new
        puts ""
        if Tasku::Config.cloud_configured?
          puts "  #{pastel.green("●")} Connected to #{pastel.bold(Tasku::Config.cloud_url)}"
          last = Tasku::Config.last_synced_at
          puts "  Last synced: #{last ? pastel.bold(last.localtime.strftime("%-d %b %Y at %H:%M")) : pastel.dim("never")}"
        else
          puts "  #{pastel.dim("○")} Not connected."
          puts "  #{pastel.dim("Run `tasku cloud login <token>` to connect.")}"
        end
        puts ""
      end

      desc "logout", "Remove saved Tasku Cloud credentials"
      def logout
        pastel = Pastel.new
        Tasku::Config.cloud_token = nil
        Tasku::Config.last_synced_at = nil
        puts pastel.green("  ✓ Logged out of Tasku Cloud.")
      end

      desc "sync", "Two-way sync tasks with Tasku Cloud"
      def sync
        pastel = Pastel.new

        unless Tasku::Config.cloud_configured?
          abort pastel.red("  Not connected. Run `tasku cloud login <token>` first.")
        end

        url            = Tasku::Config.cloud_url
        token          = Tasku::Config.cloud_token
        last_synced_at = Tasku::Config.last_synced_at

        puts pastel.dim("  Syncing with #{url}...")

        # Serialise every local task for upload
        local_tasks = Tasku::Task.all.map do |t|
          {
            uuid:            t.uuid,
            name:            t.name,
            description:     t.description,
            project:         t.project,
            category:        t.category,
            start_day:       t.start_day&.iso8601,
            due_day:         t.due_day&.iso8601,
            code:            t.code,
            priority:        t.priority,
            status:          t.status,
            tags:            t.tags,
            estimated_hours: t.estimated_hours,
            updated_at:      t.updated_at&.utc&.iso8601,
            created_at:      t.created_at&.utc&.iso8601
          }
        end

        begin
          uri  = URI.join(url, "/api/v1/sync")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl    = uri.scheme == "https"
          http.open_timeout = 15
          http.read_timeout = 30

          req = Net::HTTP::Post.new(uri.path, {
            "Content-Type"  => "application/json",
            "Authorization" => "Bearer #{token}"
          })
          local_projects = Tasku::Database.db[:projects].all.map do |p|
            { name: p[:name], colour: p[:colour] }
          end

          req.body = JSON.generate({ tasks: local_tasks, projects: local_projects, last_synced_at: last_synced_at&.iso8601 })

          res = http.request(req)
        rescue Errno::ECONNREFUSED, Errno::ENOENT, SocketError, Net::OpenTimeout => e
          abort pastel.red("  Could not connect to #{url}: #{e.message}")
        end

        if res.code == "401"
          abort pastel.red("  Invalid token — run `tasku cloud login <token>` to reauthenticate.")
        elsif res.code != "200"
          abort pastel.red("  Sync failed (HTTP #{res.code}).")
        end

        body         = JSON.parse(res.body)
        server_tasks = body["tasks"] || []
        synced_at    = body["synced_at"]

        created = updated = conflicts = 0

        server_tasks.each do |st|
          next unless st["uuid"]

          # Conflict tasks live server-side; the user resolves them on the web.
          if st["conflict"]
            conflicts += 1
            next
          end

          local = Tasku::Task.first(uuid: st["uuid"])

          server_updated = st["updated_at"] ? Time.parse(st["updated_at"]).utc : nil

          if local.nil?
            # New task from cloud — write directly to bypass timestamps plugin
            # so updated_at matches the server's value exactly.
            Tasku::Database.db[:tasks].insert(
              uuid:            st["uuid"],
              name:            st["name"],
              description:     st["description"],
              project:         st["project"],
              category:        st["category"],
              start_day:       st["start_day"] ? Date.parse(st["start_day"]) : nil,
              due_day:         st["due_day"]   ? Date.parse(st["due_day"])   : nil,
              code:            st["code"],
              priority:        st["priority"] || "none",
              status:          st["status"]   || "todo",
              tags:            st["tags"],
              estimated_hours: st["estimated_hours"],
              created_at:      st["created_at"] ? Time.parse(st["created_at"]).utc : Time.now.utc,
              updated_at:      server_updated || Time.now.utc
            )
            created += 1
          else
            local_updated = local.updated_at ? local.updated_at.utc : nil

            if server_updated && local_updated && server_updated > local_updated
              # Write via dataset to preserve server's updated_at exactly,
              # preventing the local timestamp from drifting forward and
              # triggering another upload next sync.
              Tasku::Database.db[:tasks].where(id: local.id).update(
                name:            st["name"],
                description:     st["description"],
                project:         st["project"],
                category:        st["category"],
                start_day:       st["start_day"] ? Date.parse(st["start_day"]) : nil,
                due_day:         st["due_day"]   ? Date.parse(st["due_day"])   : nil,
                code:            st["code"],
                priority:        st["priority"] || "none",
                status:          st["status"]   || "todo",
                tags:            st["tags"],
                estimated_hours: st["estimated_hours"],
                updated_at:      server_updated
              )
              updated += 1
            end
          end
        end

        Tasku::Config.last_synced_at = synced_at ? Time.parse(synced_at).utc : Time.now.utc

        puts ""
        puts "  #{pastel.green("✓")} Sync complete."
        puts "  #{pastel.bold(local_tasks.count.to_s)} #{local_tasks.count == 1 ? "task" : "tasks"} pushed to cloud."
        puts "  #{pastel.bold(created.to_s)} #{created == 1 ? "task" : "tasks"} pulled from cloud."  if created > 0
        puts "  #{pastel.bold(updated.to_s)} #{updated == 1 ? "task" : "tasks"} updated from cloud." if updated > 0
        if conflicts > 0
          puts "  #{pastel.yellow("⚠")}  #{conflicts} #{conflicts == 1 ? "conflict" : "conflicts"} — visit #{pastel.bold(url)} to resolve."
        end
        puts ""
      end
    end

    class App < Thor
      def self.exit_on_failure?
        true
      end

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

      desc "config SUBCOMMAND", "Manage user preferences"
      subcommand "config", ConfigApp

      desc "cloud SUBCOMMAND", "Sync tasks with Tasku Cloud"
      subcommand "cloud", CloudApp

      def help(*args)
        if args.empty?
          puts ""
          puts pastel.bold(LOGO)
          puts "  #{pastel.bold(TAGLINE)}"
          puts ""
        end
        super
      end

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

        if attrs.nil?
          puts pastel.yellow("  Add cancelled.")
          return
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
      option :overdue,   type: :boolean, desc: "Show only overdue tasks"
      option :today,     type: :boolean, desc: "Show tasks due today"
      option :tomorrow,  type: :boolean, desc: "Show tasks due tomorrow"
      option :sort,      type: :string,  desc: "Sort by: id, name, priority, due, status, created"
      option :order,     type: :string,  desc: "Order: asc, desc", default: "asc"
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

        if options[:today]
          today = Date.today
          dataset = dataset.where(due_day: today).exclude(status: %w[done cancelled])
        end

        if options[:tomorrow]
          tomorrow = Date.today + 1
          dataset = dataset.where(due_day: tomorrow).exclude(status: %w[done cancelled])
        end

        sort_col = case options[:sort]
                   when "name"     then :name
                   when "priority" then Sequel.case(Task::VALID_PRIORITIES.each_with_index.to_h, 999, :priority)
                   when "due"      then :due_day
                   when "status"   then Sequel.case(Task::VALID_STATUSES.each_with_index.to_h, 999, :status)
                   when "created"  then :created_at
                   else :id
                   end

        order = options[:order] == "desc" ? Sequel.desc(sort_col) : Sequel.asc(sort_col)
        dataset = dataset.order(order)

        tasks = dataset.all
        bar = { "bar_project" => Config.get("bar_project"), "bar_priority" => Config.get("bar_priority"), "bar_status" => Config.get("bar_status") }
        cols_cfg = {
          "col_project"      => Config.get("col_project"),
          "col_category"     => Config.get("col_category"),
          "col_priority"     => Config.get("col_priority"),
          "col_status"       => Config.get("col_status"),
          "col_due"          => Config.get("col_due"),
          "col_name_min"     => Config.get("col_name_min"),
          "col_priority_min" => Config.get("col_priority_min"),
          "col_status_min"   => Config.get("col_status_min"),
          "col_due_min"      => Config.get("col_due_min")
        }
        if ENV["MADO"] == "1"
          Tasku::TUI::MadoList.new(tasks, colour_map: Project.colour_map, bar: bar, cols_cfg: cols_cfg, project: options[:project]).run
        else
          terminal.render_list(tasks, colour_map: Project.colour_map, spacing: Config.get("list_spacing"), bar: bar, cols_cfg: cols_cfg)
        end
      end

      desc "show ID", "Show task details"
      def show(id)
        task = find_task(id)
        terminal.render_show(task, colour_map: Project.colour_map)
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
      option :interactive, type: :boolean, aliases: "-i", desc: "Interactive mode", default: false
      def edit(id)
        task = find_task(id)

        attrs = if options[:interactive]
                  interactive_edit(task)
                else
                  option_edit
                end
        if attrs.nil?
          puts pastel.yellow("  Edit cancelled.")
          return
        end
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
      option :project, type: :string, desc: "Filter by project"
      def stats
        dataset = Task.dataset
        dataset = dataset.where(project: options[:project]) if options[:project]
        tasks = dataset.all
        terminal.render_stats(tasks, colour_map: Project.colour_map) if tasks
      end

      desc "projects", "List all projects"
      def projects
        project_names = Task.dataset.select(:project).where(Sequel.~(project: nil)).distinct.order(:project).map(:project)
        if project_names.empty?
          puts pastel.yellow("  No projects found.")
          return
        end

        colour_map = Project.colour_map
        puts ""
        project_names.each do |p|
          count = Task.where(project: p).count
          colour = colour_map[p]
          swatch = colour ? "#{hex_colour_str("█", colour)} " : "  "
          name_str = colour ? hex_bold_str(p, colour) : pastel.bold(p)
          puts "  #{swatch}#{name_str} #{pastel.dim("(#{count} task(s))")}"
        end
        puts ""
      end

      desc "colour PROJECT HEX", "Set a project's display colour (e.g. #FF5733). Omit HEX to clear."
      def colour(project, hex = nil)
        if hex.nil?
          proj = Project[project]
          if proj
            proj.update(colour: nil)
            puts pastel.green("  Colour cleared for project '#{project}'.")
          else
            puts pastel.yellow("  No colour set for project '#{project}'.")
          end
          return
        end

        validated = validate_hex!(hex)
        Project.find_or_create(name: project).update(colour: validated)
        swatch = hex_colour_str("█", validated)
        puts "  #{swatch} Colour #{pastel.bold(validated)} set for project '#{pastel.bold(project)}'."
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
        rescue TTY::Reader::InputInterrupt
          nil
        end

        def interactive_edit(task)
          prompt = TTY::Prompt.new

          name = prompt.ask("Task name:", default: task.name, required: true) do |q|
            q.modify :strip
          end

          description = prompt.ask("Description:", default: task.description || "")
          description = nil if description&.empty?

          project = prompt.ask("Project:", default: task.project || "")
          project = nil if project&.empty?

          category = prompt.ask("Category:", default: task.category || "")
          category = nil if category&.empty?

          priority = prompt.select("Priority?", %w[none low medium high urgent],
                                   default: task.priority || "none")
          status = prompt.select("Status?", Task::VALID_STATUSES,
                                 default: task.status || "todo")

          start_day = prompt.ask("Start date (YYYY-MM-DD, optional):",
                                 default: task.start_day&.to_s || "")
          start_day = nil if start_day&.empty?

          due_day = prompt.ask("Due date (YYYY-MM-DD, optional):",
                               default: task.due_day&.to_s || "")
          due_day = nil if due_day&.empty?

          model_name = prompt.ask("Model:", default: task.model_name || "")
          model_name = nil if model_name&.empty?

          code = prompt.ask("Code:", default: task.code || "")
          code = nil if code&.empty?

          tags = prompt.ask("Tags (comma-separated):", default: task.tags || "")
          tags = nil if tags&.empty?

          hours = prompt.ask("Estimated hours:", default: task.estimated_hours&.to_s || "") do |q|
            q.convert(:float, "")
          end
          hours = nil if hours.is_a?(String) && hours.empty?

          {
            name: name,
            description: description,
            project: project,
            category: category,
            start_day: parse_date(start_day),
            due_day: parse_date(due_day),
            model_name: model_name,
            code: code,
            priority: priority,
            status: status,
            tags: tags,
            estimated_hours: hours
          }.compact
        rescue TTY::Reader::InputInterrupt
          nil
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

        def validate_hex!(hex)
          hex = hex.start_with?("#") ? hex : "##{hex}"
          unless hex.match?(/\A#[0-9a-fA-F]{6}\z/)
            abort pastel.red("Invalid hex colour '#{hex}'. Use format #RRGGBB.")
          end
          hex
        end

        def hex_colour_str(text, hex)
          r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) }
          "\e[38;2;#{r};#{g};#{b}m#{text}\e[0m"
        end

        def hex_bold_str(text, hex)
          r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) }
          "\e[1;38;2;#{r};#{g};#{b}m#{text}\e[0m"
        end

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
