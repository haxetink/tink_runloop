package tink.runloop;

#if macro
class Boot {
  static function boot() {
    // Apps that hook into a host's own entry point (e.g. OpenFL/Lime, which block inside
    // `Application.exec()`) should compile with -D tink_runloop_no_boot and instead call
    // `RunLoop.current.enter(...)` themselves once their application has been created.
    #if !tink_runloop_no_boot
    tink.SyntaxHub.transformMain.whenever(function (e) { 
      return macro @:pos(e.pos) @:privateAccess tink.RunLoop.create(function () $e);
    });
    #end
  }
}
#else 
  #error
#end