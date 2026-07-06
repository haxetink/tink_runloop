# Tink Runloop

[![Build Status](https://travis-ci.org/haxetink/tink_runloop.svg?branch=master)](https://travis-ci.org/haxetink/tink_runloop)
[![Gitter](https://img.shields.io/gitter/room/nwjs/nw.js.svg?maxAge=2592000)](https://gitter.im/haxetink/public)

This library provides a cross platform [run loop](https://en.wikipedia.org/wiki/Event_loop) abstraction. It works in a single threaded mode, but does leverage multiple threads when available.
  
The very basis of the library is the concept of a worker, with the runloop itself being also a worker. Each worker can performed tasks. In this README we shall only sketch out minimal versions of the types involved to avoid complicating the matter.

A tasks, simply put, look very much like this:

```haxe
abstract Task {
  
  var recurring(get, never):Bool;
  var state(get, never):TaskState;
  
  function cancel():Void;	
  function perform():Void;
  
  @:from static function ofFunction(f:Void->Void):Task;
  @:from static function repeat(f:Void->TaskRepeat):Task;
  
  static var NOOP(default, null):Task;
}

enum TaskState {
  Pending;
  Canceled;
  Busy;
  Performed;
}

enum TaskRepeat {
  Continue;
  Done;
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
  static var current(get, never):RunLoop;
  function createSlave():Worker;
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

Ideally, you'll want to pool slaves to avoid creating too many.

## Hooking into a host's native loop

`RunLoop.current` doesn't drive itself: it delegates scheduling to a `LoopDriver`, which is responsible for hooking `RunLoop`'s ticks into whatever event loop the host platform already has. A driver is picked automatically based on the compile target:

- On `openfl`, ticks piggyback on `Application.current.onUpdate`, once per frame before rendering.
- On `lime` without `openfl`, the same happens through `lime.app.Application.current.onUpdate`.
- On `nodejs`, ticks are scheduled via `setImmediate`, integrating with libuv's event loop instead of busy-polling.
- On other `js` targets (i.e. browsers), ticks use `requestAnimationFrame` when a `window` is available, falling back to `haxe.Timer(0)` otherwise (workers, headless `js`).
- Everywhere else (cpp, neko, python, php, jvm, interp), the loop just runs a tight, blocking `while` loop on the calling thread, since there's no host loop to hook into.

You can force the blocking driver on any target by compiling with `-D tink_runloop_driver_blocking`, or plug in your own by implementing `tink.runloop.LoopDriverObject` and calling `LoopDriver.set(myDriver)` before the loop starts. `LoopDriver.reset()` restores the platform default, which is handy in tests.

### OpenFL and Lime

A typical OpenFL or Lime application blocks inside `Application.exec()` and never returns from `main()`, so `tink_runloop` can't wrap it the usual way. Compile with `-D tink_runloop_no_boot` to skip that automatic wrapping, then hook the loop up yourself once your application exists, e.g. right after creating it:

```haxe
var app = new Application();
// ...
RunLoop.current.enter(function () {});
app.exec();
```

Without `-D tink_runloop_no_boot`, the loop tries to attach to `Application.current` before it's been created and throws.

### Node.js

On Node, the loop stops pumping once it goes idle (`Done`), same as everywhere else. If you're waiting on external asynchronous work (a socket, a database driver, ...) that isn't itself scheduled through `tink_runloop`, keep the loop alive with `RunLoop.current.retain()` for as long as that work is pending - otherwise Node may exit early since nothing is left registered on its own event loop. Scheduling new work afterwards, via `work()`, `atNextStep()`, or `asap()`, automatically wakes the loop back up and reattaches the driver, so a `Done` loop isn't a dead end.
