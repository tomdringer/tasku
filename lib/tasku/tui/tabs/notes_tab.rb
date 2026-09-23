# frozen_string_literal: true

module Tasku
  module TUI
    module Tabs
      class NotesTab < Tab
        def initialize
          super("Notes")
        end

        def render(pastel, width, height)
          [
            "",
            pastel.dim("Notes coming soon.".center(width)),
            "",
            pastel.dim("Create notes tied to tasks or standalone.".center(width))
          ]
        end
      end
    end
  end
end
