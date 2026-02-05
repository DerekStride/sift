# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"

module Sift
  # Persistent queue for review items stored as JSONL
  class Queue
    class Error < StandardError; end

    # Source types for queue items
    VALID_SOURCE_TYPES = %w[diff file transcript text].freeze

    # Valid status values
    VALID_STATUSES = %w[pending in_progress approved rejected failed].freeze

    # Represents a source of content for review
    Source = Struct.new(:type, :path, :content, :session_id, keyword_init: true) do
      def to_h
        {
          type: type,
          path: path,
          content: content,
          session_id: session_id
        }.compact
      end

      def self.from_h(hash)
        new(
          type: hash["type"] || hash[:type],
          path: hash["path"] || hash[:path],
          content: hash["content"] || hash[:content],
          session_id: hash["session_id"] || hash[:session_id]
        )
      end
    end

    # Represents a queue item
    Item = Struct.new(:id, :status, :sources, :metadata, :session_id, :created_at, :updated_at, keyword_init: true) do
      def to_h
        {
          id: id,
          status: status,
          sources: sources.map(&:to_h),
          metadata: metadata,
          session_id: session_id,
          created_at: created_at,
          updated_at: updated_at
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      def self.from_h(hash)
        sources = (hash["sources"] || hash[:sources] || []).map do |src|
          Source.from_h(src)
        end

        new(
          id: hash["id"] || hash[:id],
          status: hash["status"] || hash[:status],
          sources: sources,
          metadata: hash["metadata"] || hash[:metadata] || {},
          session_id: hash["session_id"] || hash[:session_id],
          created_at: hash["created_at"] || hash[:created_at],
          updated_at: hash["updated_at"] || hash[:updated_at]
        )
      end

      def pending?
        status == "pending"
      end

      def in_progress?
        status == "in_progress"
      end

      def approved?
        status == "approved"
      end

      def rejected?
        status == "rejected"
      end

      def failed?
        status == "failed"
      end
    end

    attr_reader :path

    def initialize(path)
      @path = path
    end

    # Add a new item to the queue
    # Returns the created Item
    def push(sources:, metadata: {}, session_id: nil)
      validate_sources!(sources)

      now = Time.now.utc.iso8601
      item = Item.new(
        id: generate_id,
        status: "pending",
        sources: normalize_sources(sources),
        metadata: metadata,
        session_id: session_id,
        created_at: now,
        updated_at: now
      )

      append_item(item)
      item
    end

    # Iterate over pending items
    def each_pending(&block)
      filter(status: "pending").each(&block)
    end

    # Update an item by ID
    # Returns the updated Item or nil if not found
    def update(id, **attrs)
      items = all
      index = items.index { |item| item.id == id }
      return nil unless index

      item = items[index]

      # Validate status if provided
      if attrs[:status]
        status = attrs[:status].to_s
        unless VALID_STATUSES.include?(status)
          raise Error, "Invalid status: #{status}. Valid: #{VALID_STATUSES.join(", ")}"
        end
        attrs[:status] = status
      end

      # Update fields
      attrs[:updated_at] = Time.now.utc.iso8601
      updated_item = Item.new(**item.to_h.merge(attrs))
      items[index] = updated_item

      write_all(items)
      updated_item
    end

    # Find an item by ID
    # Returns Item or nil
    def find(id)
      all.find { |item| item.id == id }
    end

    # Filter items by criteria
    # Returns array of Items
    def filter(status: nil)
      items = all
      items = items.select { |item| item.status == status.to_s } if status
      items
    end

    # Get all items
    # Returns array of Items
    def all
      return [] unless File.exist?(@path)

      items = []
      File.foreach(@path) do |line|
        next if line.strip.empty?

        data = JSON.parse(line)
        items << Item.from_h(data)
      end
      items
    rescue JSON::ParserError => e
      raise Error, "Failed to parse queue file: #{e.message}"
    end

    # Count items, optionally by status
    def count(status: nil)
      filter(status: status).size
    end

    # Remove an item by ID
    # Returns the removed Item or nil
    def remove(id)
      items = all
      removed = nil
      items.reject! do |item|
        if item.id == id
          removed = item
          true
        else
          false
        end
      end

      write_all(items) if removed
      removed
    end

    # Clear all items from the queue
    def clear
      write_all([])
    end

    private

    def generate_id
      # Generate a short unique ID (3 alphanumeric chars like beads tool)
      chars = ("a".."z").to_a + ("0".."9").to_a
      existing_ids = all.map(&:id).to_set

      loop do
        id = 3.times.map { chars.sample }.join
        return id unless existing_ids.include?(id)
      end
    end

    def validate_sources!(sources)
      raise Error, "Sources cannot be empty" if sources.nil? || sources.empty?

      sources.each do |source|
        type = source[:type] || source["type"]
        unless VALID_SOURCE_TYPES.include?(type)
          raise Error, "Invalid source type: #{type}. Valid: #{VALID_SOURCE_TYPES.join(", ")}"
        end
      end
    end

    def normalize_sources(sources)
      sources.map do |source|
        if source.is_a?(Source)
          source
        else
          Source.from_h(source)
        end
      end
    end

    def append_item(item)
      ensure_directory
      File.open(@path, "a") do |f|
        f.puts(item.to_json)
      end
    end

    def write_all(items)
      ensure_directory
      File.open(@path, "w") do |f|
        items.each do |item|
          f.puts(item.to_json)
        end
      end
    end

    def ensure_directory
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end
  end
end
