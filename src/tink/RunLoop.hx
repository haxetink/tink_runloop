package tink;

import haxe.CallStack;
import haxe.Timer;
import tink.concurrent.*;
import tink.runloop.*;
import tink.runloop.WorkResult;

using tink.CoreApi;

class RunLoop extends QueueWorker {
  /**
   * The retain count of the loop. When this drops to 0 and no more tasks are scheduled, the loop is done.
   */
  public var retainCount(default, null):Int = 0;
  
  var slaves:Array<Worker>;
  
  public var done(default, null):Signal<Noise>;
  var _done:SignalTrigger<Noise>;
  
  static public var current(default, null):RunLoop;
  
  /**
   * Lets the run loop burst for a given time,
   * performing as many tasks as possible until the time elapses.
   * Note that if tasks block the loop, the burst can take significantly longer.
   */
  public function burst(time:Float):WorkResult {
    var limit = Timer.stamp() + Math.min(time, burstCap);
    var ret = null;
    do {
      switch step() {
        case Progressed:
        case v: 
          ret = v;
          break;
      }
    } while (Timer.stamp() < limit);    
    return ret;
  }
  
  /**
   * Caps how long a burst may take at most. Defaults to 250ms.
   */
  public var burstCap:Float = .25;
  
  static function create(init:Void->Void) {
    var r = new RunLoop();
    
    current = r;
    
    r.execute(init);
    
    var stamp = Timer.stamp();
    function burst(stop) 
      return function () {
        var delta = Timer.stamp() - stamp;
        stamp += delta;
        
        switch r.burst(delta) {
          case Done | Aborted: 
            stop();
          default:
        }
      }
    
    #if flash
      flash.Lib.current.stage.addEventListener(flash.events.Event.ENTER_FRAME, function (_) { 
        r.burst(.01);
      });
    #elseif js
      var t = new Timer(0),
      t.run = burst(t.stop);
    #else
      while (true) 
        switch r.step() {
          case Done | Aborted: break;
          default:
        }
    #end
  }
  
  function new(id = 'ROOT_LOOP') {
    slaves = [];
    done = _done = Signal.trigger();
    super(this, id);
  }
  
  override function log(v:Dynamic, ?p)
    haxe.Log.trace(v, p);
  
  dynamic public function onError(e:Error, t:Task, w:Worker, stack:Array<StackItem>) {
    log(t);
    log('\nError on worker $w:\n${CallStack.toString(stack)}\n');
    kill();
    throw e;
  }
  
  /**
   * Delegates a task to a worker.
   * The resulting future is dispatched onto the runloop's thread.
   */
  public function delegate<A>(task:Lazy<A>, slave:Worker):Future<A> {
    var t = Future.trigger();
    
    var callback = bind(t.trigger);
    
    slave.work(
      function () callback.invoke(task.get())
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