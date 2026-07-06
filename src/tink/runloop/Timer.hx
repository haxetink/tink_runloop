package tink.runloop;

import tink.RunLoop;
import tink.runloop.Task;

#if sys
class Timer {
	
	public var next(default, null):Float;
	
	var f:Void->Void;
	var recurring:Bool;
	var interval:Float;
	
	public static inline function delay(ms:Int, f:Void->Void) {
		return new Timer(ms, f);
	}
	
	public function new(ms:Int, f:Void->Void, recurring = false, ?task:TimerTask) {
		if(task == null) task = TimerTask.current;
		task.add(this);
		
		this.interval = ms / 1000;
		this.f = f;
		this.recurring = recurring;
		this.next = task.stamp() + interval;
	}
	
	public function run() {
		f();
		if(recurring) next += interval;
		else stop();
	}
	
	public function stop() {
		next = -1;
		f = null;
	}
		
}

class TimerTask extends TaskBase {
	
	public static var current(default, null):TimerTask = new TimerTask();
	
	#if concurrent
	var mutex = new tink.concurrent.Mutex();
	#end
	
	var timers:Array<Timer> = [];
	var release:Task;

	public function new() {
		super(true);
		var slave = RunLoop.current.createSlave();
		slave.work(this);
	}
	
	public function stamp() 
		return Sys.time();
	
	public function add(timer:Timer) {
		#if concurrent
		mutex.acquire();
		#end
		
		if(release == null)
			release = RunLoop.current.retain();
		timers.push(timer);
		
		#if concurrent
		mutex.release();
		#end
	}

	override function doCleanup()
		timers = [];
		
	override function doPerform() {
		#if concurrent
		mutex.acquire();
		#end
		
		var len = timers.length;
		var i = 0;
		while(i < len) {
			var timer = timers[i];
			
			switch timer.next {
				case -1:
					// TODO: using a list may be more efficient than using array#splice()
					timers.splice(i, 1);
					len--;
				case v:
					if(stamp() > v) timer.run();
					i++;
			}
		}
		
		if(timers.length == 0 && release != null) {
			RunLoop.current.work(release);
			release = null;
		}
		
		#if concurrent
		mutex.release();
		#end
		
		// Don't exhaust the cpu
		// TODO: need a smarter machanism, because this blocks in single threaded mode
		Sys.sleep(0.01);
	}
}
#end