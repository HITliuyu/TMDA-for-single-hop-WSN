
configuration AppC {
}
implementation {
	components tdmaC;

	components AppP;
	components SerialPrintfC, SerialStartC;
	components new TimerMilliC() as StartTimer;
	components new TimerMilliC() as PeriodicTimer;
	components new TimerMilliC() as JitterTimer;
	components MainC, RandomC;
	components ActiveMessageC;

	
	AppP.AMSend->tdmaC;
	AppP.tdma->tdmaC;
	AppP.Receive->tdmaC;
	AppP.AMPacket->ActiveMessageC;

	AppP.Boot->MainC;
	AppP.Random->RandomC;
	AppP.StartTimer->StartTimer;
	AppP.PeriodicTimer->PeriodicTimer;
	AppP.JitterTimer->JitterTimer;
}
