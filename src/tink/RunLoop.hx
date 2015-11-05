package tink;

import haxe.CallStack;
import haxe.Timer;
import tink.concurrent.*;
import tink.runloop.*;
import tink.runloop.WorkResult;

using tink.CoreApi;

class RunLoop extends QueueWorker {
  public var retainCount(default, null):Int = 0;
  var slaves:Array<Worker>;
  
  static public var current(default, null):RunLoop;
  
  public function burst(time:Float) {
    var limit = Timer.stamp() + time;
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
  
  static function create(init:Void->Void) {
    var r = new RunLoop();
    
    current = r;
    
    r.execute(init);
    
    #if flash
      flash.Boot.getTrace().selectable = true;
      flash.Lib.current.stage.addEventListener(flash.events.Event.ENTER_FRAME, function (_) { 
        r.burst(.01);
      });
    #elseif js
      var t = new Timer(10);
      t.run = 
        @do switch r.burst(.001) {
          case Done | Aborted: 
            t.stop();
          default:
        }
    #else
      while (true) 
        switch r.step() {
          case Done | Aborted: break;
          default:
        }
    #end
  }
  
  function new(id = 'root_loop') {
    slaves = [];
    super(this, id);
  }
  
  override function log(v:Dynamic, ?p)
    haxe.Log.trace(v, p);
  
  dynamic public function onError(e:Error, t:Task, w:Worker, stack:Array<StackItem>) {
    log(t);
    log('\nError on worker $w:\n${CallStack.toString(stack)}\n');
    throw e;
  }
  
  public function delegate<A>(task:Lazy<A>, slave:Worker):Future<A> {
    var t = Future.trigger();
    
    var callback = bind(t.trigger);
    
    slave.work(
      function () callback.invoke(task.get())
    );
    
    return t.asFuture();
  }
  
  public function tryDelegate<A>(unsafe:Lazy<A>, slave:Worker, report:Dynamic->Error):Surprise<A, Error>
    return delegate((function () return unsafe.get()).catchExceptions(report), slave);
  
  public function retain() {
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
          if (this.retainCount == 0) Done;
          else 
            #if concurrent
              super.doStep();
            #else
              runSlaves();
            #end
        case v: 
          execute(v);
      }
  
  public function createSlave():Worker {
    var w = new QueueWorker(this, 'worker#' + this.slaves.length);
    this.slaves.push(w);
    #if concurrent
      new Thread(function () {
        w.thread = Thread.current;
        while (true) w.step();
      });
    #end
    return w;
  }
  
}