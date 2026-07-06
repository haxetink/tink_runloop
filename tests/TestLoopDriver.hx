package;

import tink.RunLoop;
import tink.runloop.LoopDriver;

using tink.CoreApi;

@:asserts
class TestLoopDriver {
  public function new() {}

  public function driver() {
    var mock = new MockDriver();

    asserts.assert(LoopDriver.current != null);
    LoopDriver.set(mock);
    asserts.assert(LoopDriver.current == mock);

    // `RunLoop.current` is already spinning (Boot wraps `main` in `RunLoop.create`).
    // Its outer `spin()` only reaches its own `LoopDriver.current.schedule()` call once
    // *all* synchronous test code - including this method - has returned. Deferring past
    // that point lets us observe (and drive) the real hookup through our mock.
    haxe.Timer.delay(function () {
      asserts.assert(mock.scheduleCount == 1);
      asserts.assert(RunLoop.current.running);

      // Drain the (already idle) queue through the captured tick, as a driver would.
      while (mock.tick()) {}
      asserts.assert(!RunLoop.current.running);

      var ran = false;
      RunLoop.current.work(function () ran = true);

      // Scheduling work after `Done` must wake the loop back up.
      asserts.assert(mock.scheduleCount == 2);
      asserts.assert(RunLoop.current.running);

      mock.tick();
      asserts.assert(ran);

      LoopDriver.reset();
      asserts.done();
    }, 0);

    return asserts;
  }
}

private class MockDriver implements LoopDriverObject {
  public var scheduleCount = 0;
  public var tick:LoopTick;

  public function new() {}

  public function schedule(onTick:LoopTick):CallbackLink {
    scheduleCount++;
    tick = onTick;
    return null;
  }
}
