# frozen_string_literal: true

module Sift
  module TUI
    # Command handlers mixed into App.
    # Each cmd_* method returns [self, command_or_nil] per the Bubbletea contract.
    module Commands
      def cmd_quit
        stop_async_reactor
        [self, Bubbletea.quit]
      end

      def cmd_view
        item = current_item
        return [self, nil] unless item

        callable = -> {
          editor = Editor.new(sources: item.sources, item_id: item.id, session_id: item.session_id, restore_tty: false)
          editor.open
        }
        [self, Bubbletea.exec(callable, message: ViewDoneMessage.new)]
      end

      def cmd_agent
        return [self, nil] unless current_item
        enter_prompt_mode(:item_agent, current_item)
        [self, nil]
      end

      def cmd_close
        return [self, nil] unless current_item
        done = handle_close(current_item)
        if done
          stop_async_reactor
          [self, Bubbletea.quit]
        else
          [self, nil]
        end
      end

      def cmd_general
        enter_prompt_mode(:general_agent, nil)
        [self, nil]
      end

      def cmd_next
        return [self, nil] if @items.size <= 1
        @index = (@index + 1) % @items.size
        [self, nil]
      end

      def cmd_prev
        return [self, nil] if @items.size <= 1
        @index = (@index - 1) % @items.size
        [self, nil]
      end

      def cmd_submit_prompt
        submit_prompt
      end

      def cmd_submit_via_editor
        submit_prompt_via_editor
      end

      def cmd_cancel_prompt
        cancel_prompt
        [self, nil]
      end
    end
  end
end
