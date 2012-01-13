#!/usr/bin/env ruby 

require "optparse"
require "pp"

$running = true

def make_path()
  gpath =$config[:testdir]
  if (gpath[0..8] == "gfarm:///")
    gpath.slice!(0..7)
  end
  return $config[:gfarm2fs]+gpath
end

$gfsds = `gfsched`.split("\n")
if ($gfsds.size == 0)
  STDERR.print "no gfsd!\n"
  exit(1)
end

$config = Hash.new
$config[:testdir] = "gfarm:///stress"
$config[:number] = 1
opts = OptionParser.new
opts.on("-t MANDATORY",
        "--testdir MANDATORY",
        String,
        "test gfarm url") {|v|
  $config[:testdir] = v
}
opts.on("-m MANDATORY",
        "--gfarm2fs MANDATORY",
        String,
        "gfarm2fs mountpoint") {|v|
  $config[:gfarm2fs] = v
}
opts.on("-n MANDATORY",
        "--number MANDATORY",
        Integer,
        "number of multiplex") {|v|
  $config[:number] = v
} 
opts.parse!(ARGV)

if (!$config[:gfarm2fs].nil?)
  $config[:fullpath] = make_path()
end
  
$config[:number].times { |i|
  system("gfmkdir -p #{$config[:testdir]}/metadata/#{i}");
  system("gfmkdir -p #{$config[:testdir]}/tree/#{i}");
  system("gfmkdir -p #{$config[:testdir]}/io/#{i}");
  if (!$config[:gfarm2fs].nil?)
    system("gfmkdir -p #{$config[:testdir]}/metadata2/#{i}");
    system("gfmkdir -p #{$config[:testdir]}/tree2/#{i}");
    system("gfmkdir -p #{$config[:testdir]}/io2/#{i}");
  end
}
$commands = Array.new

$config[:number].times { |i|
  $commands.push("gfperf-metadata -t #{$config[:testdir]}/metadata/#{i} -n 500")
  $commands.push("gfperf-tree -t #{$config[:testdir]}/tree/#{i} -w 3 -d 5")
  $gfsds.each {|g|
    $commands.push("gfperf-read -t #{$config[:testdir]}/io/#{i} -l 1G -g #{g} -k -1")
    $commands.push("gfperf-write -t #{$config[:testdir]}/io/#{i} -l 1G -g #{g} -k -1")
  }
  tg = $gfsds.clone
  tg.push(tg.shift)
  $gfsds.each_index {|i|
    $commands.push("gfperf-replica -s #{$gfsds[i]} -d #{tg[i]} -l 1M -t #{$config[:testdir]}/io/#{i}")
  }

  if (!$config[:gfarm2fs].nil?)
    $commands.push("gfperf-metadata -t file://#{$config[:fullpath]}/metadata2/#{i} -n 500")
    $commands.push("gfperf-tree -t file://#{$config[:fullpath]}/tree2/#{i}")
    $gfsds.each {|g|
      $commands.push("gfperf-read -t #{$config[:testdir]}/io2/#{i} -m #{$config[:gfarm2fs]} -l 1G -g #{g} -k -1")
      $commands.push("gfperf-write -t #{$config[:testdir]}/io2/#{i} -m #{$config[:gfarm2fs]} -l 1G -g #{g} -k -1")
    }
  end
}

class Runner
  def init(manager, command)
    @manager = manager
    @command = command
    return self
  end

  def start()
    @running = true
    @thread = Thread.new { self.run() }
    return self
  end

  def run()
    while (@running) 
      @pipe = Array.new
      @pipe[0] = IO.pipe
      @pipe[1] = IO.pipe
      @pipe[2] = IO.pipe
    
      @stdin = @pipe[0][1]
      @stdout = @pipe[1][0]
      @stderr = @pipe[2][0]
      
      break unless (@running)
      @pid = fork {
        @pipe[0][1].close
        @pipe[1][0].close
        @pipe[2][0].close
        STDIN.reopen(@pipe[0][0])
        STDOUT.reopen(@pipe[1][1])
        STDERR.reopen(@pipe[2][1])
        exec("#{@command}");
      }
      @pipe[0][0].close
      @pipe[1][1].close
      @pipe[2][1].close
      outstr = ""
      errstr = ""
      t0 = Thread.new {
        while (tmp = @stdout.read)
          if (tmp == "")
            break
          end
          outstr += tmp
        end
      }
      t1 = Thread.new {
        while (tmp = @stderr.read)
          if (tmp == "")
            break
          end
          errstr += tmp
        end
      }
      Process.waitpid(@pid)
      t0.join
      t1.join
      @stdin.close
      @stdout.close
      @stderr.close
      tmp = errstr.split("\n").map{|l|
        if (!l.include?("[1000058] connecting to gfmd"))
          l
        end
      }.compact
      if (tmp.size > 0)
        errstr = tmp.join("\n")+"\n"
      else
        errstr = ""
      end
      if (errstr.length > 0)
        print @command+"\n"
        print errstr
        @manager.stop
        @running = false
      end
    end
  end

  def wait()
    @thread.join
    return self
  end

  def stop()
    @running = false
    begin
      Process.kill(:TERM, @pid)
    rescue
    end
  end
end

class Manager
  def init()
    @runners = Array.new
    $commands.each { |com|
      @runners.push(Runner.new.init(self, com))
    }
    return self
  end

  def run()
    @runners.each { |r|
      r.start
    }
    return self
  end

  def stop()
    @stop_thread = Thread.new {
      @runners.each { |r|
        r.stop
      }
    }
    return self
  end

  def wait()
    @runners.each { |r|
      r.wait
    }
    @stop_thread.join unless (@stop_thread)
    return self
  end

end

print "start at #{Time.now.to_s}\n"

$manager = Manager.new.init.run

Signal.trap(:INT) {
  $manager.stop
}

Signal.trap(:TERM) {
  $manager.stop
}

$manager.wait

print "stop at #{Time.now.to_s}\n"

print "clean up..."
system("gfrm -rf #{$config[:testdir]}/*");
print "done.\n"
