class RingCache

  EMPTY = Object.new

  def initialize(size = 64)
    @hash = Hash.new(EMPTY)
    @hash_semaphore = Mutex.new
    @buffer = RingBuffer.new(size)
    @writer = @buffer.iterator
    @cache_queue = Queue.new

    @cache_manager = Thread.new do
      searcher = @buffer.iterator

      while message = @cache_queue.pop
        action, cache_value = message

        begin
          unless cache_value.index.nil?
            searcher.seek!(cache_value.index)
            searcher.unset!
            cache_value.hits += 1
          end

          unless action == :evict
            overwrite_current(cache_value)
          end
        rescue
          puts "ERROR: #{$!}"
        end
      end
    end
  end

  def get(key)
    stored = @hash[key]
    if stored === EMPTY
      raise "Key \"#{key}\" not found and no block given" unless block_given?
      calculated = yield
      set(key, calculated)
    else
      # promote hit value
      @cache_queue.push([:promote, stored])
      stored.value
    end
  end

  def set(key, value)
    cache_value = CacheValue.new(key, value)

    @hash_semaphore.synchronize do
      existing = @hash[key]

      unless existing === EMPTY
        @cache_queue.push([:evict, existing])
      end

      @hash[key] = cache_value
      @cache_queue.push([:set, cache_value])
    end

    value
  end

  def to_s
    @writer.inspect
  end

  private

  def overwrite_current(cache_value)
    if @writer.set?
      # going to overwrite so evict 20% of the buffer for locking efficiency
      housekeeper = @writer.clone
      entries_to_remove = [(@buffer.size * 0.2).to_i, 1].max

      @hash_semaphore.synchronize do
        entries_to_remove.times do
          next unless housekeeper.set?
          evict(housekeeper)
          housekeeper.next
        end
      end
    end

    cache_value.index = @writer.index
    @writer.set(cache_value)
    @writer.next
  end

  def evict(iterator)
    # evicting a stale value
    evictee = iterator.current

    if @hash[evictee.key] === evictee
      @hash.delete(evictee.key)
    end

    iterator.unset!
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

    attr_reader :size

    def initialize(size)
      @size = size
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

      def seek!(value)
        @current_index = safe_index(value)
        current
      end

      def next
        seek! next_index
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

      def set_index(value)
        @current_index = value
        current
      end

      def next_index
        safe_index(@current_index + 1)
      end

      def safe_index(value)
        value % @buffer.size
      end

    end

  end

end
