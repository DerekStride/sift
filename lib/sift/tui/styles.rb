# frozen_string_literal: true

require "lipgloss"

module Sift
  module TUI
    module Styles
      # Card frame
      CARD_BORDER = Lipgloss::Style.new
        .border(:rounded)
        .border_foreground("#5B8DEF")
        .padding(0, 1)

      # Card title (item id + title)
      CARD_TITLE = Lipgloss::Style.new
        .bold(true)
        .foreground("#5B8DEF")

      # Position indicator [2/5]
      CARD_POSITION = Lipgloss::Style.new
        .foreground("#666666")

      # Source type headers (diff, text, file, etc.)
      SOURCE_TYPE = Lipgloss::Style.new
        .foreground("#E5C07B")
        .bold(true)

      # Source paths/labels
      SOURCE_PATH = Lipgloss::Style.new
        .foreground("#666666")

      # Action bar key
      ACTION_KEY = Lipgloss::Style.new
        .bold(true)

      # Action bar separator
      ACTION_SEP = Lipgloss::Style.new
        .foreground("#444444")

      # Status bar text
      STATUS_TEXT = Lipgloss::Style.new
        .foreground("#666666")

      # Flash styles
      FLASH_INFO = Lipgloss::Style.new
        .foreground("#5B8DEF")

      FLASH_SUCCESS = Lipgloss::Style.new
        .foreground("#98C379")

      FLASH_ERROR = Lipgloss::Style.new
        .foreground("#E06C75")

      # Prompt label
      PROMPT_LABEL = Lipgloss::Style.new
        .bold(true)

      PROMPT_HINT = Lipgloss::Style.new
        .foreground("#666666")

      PROMPT_KEY = Lipgloss::Style.new
        .foreground("#666666")

      PROMPT_CONFIG_LABEL = Lipgloss::Style.new
        .foreground("#AAB2BF")
        .bold(true)

      PROMPT_VALUE = Lipgloss::Style.new
        .bold(true)

      # Waiting message
      WAITING_TEXT = Lipgloss::Style.new
        .foreground("#666666")
        .italic(true)

      # Action key colors (for building action bar)
      KEY_COLORS = {
        "v" => "#56B6C2", # cyan - view
        "a" => "#5B8DEF", # blue - agent
        "c" => "#98C379", # green - close
        "g" => "#C678DD", # magenta - general
        "n" => "#E5C07B", # yellow - next
        "p" => "#E5C07B", # yellow - prev
        "q" => "#666666", # gray - quit
      }.freeze
    end
  end
end
