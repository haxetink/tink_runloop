package tink.runloop;

import tink.concurrent.Mutex;

/**
 * Represents a task to be run by a `Worker`.
 * 
 * For common use cases, you can just rely on the fact that any `Void->Void` as well as `Void->TaskRepeat` is autocast to `Task`.
 * If performance becomes an issue, you can implement your own `TaskObject` instead.
 * Unless you have *very good* reasons not to, extending `TaskBase` is the suggested way to do it.
 * 
 * You can also use `Task.ofFunction` to create a `Task` that can be passed around while ensuring the underlying function is called only once.
 */
@:forward
abstract Task(TaskObject) from TaskObject to TaskObject {
  
  @:from static public function ofFunction(f:Void->Void):Task 
    return new FunctionTask(f);
    
  @:from static public function repeat(f:Void->TaskRepeat):Task 
    return new RepeatableFunctionTask(f);
    
  static public var NOOP(default, null):Task = new Noop();
}

enum TaskRepeat {
  Continue;
  Done;
}

interface TaskObject {
  //TODO: evaluate merging this with CallbackLink
  var recurring(get, never):Bool;
  var state(get, never):TaskState;
  
  function cancel():Void;  
  function perform():Void;
}

private class Noop implements TaskObject {
  public function new() { }
  
  public var recurring(get, never):Bool;
  
    inline function get_recurring() return false;
    
  public var state(get, never):TaskState;
  
    inline function get_state() return Performed;
  
  public function cancel():Void {}
  public function perform():Void {}  
}

enum TaskState {
  Pending;
  Canceled;
  Busy;
  Performed;
}

class TaskBase implements TaskObject {
  /**
   * Locks are generally not the best idea. Given the intended life cycle of a task,
   * this should not be an issue. Since the `perform` or `cancel` method of a single `Task` are 
   * highly unlikely to be invoked heavily, there is no danger of a life lock.
   */
  var m:Mutex;
  
  public var recurring(get, null):Bool;
  
    inline function get_recurring() return recurring;
  
  public var state(get, null):TaskState;
  
    inline function get_state() return state;
  
  public function cancel():Void 
    exec(function () {
      state = Canceled;
      doCancel();
      doCleanup();
    });
  
  function exec(f) {
    if (!m.tryAcquire()) return;
    
    if (state == Pending) 
      try f()
      catch (e:Dynamic) {
        m.release();
        tink.core.Error.rethrow(e);
      }
    
    m.release();
  }
  
  public function perform():Void 
    exec(function () {
      state = Busy;
      doPerform();  
      if (recurring) 
        state = Pending;
      else {
        state = Performed;
        doCleanup();
      }
    });
  
  function new(?recurring = false) {
    this.recurring = recurring;
    state = Pending;
    m = new Mutex();
  }
    
  function doCleanup() {}
  function doCancel() {}
  function doPerform() {}
  
}

class FunctionTask extends TaskBase {
  var f:Void->Void;
  
  public function new(f) {
    super();
    this.f = f;
  }
  
  override function doCleanup()
    this.f = null;
    
  override function doPerform()
    f();
}

class RepeatableFunctionTask extends TaskBase {
  var f:Void->TaskRepeat;
  
  public function new(f) {
    super();
    this.f = f;
  }
  
  override function doCleanup()
    this.f = null;
    
  override function doPerform()
    this.recurring = f() == Continue;
}