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
   * 
   */
	WrongThread;
}