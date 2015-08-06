package tink.runloop;

interface Worker {
	var id(get, never):String;
	var owner(get, never):RunLoop;
	
	function work(task:Task):Task;
	function asap(task:Task):Task;
	function atNextStep(task:Task):Task;
	
	/**
	 * Gives a worker the opportunity to progress.
	 */
	function step():WorkResult;
}