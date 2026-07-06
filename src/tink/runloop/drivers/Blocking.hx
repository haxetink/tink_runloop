package tink.runloop.drivers;

import tink.runloop.LoopDriver;

using tink.CoreApi;

/**
 * Drives the loop with a tight, blocking `while` loop on the calling thread.
 * Used for standalone targets without a native host loop (cpp, neko, python, php, jvm, interp).
 */
class Blocking implements LoopDriverObject {
  public function new() {}

  public function schedule(onTick:LoopTick):CallbackLink {
    while (onTick()) {}
    return null;
  }
}
