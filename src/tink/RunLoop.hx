package tink;

import haxe.CallStack;
import tink.concurrent.*;
import tink.runloop.*;
import tink.runloop.WorkResult;

using tink.CoreApi;

class RunLoop extends QueueWorker {
  /**
   * The retain count of the loop. When this drops to 0 and no more tasks are scheduled, the loop is done.
   */
  public var retainCount(default, null):Int = 0;
  public var running(default, null):Bool;
  
  var slaves:Array<Worker>;
  
  public var done(default, null):Signal<Noise>;
  var _done:SignalTrigger<Noise>;
  
  static public var current(default, null):RunLoop = new RunLoop();
  
  static function getStamp()
    return
      #if sys
        Sys.cpuTime();
      #else
        haxe.Timer.stamp();
      #end
  
  /**
   * Lets the run loop burst for a given time,
   * performing as many tasks as possible until the time elapses.
   * Note that if tasks block the loop, the burst can take significantly longer.
   */
  public function burst(time:Float):WorkResult {
        
    var limit = getStamp() + Math.min(time, burstCap);
    var ret = null;
    do {
      if (!running) break;
      switch step() {
        case Progressed:
        case v: 
          ret = v;
          break;
      }
    } while (getStamp() < limit);    
    return ret;
  }
  
  /**
   * Caps how long a burst may take at most. Defaults to 250ms.
   */
  public var burstCap:Float = .25;
  
  static function create(init:Void->Void) 
    current.enter(init);
  
  public function enter(init:Void->Void) {
    if (!running)
      spin(init);
    else
      work(init);
  }
  
  var link:CallbackLink;
  var killed = false;
  
  /**
   * Hooks the run loop into the current `LoopDriver`, optionally running `init` synchronously first.
   * Safe to call again after the loop has stopped (e.g. reached `Done`) to resume it.
   */
  function spin(?init:Void->Void) {
    
    this.running = true;
    if (init != null)
      this.execute(init);
    
    var stamp = getStamp();
    link = LoopDriver.current.schedule(function () {
      var delta = getStamp() - stamp;
      stamp += delta;
      
      // `burst` can return `null` when its time budget runs out mid-progress (call again later).
      // Guard against it explicitly: switching on a `null` enum value crashes on some targets (e.g. neko).
      var result = this.burst(delta);
      return
        if (result == null) true
        else switch result {
          case Done | Aborted:
            this.running = false;
            false;
          default:
            true;
        }
    });
  }
  
  /**
   * Resumes the loop if it isn't currently pumped by a driver, e.g. because it previously
   * reached `Done`. Called whenever new work is scheduled.
   */
  function ensurePumping()
    if (!running && !killed)
      spin();
  
  override public function work(task:Task):Task {
    var t = super.work(task);
    ensurePumping();
    return t;
  }
  
  override public function atNextStep(task:Task):Task {
    var t = super.atNextStep(task);
    ensurePumping();
    return t;
  }
  
  override public function asap(task:Task):Task {
    var t = super.asap(task);
    ensurePumping();
    return t;
  }
  
  override public function kill() {
    killed = true;
    running = false;
    link.cancel();
    super.kill();
  }
  
  function new(id = 'ROOT_LOOP') {
    slaves = [];
    done = _done = Signal.trigger();
    super(this, id);
  }
  
  override function log(v:Dynamic, ?p)
    haxe.Log.trace(v, p);
  
  dynamic public function onError(e:Error, t:Task, w:Worker, stack:Array<StackItem>) {
    if (w != this) {
      log(t);
      log('\nError on worker $w:\n${CallStack.toString(stack)}\n');
      kill();
      throw e;
    }
    else Error.rethrow(e);
  }  
  
  /**
   * Delegates a task to a worker.
   * The resulting future is dispatched onto the runloop's thread.
   */
  public function delegate<A>(task:Lazy<A>, slave:Worker):Future<A> {
    var t = Future.trigger();
    
    this.asap(function () retainCount++);
    
    slave.work(
      function () {
        var res = task.get();
        this.work(function () {
          t.trigger(res);
          retainCount--;
        });
      }
    );
    
    return t.asFuture();
  }
  
  /**
   * Delegates an unsafe task to a worker.
   * The resulting surprise is dispatched onto the runloop's thread.
   */
  public function tryDelegate<A>(unsafe:Lazy<A>, slave:Worker, report:Dynamic->Error):Surprise<A, Error>
    return delegate((function () return unsafe.get()).catchExceptions(report), slave);
  
  /**
   * Increases the retain count of the loop.
   */
  public function retain():Task {
    this.asap(function () retainCount++);
    
    return Task.ofFunction(function () asap(function () retainCount--));
  }
    
  /**
   * Binds a callback to this RunLoop, i.e. returns a new function that when invoked,
   * will run the provided `callback` on this `RunLoop`.
   * 
   * Note that bound callbacks:
   * 
   * 1. Can be called only once, i.e. subsequent calls will have no effect.
   * 2. Keep the RunLoop alive until called.
   * 
   * If that is more than you need, consider just using this simpler version:
   * 
   *   function (x) RunLoop.current.work(function () callback.invoke(x))
   */
  public function bind<A>(callback:Callback<A>):Callback<A> {
    if (callback == null) 
      return null;
      
    this.asap(function () retainCount++);

    return function (result:A) 
      this.work(
        function () 
          if (callback != null) {
            callback.invoke(result);
            callback = null;
            retainCount--;
          }
      );
  }
  
  /**
   * Performs an operation synchronously on the RunLoop, 
   * i.e. the calling thread will block until it's done.
   * Use sparsingly.
   */
  public function synchronously<A>(operation:Void->A):A {
    #if !concurrent
      return operation();
    #else
      if (Thread.current == this.thread)
        return operation();
      else {
        var ret = new Queue();
        
        asap(function () 
          ret.push(operation.catchExceptions())
        );
        
        return switch ret.await() {
          case Success(data): data;
          case Failure(e): throw e;
        }
        
      }
    #end
  }
  
  #if !concurrent
  var slaveCounter = 0;
  function runSlaves():WorkResult {
    slaveCounter %= slaves.length;
    if (slaves.length > 0)
      for (_ in 0...slaves.length) 
        switch slaves[slaveCounter++ % slaves.length].step() {
          case Progressed:
            return Progressed;
          default:
        }
    return Idle;
  }
  #end
  
  override function doStep():WorkResult 
    return
      switch tasks.pop() {
        case null:
          if (this.retainCount == 0) {
            _done.trigger(Noise);
            Done;
          }
          else 
            #if concurrent
              super.doStep();
            #else
              runSlaves();
            #end
        case v: 
          execute(v);
      }
  
  /**
   * Creates a slave.
   * 
   * In concurrent mode, each slave gets its own thread.
   * Otherwise, slaves progress when the owner run loop idles.
   */
  public function createSlave():Worker {
    var w = new QueueWorker(this, '$id/worker#${this.slaves.length}');
    this.slaves.push(w);
    #if concurrent
      new Thread(function () {
        w.thread = Thread.current;
        var res = null;
        while (res != Aborted) 
          res = w.step();
      });
    #end
    return w;
  }
  
}