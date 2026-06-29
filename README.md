# Tasku

タスクリスト — a beautiful terminal task manager.

Colour-coded priorities, status tracking, SQLite persistence, and a clean CLI interface.

## Requirements

Ruby **>= 3.1.0**. Check your version:

```bash
ruby --version
```

If you need to install or upgrade Ruby, use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com):

```bash
# with rbenv
rbenv install 3.4.0
rbenv global 3.4.0

# with asdf
asdf install ruby 3.4.0
asdf global ruby 3.4.0
```

## Installation

```bash
gem install tasku
```

## Usage

Run `tasku` followed by a command:

```
tasku add              Create a new task
tasku list             List all tasks
tasku show ID          Show task details
tasku edit ID          Edit a task
tasku done ID          Mark a task as done
tasku delete ID        Delete a task
tasku stats            Show task statistics
tasku projects         List all projects
tasku categories       List all categories
tasku version          Show version
```

### Adding a task

```bash
tasku add --name "Write docs" --priority high --due 2026-07-15
```

Or use interactive mode:

```bash
tasku add -i
```

### Listing tasks

```bash
tasku list                          # all tasks
tasku list --status todo            # filter by status
tasku list --priority high          # filter by priority
tasku list --project "MyApp"        # filter by project
tasku list --overdue                # overdue tasks only
tasku list --sort due --order desc  # sorted
```

### Editing a task

```bash
tasku edit 1 --name "New name" --priority urgent
tasku edit 1 --clear tags,hours
```

### Valid values

| Field    | Values                                                   |
|----------|----------------------------------------------------------|
| Priority | `none`, `low`, `medium`, `high`, `urgent`                |
| Status   | `backlog`, `todo`, `in_progress`, `done`, `cancelled`, `archived` |

### Raw SQL

```bash
tasku --sql "SELECT * FROM tasks WHERE priority = 'high'"
```

## Development

```bash
git clone https://github.com/tomdringer/tasku.git
cd tasku
bundle install
ruby -Ilib exe/tasku list
```

## License

MIT
