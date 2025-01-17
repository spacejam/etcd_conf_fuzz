#!/usr/bin/env ruby

class EtcFuzz
  def initialize
    @threads = {}

    @invoke = 'bin/etcd --data-dir="d%{n}"
        --name="etcd-%{n}"
        --initial-cluster-state="%{op}"
        --listen-peer-urls="http://localhost:400%{n}"
        --initial-advertise-peer-urls="http://localhost:400%{n}"
        --listen-client-urls="http://localhost:500%{n}"
        --advertise-client-urls="http://localhost:500%{n}"
        %{initial_cluster}'

    @setupInits = %w[
        --initial-cluster="etcd-1=http://localhost:4001" 
        --initial-cluster="etcd-1=http://localhost:4001,etcd-2=http://localhost:4002" 
        --initial-cluster="etcd-1=http://localhost:4001,etcd-2=http://localhost:4002,etcd-3=http://localhost:4003" 
    ]

    @laterInits = %w[
        --initial-cluster="etcd-2=http://localhost:4002,etcd-3=http://localhost:4003,etcd-4=http://localhost:4004" 
        --initial-cluster="etcd-1=http://localhost:4001,etcd-2=http://localhost:4002,etcd-3=http://localhost:4003,etcd-4=http://localhost:4004" 
    ]

    @threads[1] = Thread.new { run(1, @setupInits[0], "new") }
    [2,3].each { |i|
      puts "waiting 3 seconds for it to come up"
      sleep 3
      @threads[i] = Thread.new do
        configure i
        run(i, @setupInits[i-1], "existing")
      end
    }
  end

  def get_port_to_ident
    mapping = `bin/etcdctl -C http://localhost:500#{@threads.keys.sample} member list`
    ntoi = mapping.split("\n").inject({}){ |h, l|
      parts = l.split(":")
      ports = parts.select{|p| p.start_with?("400")}
      h[ports.first.split().first.sub("400", "").to_i] = parts.first
      h
    }
  end

  def configure i
    loop do
      puts "configuring #{i}"
      r = `bin/etcdctl -C http://localhost:500#{@threads.keys.sample} member add etcd-#{i} http://localhost:400#{i}`
      puts "got #{r} of len #{r.length}"
      break if r.length > 50
      sleep 1 if r.length == 0
    end
  end

  def deconfigure i
    loop do
      puts "configuring #{i}"
      r = `bin/etcdctl -C http://localhost:500#{@threads.keys.sample} member remove #{i}`
      puts "got #{r} of len #{r.length}"
      break if r.length > 0
      sleep 1 if r.length == 0
    end
  end

  def run i, init, op="existing"
    `rm  -rf d#{i}`
    cmd = @invoke % {n: i, op: op, initial_cluster: init}

    puts "invoking", cmd
    result = system(cmd.split("\n").join(" "))
    exit if result.include? "panic"
    @threads.delete(i)
  end

  def kill_one
    return unless @threads.length > 2
    target = @threads.keys.sample
    deconfigure get_port_to_ident[target]
    puts "running now: #{@threads.keys}"
    puts "trying to kill #{target}"
    Thread.kill(@threads[target])
    `ps aux | grep "400#{target}$" | awk '{print $2}' | xargs kill`
    @threads.delete(target)
  end

  def spawn_one
    return unless @threads.length < 4
    candidates = [1,2,3,4].reject { |e| @threads.keys.include? e }
    puts "thread keys: #{@threads.keys}"
    puts "candidates: #{candidates}"
    n = candidates.sample
    puts "running now: #{@threads.keys}"
    puts "trying to start #{n}"
    configure n
    @threads[n] = Thread.new { run(n, @laterInits.sample) }
  end
end

ef = EtcFuzz.new
loop do
  sleep 0.5
  if rand > 0.5
    ef.kill_one
  else
    ef.spawn_one
  end
end
