package tink.runloop.drivers;

import tink.runloop.LoopDriver;

using tink.CoreApi;

/**
 * Drives the loop from a Lime-only application's update event (no OpenFL), once per frame.
 *
 * Requires an active `lime.app.Application`. Since a typical Lime project blocks inside
 * `Application.exec()` before ever returning, compile with `-D tink_runloop_no_boot` and call
 * `RunLoop.current.enter(...)` yourself once the application has been created.
 */
class Lime implements LoopDriverObject {
  public function new() {}

  public function schedule(onTick:LoopTick):CallbackLink {
    var app = lime.app.Application.current;
    if (app == null)
      throw 'tink_runloop: no active lime.app.Application to hook into. Compile with -D tink_runloop_no_boot '
        + 'and call RunLoop.current.enter() after creating your Application.';

    var listener = null;
    listener = function (_)
      if (!onTick())
        app.onUpdate.remove(listener);
    app.onUpdate.add(listener);
    return function () app.onUpdate.remove(listener);
  }
}
