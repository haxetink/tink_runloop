package tink.runloop.drivers;

import tink.runloop.LoopDriver;

using tink.CoreApi;

/**
 * Drives the loop on Node.js using `setImmediate`, which integrates with libuv's
 * check phase instead of polling via `haxe.Timer(0)`.
 */
class Node implements LoopDriverObject {
  public function new() {}

  public function schedule(onTick:LoopTick):CallbackLink {
    var immediate = null;
    function tick()
      if (onTick())
        immediate = js.node.Timers.setImmediate(tick);
    immediate = js.node.Timers.setImmediate(tick);
    return function ()
      if (immediate != null)
        js.node.Timers.clearImmediate(immediate);
  }
}
