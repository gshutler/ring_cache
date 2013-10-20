require 'minitest/autorun'
require 'minitest/spec'

require_relative "ring_cache"

describe RingCache do

  subject { RingCache.new(5) }

  describe "#get" do

    it "lazily gets uncached values" do
      value = 1
      calls = 0
      last_result = nil

      5.times do
        last_result = subject.get(:value) do
          calls += 1
          value
        end
      end

      assert_equal 1, calls
      assert_equal value, last_result
    end

    it "raises if cache miss and no block given" do
      assert_raises RuntimeError do
        subject.get(:miss)
      end
    end

    it "promotes on get to avoid eviction of recently used values" do
      # add our frequent hit first
      subject.set(:frequent, 42)

      # fill the rest of the buffer
      (1..4).each do |value|
        subject.set(value, value)
      end

      # get the value to trigger promotion
      subject.get(:frequent)

      # fill the buffer over again
      (5..8).each do |value|
        subject.set(value, value)
      end

      # should not fail as the value should still be cached
      subject.get(:frequent)
    end

  end

  describe "#set" do

    it "evicts old values when the buffer fills" do
      value = 42
      calls = 0

      subject.set(:value, value)

      # fill the rest of the buffer so the value should be evicted
      (1..5).each do |value|
        subject.set(value, value)
      end

      subject.get(:value) do
        calls += 1
        value
      end

      assert_equal 1, calls
    end

  end

end

describe RingCache::RingBuffer::Iterator do

  let(:buffer) { RingCache::RingBuffer.new(5) }

  subject { buffer.iterator }

  describe "#initialize" do
    it "initializes everything as EMPTY" do
      items = 0

      subject.each_with_empty do |item|
        assert_same RingCache::EMPTY, item
        items += 1
      end

      assert_equal 5, items
    end
  end

  describe "#set" do

    let(:value) { Object.new }

    it "reports as not set beforehand" do
      refute subject.set?
    end

    it "report as set afterwards" do
      subject.set(value)
      assert subject.set?
    end

    it "returns the set value afterwards for current" do
      subject.set(value)
      assert_same value, subject.current
    end

  end

  describe "#unset!" do

    let(:value) { Object.new }

    before do
      subject.set(value)
    end

    it "reports as set beforehand" do
      assert subject.set?
    end

    it "report as not set afterwards" do
      subject.unset!
      refute subject.set?
    end

    it "returns the unset value" do
      assert_same value, subject.unset!
    end

  end

  describe "filling the buffer" do

    it "rolls over, overwriting old values" do
      (1..10).each do |num|
        subject.set(num)
        subject.next
      end

      assert_equal (6..10).to_a, subject.to_a
    end

  end

end

