package;

import haxe.unit.TestCase;
import tink.RunLoop;
import tink.runloop.WorkResult;

class TestPriorities extends TestCase {

  function test() {
    var i = 0;
    function inc() i++;
    function dec() i--;
    RunLoop.current.asap(inc);
    assertEquals(1, i);
    RunLoop.current.asap(inc);
    assertEquals(2, i);
    RunLoop.current.atNextStep(inc);
    assertEquals(2, i);
    RunLoop.current.step();
    assertEquals(3, i);
    
    for (i in 0...100)
      RunLoop.current.work(inc);
      
    for (i in 0...3)
      RunLoop.current.atNextStep(dec);
      
    assertEquals(3, i);
    
    for (i in 0...3)
      RunLoop.current.step();
      
    assertEquals(0, i);
    
    var called = false;
    RunLoop.current.done.handle(function () called = true);
    assertFalse(called);
    
    for (i in 0...100) {
      trace(i);
      assertEquals(Progressed, RunLoop.current.step());
    }
    
    assertEquals(Done, RunLoop.current.step());
    assertTrue(called);
    assertEquals(100, i);
  }
  
}