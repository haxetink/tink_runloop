package tink.runloop;

enum WorkResult {
	Progressed;
	Waiting(seconds:Float);
  /**
   * 
   */
	Idle;
  /**
   * 
   */
	Done;
  /**
   * 
   */
	Aborted;
  /**
   * Returned when attempting to cause a worker step from the wrong thread.
   */
	WrongThread;
}