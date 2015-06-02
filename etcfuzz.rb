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

    setup = [
      Proc.new { || run 1, @setupInits[0], "new" },
      Proc.new { ||
        puts "trying"
        run(2, @setupInits[1], "existing")
      },
      Proc.new { || run 3, @setupInits[2], "existing" },
    ]
    @threads[1] = Thread.new { setup.first.call }
    [1,2].each { |i|
      puts "waiting 3 seconds for it to come up"
      sleep 3
      @threads[i] = Thread.new do
        configure i + 1
        run i + 1, @setupInits[i], "existing"
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
    puts "configuring #{i}"
    r = `bin/etcdctl -C http://localhost:500#{@threads.keys.sample} member add etcd-#{i} http://localhost:400#{i}`
    puts r
  end

  def run i, init, op="existing"
    `rm  -rf d#{i}`
    cmd = @invoke % {n: i, op: op, initial_cluster: init}
    exit if cmd.include? "panic"

    puts "invoking", cmd
    result = system(cmd.split("\n").join(" "))
  end

  def kill_one
    return unless @threads.length >= 2
    target = @threads.keys.sample
    puts "running now: #{@threads.keys}"
    puts "trying to kill #{target}"
    Thread.kill(@threads[target])
    `ps aux | grep "400#{target}$" | awk '{print $2}' | xargs kill`
    @threads.delete(target)
  end

  def spawn_one
    return unless @threads.length < 4
    candidates = [1,2,3,4].reject { |e| @threads.keys.include? e }
    n = candidates.sample
    puts "running now: #{@threads.keys}"
    puts "trying to start #{n}"
    configure n
    @threads[n] = Thread.new { || run n, @laterInits.sample }
  end
end

ef = EtcFuzz.new
loop do
  sleep 3
  if rand > 0.5
    ef.kill_one
  else
    ef.spawn_one
  end
end
