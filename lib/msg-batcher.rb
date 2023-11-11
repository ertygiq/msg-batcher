# frozen_string_literal: true

# Important!:
# If release method is called by timer thread, all other pushes will wait until release callback is finished by
# timer thread. If release is issued by pushers, the release callback would be ran by last pushing thread
# but other push threads would not wait for it to finish (which is good).


class MsgBatcher
  DEBUG = false

  class Error < StandardError; end

  def initialize(max_length, max_time_msecs, on_error=nil, &block)
    @max_length = max_length
    @max_time_msecs = max_time_msecs
    @on_error = on_error
    @on_error ||= lambda { |ex| raise ex }
    @block = block

    @closed = false

    @storage = []
    @m = Mutex.new
    @m2 = Mutex.new # used besides @m mutex. Used because of timer thread.

    @timer_start_cv = ConditionVariable.new
    @timer_started_cv = ConditionVariable.new
    @timer_full_cycle_cv = ConditionVariable.new
    @timer_release_cv = ConditionVariable.new


    # It is important that push invocation start after full completion of this method.
    # So initialize instance of this class first and only then start pushing.
    start_timer
  end

  def kill(blocking: true)
    # no #push will interfere
    @m.synchronize do
      # want to make sure that timer thread is in a waiting position. Hence, acquiring @m2
      @m2.synchronize do
        @closed = true
        # releasing timer thread
        @timer_start_cv.signal
        # This can happen, however, that timer thread will wait timeout on @timer_release_cv.
        # If it was waiting on @timer_start_cv. Because timer thread won't reach @timer_release_cv wait poisition
        @timer_release_cv.signal
      end
      @timer_thread.join if blocking
    end
  end

  # Thread-safe
  # @raise [Error] when invoked when batcher has been closed
  def push(entry)
    raise Error, 'Batcher is closed - cannot push' if @closed

    @m.lock
    @m2.lock

    # Start timer
    # Timer thread must be in TT1 position
    if @storage.empty?
      @timer_start_cv.signal
      @timer_started_cv.wait @m2 # waiting for timer thread to be in position TT2
    end

    @storage.push entry
    # curr_size = @storage.inject(0) { |sum, e| s}
    if @storage.size == @max_length
      # unlocks @m inside release method
      release
    else
      @m2.unlock
      @m.unlock
    end
  end

  private

  def dputs(str)
    puts str if DEBUG
  end

  def release(from_push=true)
    # inside @m lock
    temp = @storage
    @storage = []

    @already_released = true
    dputs 'kill timer'
    @timer_release_cv.signal # informing timer that release is happening

    # Now interesting happens
    # We are releasing @m2 lock and waiting for @timer_full_cycle_cv
    # No other thread but timer thread would acquire @m2 lock, as other threads that are pushing
    # are locked on @m.
    # So as @m2 is acquired by timer thread, it starts new loop cycle and signals @timer_full_cycle_cv
    # So this release method stops waiting and tries to lock @m2 again. But it cannot until timer
    # thread releases it. It releases it on line @timer_start_cv.wait @m2.
    # So now we can be sure that timer is at the beginning, ready to wait for @timer_start_cv signal.

    if from_push
      dputs '--------before wait m2'
      @timer_full_cycle_cv.wait @m2
      @m2.unlock
      dputs '-----22222'
      @m.unlock
      dputs '---- unlock all'
    end

    if temp.empty?
      # The situation when the batch is empty should not happen.
      # However, when the batcher is killed and the timer thread is forced to finish this can happen
      # In any case, just ignoring this empty batch and do not call callback on it
      warn 'MsgBatcher: empty batch. This should not have happened' unless @closed
      return
    end

    begin
      @block.call temp
    rescue
      @on_error.call $!
    end

  end

  def start_timer
    @m2.lock

    @timer_thread = Thread.new do
      @m2.lock
      while true
        @already_released = false
        # informing release that timer is at the beginning
        @timer_full_cycle_cv.signal
        dputs 'sdlkfjsd'

        # Position: TT1
        # Wait for invocation from push
        # Each release invocation finishes when timer thread are below (waiting for @timer_start_cv)
        dputs 'TT1'
        @timer_start_cv.wait @m2

        dputs 'TT1 after wait'
        @timer_started_cv.signal

        dputs 'TT2'
        # then wait either time to elapse or signal that data has been released
        @timer_release_cv.wait @m2, @max_time_msecs / 1000.0
        dputs "timer end #{@m2.owned?}"
        # @m2 is locked here!
        unless @already_released
          dputs "timer's release"
          release(false)
        end

        break if @closed
      end
    end
    # wait for timer to be in waiting state
    @timer_full_cycle_cv.wait @m2
    @m2.unlock
  end
end
