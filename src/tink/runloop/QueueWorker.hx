package tink.runloop;

import tink.concurrent.*;
import tink.core.Error;

class QueueWorker implements Worker {

	public var id(get, null):String;
	
		inline function get_id()
			return this.id;
			
	public var owner(get, null):RunLoop;
	
		inline function get_owner()
			return this.owner;
	
	var tasks:Queue<Task>;
	var thread(default, null):Thread;
	
	public function new(owner, id) {
		this.id = id;
		this.tasks = new Queue();
		this.owner = owner;
		this.thread = Thread.current;
	}
  
	dynamic public function log(v:Dynamic, ?p:haxe.PosInfos)
    owner.log(v, p);
  
	public function work(task:Task):Task {
		if (task.state == Pending)
			tasks.add(task);
		return task;
	}	
	
	public function atNextStep(task:Task):Task {
		if (task.state == Pending)
			tasks.push(task);
		return task;
	}	
	
	public function asap(task:Task):Task {
		if (this.thread == Thread.current) 
			task.perform();
		else 
			atNextStep(task);
			
		return task;
	}
  
  public function kill()
    tasks = null;
	
	function error(e:Error, t:Task) 
		owner.asap(function () owner.onError(e, t, this, haxe.CallStack.exceptionStack()));
	
	function execute(t:Task):WorkResult
		return
			if (t == null) Idle;
			else {
				try {
					t.perform();
					if (t.recurring)
						work(t);
				}
				catch (e:Error)
					error(e, t)
				catch (e:Dynamic)
					error(Error.withData('Uncaught exception: $e', e), t);
					
				Progressed;
			}
			
	public function toString() 
		return 'Worker:$id';
	
	@:final public function step():WorkResult 
		return 
			if (thread == Thread.current)
				doStep();
			else 
				WrongThread;
			
	function doStep():WorkResult 
		return 
      if (tasks == null) Aborted;
      else execute(
				#if concurrent
					tasks.await()
				#else
					tasks.pop()
				#end
			);		
	
}