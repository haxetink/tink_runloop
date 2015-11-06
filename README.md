# Tink Runloop

[![Build Status](https://travis-ci.org/haxetink/tink_runloop.svg?branch=master)](https://travis-ci.org/haxetink/tink_runloop)

This library provides a cross platform [run loop](https://en.wikipedia.org/wiki/Event_loop) abstraction. It works in a single threaded mode, but does leverage multiple threads when available.
  
The very basis of the library is the concept of a worker, with the runloop itself being also a worker. Each worker can performed tasks. In this README we shall only sketch out minimal versions of the types involved to avoid complicating the matter.

A tasks, simply put, look very much like this:

```haxe
abstract Task {
	public var recurring(get, never):Bool;
	public var state(get, never):TaskState;
  
	public function cancel():Void;	
	public function perform():Void;
  
  @:from static function ofFunction(f:Void->Void):Task;
}

enum TaskState {
	Pending;
	Canceled;
	Busy;
	Performed;
}
```

Most of the time, you will want to simply create tasks from anonymous functions through the implicit conversion.

Tasks are meant to be run by workers, which essentially boild down to this:

```haxe
interface Worker {	
	function work(task:Task):Task;
	function atNextStep(task:Task):Task;
	function asap(task:Task):Task;
  function kill():Void;
}
```

The default implementation of the worker has an internal queue of scheduled tasks, that are performed step by step. Commonly, you will want to add tasks at the end of the queue through `work`, but you can also use `atNextStep` to add the task at the beginning. If you're in a rush, then you can perform a task through `asap`, which if the calling thread is the thread that the worker runs on (which is always the case in single threaded environments), will perform the task immediately, and otherwise will add it at the beginning of the worker's queue. Try using this sparsely. Without calls to `asap`, it is guaranteed that a worker performs only one task at a time. Also, any task can only be performed by one worker at a time.

Run loops are particular implementors of the `Worker` interface and can be described like so:

```haxe
class RunLoop implements Worker {
  static public var current(get, never):RunLoop;
  public function createSlave():Worker;
}
```

Currently, there is only one run loop, but that may change in the future - if a use case presents itself. You may get by, simply scheduling all tasks on the run loop and be done. But you can also create slaves. In single threaded mode, they progress when the run loop itself is idle, so they are suitable for background tasks.

Consider something like this:
  
```haxe
import haxe.zip.*;
import tink.core.*;
  
class BackgroundCompression {
  
  static public function compress(entries:List<Entry>, level:Int, worker:Worker):Future<Noise> {
    
    for (e in entries)
      worker.work(function () if (!e.compressed) e.data = haxe.zip.Compress.run(e.data, level));
      
    return RunLoop.current.delegate(Noise, worker);
  }
}
```

This allows you offloading compression into a slave like so:

```haxe
BackgroundCompression.compress(someEntries, 9, RunLoop.current.createSlave());
```

Ideally you'll want to pool slaves to avoid creating too many.