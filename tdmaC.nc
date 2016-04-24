#include <Timer.h>
#include "messages.h"
#include <printf.h>
configuration tdmaC {
	provides{
		interface AMSend;
		interface Receive;
		interface tdma;
	}
}
implementation {
	components tdmaP as AppP, MainC, LedsC;
	components new Timer32C() as TimerBeaconTx;
	components new Timer32C() as TimerOff;
	components new Timer32C() as TimerOn;
	components new Timer32C() as TimerSendJoinReq;
	components new Timer32C() as TimerTurnoffRadio;
	components new Timer32C() as TimerData;
	components CC2420TimeSyncMessageC as TSAM;
	components CC2420ActiveMessageC;
	components ActiveMessageC;
	components RandomC;

	components SerialPrintfC, SerialStartC;

	components new AMSenderC(AM_JOINREQMSG) as SendJoinReq;
	components new AMReceiverC(AM_JOINREQMSG) as ReceiveJoinReq;
	
	components new AMSenderC(AM_REPLYSLOTMSG) as SendReplyJoin;
	components new AMReceiverC(AM_REPLYSLOTMSG) as ReceiveReplyJoin;
    
    components new AMSenderC(AM_DATAMSG) as SendData;
	components new AMReceiverC(AM_DATAMSG) as ReceiveData;

	components new AMSenderC(AM_ACKMSG) as SendAck;
	components new AMReceiverC(AM_ACKMSG) as ReceiveAck;



	AppP.AMSend = AMSend;
	AppP.Receive = Receive;
	AppP.tdma = tdma;

	AppP.TSPacket -> TSAM.TimeSyncPacket32khz;
	AppP.SendBeacon -> TSAM.TimeSyncAMSend32khz[AM_BEACONMSG]; // wire to the beacon AM type
	AppP.ReceiveBeacon -> TSAM.Receive[AM_BEACONMSG];
	
	AppP.Leds -> LedsC;
	AppP.Boot -> MainC;
	AppP.TimerBeaconTx -> TimerBeaconTx;
	AppP.TimerOff -> TimerOff;
	AppP.TimerOn -> TimerOn;
	AppP.TimerSendJoinReq -> TimerSendJoinReq;
	AppP.TimerTurnoffRadio -> TimerTurnoffRadio;
	AppP.TimerData -> TimerData;

	AppP.AMControl -> ActiveMessageC;
	AppP.AMPacket -> ActiveMessageC;
	AppP.Random -> RandomC;

	AppP.SendJoinReq -> SendJoinReq;
	AppP.ReceiveJoinReq -> ReceiveJoinReq;
	AppP.SendReplyJoin -> SendReplyJoin;
	AppP.ReceiveReplyJoin -> ReceiveReplyJoin;
	AppP.SendData -> SendData;
	AppP.ReceiveData -> ReceiveData;
	AppP.SendAck -> SendAck;
	AppP.ReceiveAck -> ReceiveAck;
}
