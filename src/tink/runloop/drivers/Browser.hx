package tink.runloop.drivers;

import tink.runloop.LoopDriver;

using tink.CoreApi;

/**
 * Drives the loop from a browser `js` host, preferring `requestAnimationFrame`
 * so idle time yields to the browser's paint cycle, and falling back to
 * `haxe.Timer(0)` where no `window` is available (workers, headless `js`).
 */
class Browser implements LoopDriverObject {
  public function new() {}

  public function schedule(onTick:LoopTick):CallbackLink {
    #if js
    if (hasWindow()) {
      var window = js.Browser.window;
      var id = 0;
      function frame(_)
        if (onTick())
          id = window.requestAnimationFrame(frame);
      id = window.requestAnimationFrame(frame);
      return function () window.cancelAnimationFrame(id);
    }
    #end

    var t = new haxe.Timer(0);
    t.run = function ()
      if (!onTick())
        t.stop();
    return t.stop;
  }

  #if js
  static function hasWindow():Bool
    return js.Lib.typeof(js.Browser.window) != 'undefined';
  #end
}
