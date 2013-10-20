class RingCache

  EMPTY = Object.new

  def initialize(size = 64)
    @hash = Hash.new(EMPTY)
    @buffer = RingBuffer.new(size)
    @writer = @buffer.iterator
  end

  def get(key)
    stored = @hash[key]
    if stored === EMPTY
      raise "Key \"#{key}\" not found and no block given" unless block_given?
      calculated = yield
      set(key, calculated)
    else
      # promote hit value
      @buffer.iterator(stored.index).unset!
      overwrite_current(stored)
      stored.hits += 1
      stored.value
    end
  end

  def set(key, value)
    cache_value = CacheValue.new(key, value)
    overwrite_current(cache_value)
    @hash[key] = cache_value
    value
  end

  def overwrite_current(cache_value)
    if @writer.set?
      # evicting a stale value
      evictee = @writer.unset!
      @hash.delete(evictee.key)
    end

    @writer.set(cache_value)
    cache_value.index = @writer.index
    @writer.next
  end

  def to_s
    @writer.inspect
  end

  class CacheValue

    attr_reader :key, :value
    attr_accessor :index
    attr_accessor :hits

    def initialize(key, value)
      @key = key
      @value = value
      @hits = 0
    end

    def inspect
      "{ Key:#{key}, Value:#{value}, Hits:#{hits} }"
    end

  end

  class RingBuffer

    def initialize(size)
      @buffer = Array.new(size, RingCache::EMPTY)
    end

    def iterator(start_index = 0)
      Iterator.new(@buffer, start_index)
    end

    def to_a
      iterator.to_a
    end

    class Iterator

      def initialize(buffer, index)
        @buffer = buffer
        @current_index = index
      end

      def current
        @buffer[@current_index]
      end

      def index
        @current_index
      end

      def next
        @current_index = next_index
        current
      end

      def peek
        @buffer[next_index]
      end

      def set?
        (current === RingCache::EMPTY) == false
      end

      def set(value)
        @buffer[@current_index] = value
      end

      def unset!
        c = current
        set(RingCache::EMPTY)
        c
      end

      def each
        each_with_empty do |item|
          yield item unless item === RingCache::EMPTY
        end
      end

      def each_with_empty
        each_iterator = clone
        @buffer.size.times do
          yield each_iterator.current
          each_iterator.next
        end
      end

      def to_a
        array = []
        clone.each { |value| array << value }
        array
      end

      def inspect
        to_a.inspect
      end

      def clone
        Iterator.new(@buffer, index)
      end

      private

      def next_index
        next_index = @current_index + 1
        next_index % @buffer.size
      end

    end

  end

end
