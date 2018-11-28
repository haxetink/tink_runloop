package;

import haxe.Timer;
import tink.RunLoop;
import tink.runloop.WorkResult;

@:asserts
class TestTimer {
  public function new() {}
  public function delay() {
    var start = Timer.stamp();
    Timer.delay(function() {
      var now = Timer.stamp();
      var dt = now - start;
      asserts.assert(dt > 1.0);
      asserts.done();
    }, 1000);
    return asserts;
  }
  
}