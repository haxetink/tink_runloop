package tink.runloop;

#if macro
class Boot {
  static function boot() {
    tink.SyntaxHub.transformMain.whenever(function (e) { 
      return macro @:pos(e.pos) @:privateAccess tink.RunLoop.create(function () $e);
    });
  }
}
#else 
  #error
#end