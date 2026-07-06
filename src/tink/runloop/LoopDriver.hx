package tink.runloop;

using tink.CoreApi;

/**
 * A tick function driving the run loop forward.
 * Return `false` to indicate that no further ticks are needed.
 */
typedef LoopTick = Void->Bool;

/**
 * Hooks the run loop into a host's native event loop (browser, Node.js, OpenFL, Lime, ...).
 * Implement this to adapt tink_runloop to a new platform.
 */
interface LoopDriverObject {
  /**
   * Schedules `onTick` to be called repeatedly by the host loop.
   * The returned link can be `cancel()`-ed to tear down the hook (e.g. remove a listener or stop a timer),
   * regardless of whether `onTick` has since returned `false`.
   */
  function schedule(onTick:LoopTick):CallbackLink;
}

@:forward
abstract LoopDriver(LoopDriverObject) from LoopDriverObject to LoopDriverObject {

  static var _current:LoopDriver;

  /**
   * The driver used by `RunLoop.current`. Defaults to a platform appropriate driver,
   * lazily created on first access. Override with `set()` before the loop starts.
   */
  public static var current(get, never):LoopDriver;
    static function get_current():LoopDriver
      return switch _current {
        case null: _current = defaultDriver();
        case v: v;
      }

  /**
   * Overrides the driver used by `RunLoop.current`. Must be called before the loop is (re)entered
   * for it to take effect.
   */
  public static function set(driver:LoopDriver):Void
    _current = driver;

  /**
   * Restores the platform appropriate default driver.
   */
  public static function reset():Void
    _current = null;

  /**
   * Builds the platform appropriate driver, selected at compile time.
   */
  public static function defaultDriver():LoopDriver
    return
      #if tink_runloop_driver_blocking
        new tink.runloop.drivers.Blocking();
      #elseif openfl
        new tink.runloop.drivers.OpenFL();
      #elseif lime
        new tink.runloop.drivers.Lime();
      #elseif nodejs
        new tink.runloop.drivers.Node();
      #elseif js
        new tink.runloop.drivers.Browser();
      #else
        new tink.runloop.drivers.Blocking();
      #end
}
