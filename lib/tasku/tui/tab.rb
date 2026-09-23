# frozen_string_literal: true

module Tasku
  module TUI
    class Tab
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def render(pastel, width, height)
        raise NotImplementedError
      end
    end
  end
end
