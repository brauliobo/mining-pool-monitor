module Enumerable

  def peach threads: nil, priority: nil, wait: true, &block
    block   ||= -> *args {}
    threads ||= (ENV['THREADS'] || '10').to_i

    return each(&block) if threads == 1

    pool      = Concurrent::FixedThreadPool.new threads
    # catch_each can't be used as catchblock needs to be used inside pool.post
    ret       = each do |*args|
      pool.post do
        Thread.current.priority = priority if priority
        block.call(*args)
      rescue => e
        puts "error: #{e.message}"
      end
    end

    pool.shutdown
    pool.wait_for_termination if wait

    ret
  end

  def api_peach threads: nil, priority: nil, &block
    peach(
      threads:  threads || ENV['API_THREADS'] || 3,
      priority: priority,
      &block
    )
  end

  def cpu_peach threads: nil, priority: nil, &block
    peach(
      threads:  threads || ENV['CPU_THREADS'],
      priority: ENV['CPU_PRIORITY']&.to_i,
      &block
    )
  end

end
