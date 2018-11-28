package;

import tink.RunLoop;
import tink.runloop.WorkResult;

@:asserts
class TestPriorities {
  public function new() {}
  public function test() {
    var i = 0;
    function inc() i++;
    function dec() i--;
    RunLoop.current.asap(inc);
    asserts.assert(i == 1);
    RunLoop.current.asap(inc);
    asserts.assert(i == 2);
    RunLoop.current.atNextStep(inc);
    asserts.assert(i == 2);
    RunLoop.current.step();
    asserts.assert(i == 3);
    
    for (i in 0...100)
      RunLoop.current.work(inc);
      
    for (i in 0...3)
      RunLoop.current.atNextStep(dec);
      
    asserts.assert(i == 3);
    
    for (i in 0...3)
      RunLoop.current.step();
      
    asserts.assert(i == 0);
    
    var called = false;
    RunLoop.current.done.handle(function () called = true);
    asserts.assert(!called);
    
    for (i in 0...100) 
      asserts.assert(RunLoop.current.step() == Progressed);
    
    asserts.assert(RunLoop.current.step() == Done);
    asserts.assert(called);
    asserts.assert(i == 100);
    
    return asserts.done();
  }
  
}