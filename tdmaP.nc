#include <Timer.h>
#include "messages.h"
#include <printf.h>

module tdmaP {
	uses { 
		interface Boot;
		interface Leds;
		interface Timer<T32khz> as TimerBeaconTx;
		interface Timer<T32khz> as TimerOn;
		interface Timer<T32khz> as TimerOff;
		interface Timer<T32khz> as TimerSendJoinReq;
		interface Timer<T32khz> as TimerTurnoffRadio;
		interface Timer<T32khz> as TimerData;

    	interface TimeSyncAMSend<T32khz, uint32_t> as SendBeacon;
        interface TimeSyncPacket<T32khz, uint32_t> as TSPacket;
    	interface Receive as ReceiveBeacon;
		interface SplitControl as AMControl;
		interface AMPacket;
		interface Random;

		interface AMSend as SendJoinReq;
		interface Receive as ReceiveJoinReq;
		interface AMSend as SendReplyJoin;
		interface Receive as ReceiveReplyJoin;
		interface AMSend as SendData;
		interface Receive as ReceiveData;
		interface AMSend as SendAck;
		interface Receive as ReceiveAck;
	}
	provides{
		interface AMSend;
		interface Receive;
		interface tdma;
	}
}
implementation {

#define SECOND 32768L
#define EPOCH_DURATION (SECOND*2)
#define IS_MASTER (TOS_NODE_ID==1)
#define SLOT_DURATION (SECOND/8)
#define ON_DURATION (SECOND/16)
#define N_BLINKS 16
#define JITTER  (TOS_NODE_ID*256L)
#define SENDDATADELAY 1024L  //send data delay to let radio start done
	
	uint32_t epoch_reference_time;
	
	// When to turn on the led the next time.
	// Relative to the epoch_reference_time
	uint32_t next_on;  
	
	int slot;	// current slot number
	int epoch = 0;	// current epoch number
	int reqNode;  //Node who sends join request

	int array[N_BLINKS] = {0};  //record all slots assignment
	int slotAssignCounter = 2; // slot assignment counter for Master
	int mySlot;  // record slave's assigned slot


	message_t beacon;
	message_t JoinReqOutput;
	message_t ReplyJoinReqOutput;
	message_t * DataOutput;
	message_t AckOutput;


	bool GetSlotFlag = FALSE;
	bool GetBeaconFlag = FALSE;
	bool GetAckFlag = FALSE;
	bool DataReadyFlag = FALSE;

	bool SendingJoinReqFlag = FALSE;
	bool SendingReplyJoinFlag = FALSE;
	bool SendingDataFlag = FALSE;
	bool SendingAckFlag = FALSE;

	void start_epochs();
	void ReplyJoinReq(int Node);
	void JoinReq();
	void sendAck(int n, bool flag);
	void sendData();
	
/***********************************To provide standard AMSend and Receive*****************************************/
	command error_t AMSend.cancel(message_t *msg){
		return call SendData.cancel(msg);
	}

	command void *AMSend.getPayload(message_t *msg, uint8_t len){
		return call SendData.getPayload(msg, len);
	}

	command uint8_t AMSend.maxPayloadLength(){
		return call SendData.maxPayloadLength();
	}

	command error_t AMSend.send(am_addr_t addr, message_t *msg, uint8_t len){
		DataOutput = msg;
		DataReadyFlag = TRUE;
		return SUCCESS;
	}

	command void tdma.init(){
		if(IS_MASTER){
			call TimerBeaconTx.startOneShot(3*SECOND);
		}
	}
/*****************************************System common event and functions***************************************/
	event void Boot.booted() {
		// turn on the radio
		call AMControl.start();
	}

	event void AMControl.startDone(error_t err) {
		
	}

	event void TimerBeaconTx.fired() {
		//only if the epoch is 0 we need to enter Start_epoch() function
		if(epoch == 0){
			//first time, initializing the reference time to now
			epoch_reference_time = call TimerBeaconTx.getNow();
			call SendBeacon.send(AM_BROADCAST_ADDR, &beacon, sizeof(BeaconMsg), epoch_reference_time);
			start_epochs();
		} else {
			call SendBeacon.send(AM_BROADCAST_ADDR, &beacon, sizeof(BeaconMsg), epoch_reference_time);
		}
	}
	
	event message_t* ReceiveBeacon.receive(message_t* msg, void* payload, uint8_t len){
		if(!IS_MASTER && !GetBeaconFlag){
			// we have to check whether the packet is valid before retrieving the reference time
			if (call TSPacket.isValid(msg) && len == sizeof(BeaconMsg)) {
				// get the epoch start time (converted to our local time reference frame)
				epoch_reference_time = call TSPacket.eventTime(msg);//- 98664L; 
				/*Here I wanted to fix the time difference between master and slave after sync by -98664L, but it
				caused Cooja crash, so I didn't change it but change the way in which I do test. BTW, it works fine
				in tdma module test without adding app layer*/
				GetBeaconFlag = TRUE;
				start_epochs();
			}
			return msg;
		} else {
			return msg;
		}	
	}

	// initialise and start the first epoch
	void start_epochs() {
		epoch = 1;
		slot = 0;
		next_on = EPOCH_DURATION;
		// setting a timer to turn on the leds
		call TimerOn.startOneShotAt(epoch_reference_time, EPOCH_DURATION);
	}

	// compute the next_on time, update the reference if needed
	void compute_next_slot() {
		if (slot == 0){
			// new epoch started, now we can update the reference time 
			epoch_reference_time += EPOCH_DURATION;
			
		}
		if (slot < N_BLINKS-1) {
			// proceed to the next slot
			slot++;
			// compute the relative led on time based on the slot number
			next_on = slot*SLOT_DURATION;
		}
		else {
			// it was the last slot of the epoch, prepare for the next epoch
			slot = 0;
			epoch ++;
			// next time to turn on the leds is exactly the start of the next epoch
			next_on = EPOCH_DURATION;
			// note that we cannot update the epoch_reference_time now as
			// it would point to the future and we cannot use a reference
			// in the future when setting the timers!
			if(IS_MASTER){
				int i;
				for(i=0; i<slotAssignCounter; i++){
					printf("array[%d] is %d \n", i, array[i]);
				}
			}
		}
	}

/***********************************Master events and functions*****************************************/
	event message_t* ReceiveJoinReq.receive(message_t* msg, void* payload, uint8_t len){
		//make sure it is Node 1
		if (IS_MASTER && len == sizeof(JoinReqMsg)) {
			reqNode = call AMPacket.source(msg);
			ReplyJoinReq(reqNode);
		}
		return msg;
	}
	//master replies to nodes and send assigned slots
	void ReplyJoinReq(int Node){

		if(slotAssignCounter >= N_BLINKS){
			printf("Error: No more slots can be assigned\n");
			printf("slotAssignCounter is %d\n", slotAssignCounter);
			return;
		} else {

			if(!SendingReplyJoinFlag){
				error_t err;
				int i;
				bool AssignedFlag = FALSE;
				ReplyJoinReqMsg* m = call SendReplyJoin.getPayload(&ReplyJoinReqOutput, sizeof(ReplyJoinReqMsg));
				//check if this node has been assigned
				for(i= 0; i<=slotAssignCounter-1; i++){
					if(array[i] == Node){
						AssignedFlag = TRUE;
						break;
					}
				}
				//if this node has been assigned, resend the result to it, otherwise assign an new slot
				if(AssignedFlag){
					m->slotnum = array[i];
				}else{
					slotAssignCounter ++;
					m->slotnum = slotAssignCounter-1;
				}
				//send the slot to the required node, and update the record table				
				err = call SendReplyJoin.send(Node, &ReplyJoinReqOutput, sizeof(ReplyJoinReqMsg));
				if(err == SUCCESS){
					printf("Master assigned slot %d to Node %d \n", m->slotnum, Node);
					SendingReplyJoinFlag = TRUE;
					array[slotAssignCounter-1] = Node;
					return;
				} else {
					// could not send successfully, reduce counter
					slotAssignCounter --;
					SendingReplyJoinFlag = FALSE;
					return;
				}
			}
		}
	}

	event message_t* ReceiveData.receive(message_t* msg, void* payload, uint8_t len){
		// make sure only master receives data and data message is correct
		if (IS_MASTER && len == sizeof(DataMsg)) {
			bool isLastNodeFlag = FALSE;
			int node = call AMPacket.source(msg);
			DataMsg * m = (DataMsg *) payload;
			printf("Master received data %d from node %d \n", m->data, node);
			//return to app level
			signal Receive.receive(msg, payload, len);
			// check if it's the last node and set flag, we need it to help turn off master's radio
			if(array[slotAssignCounter-1] == node){
				isLastNodeFlag = TRUE;
			}
			sendAck(node, isLastNodeFlag);
		}

		return msg;
	}

	void sendAck(int n, bool flag){
		error_t err;
		AckMsg *m = call SendAck.getPayload(&AckOutput, sizeof(AckMsg));
		m->ack = n*10;
		if(!SendingAckFlag){
			err = call SendAck.send(n, &AckOutput, sizeof(AckMsg));	
			//anyway, after sending ack to last node, just turn off radio
			if(flag)
				call AMControl.stop();
			if (err == SUCCESS){
				printf("Master sent ack to Node %d\n", n);
				SendingAckFlag = TRUE;
				return;
			}else {
				printf("Master failed to sent ack to Node %d\n", n);
				SendingAckFlag = FALSE;
				return;				
			}	
		}
		
	}
/***********************************Slaves functions*****************************************/
    //this function sends join request to master
	void JoinReq(){
		if(!SendingJoinReqFlag){
			error_t err;
			err = call SendJoinReq.send(1, &JoinReqOutput, sizeof(JoinReqMsg));
			if(err == SUCCESS){
				printf("Node %d sent Join request\n", TOS_NODE_ID);
				SendingJoinReqFlag = TRUE;
				return;
			} else {
				printf("Node %d failed to send join request\n", TOS_NODE_ID);
				SendingJoinReqFlag = FALSE;
				return;
			}
		}
	}
	// this function sends data to master
	void sendData(){
		error_t err;
		// DataMsg *m = call SendData.getPayload(DataOutput, sizeof(DataMsg));
		// m->data = TOS_NODE_ID;
		/*if I only test with tdma module, I will use the two lines above to generate data*/

		err = call SendData.send(1, DataOutput, sizeof(DataMsg));
		DataReadyFlag = FALSE;
		if(err == SUCCESS){
			printf("Node %d succeeds to send data\n", TOS_NODE_ID);
			SendingDataFlag = TRUE;
			return;
		} else {
			printf("Node %d fails to send data\n", TOS_NODE_ID);
			SendingDataFlag = FALSE;
			return;
		}
	}

	event void TimerOn.fired() {
		call Leds.set(epoch);
		// set the off timer usting the current values of reference and next_on
		call TimerOff.startOneShotAt(epoch_reference_time, next_on + ON_DURATION);

		//slaves send join slot request or send data
		if(!IS_MASTER){
			//check if it has assigned slot
			if(!GetSlotFlag){
				
				if(slot == 1){
					// call TimerSendJoinReq.startOneShotAt(epoch_reference_time+SLOT_DURATION,(call Random.rand16() % JITTER));
					call TimerSendJoinReq.startOneShotAt(epoch_reference_time+SLOT_DURATION, JITTER);
				}
			} else {
				// if it has an assigned slot and it is this slot, send data
				if(slot == mySlot){
					if(DataReadyFlag){
						printf("data ready!\n");
						call AMControl.start();
						//delay send data to wait for radio ready
						call TimerData.startOneShot(SENDDATADELAY);
						//set timer to turn off radio in case sendind data fails
						call TimerTurnoffRadio.startOneShotAt(epoch_reference_time,  (mySlot+1)*SLOT_DURATION);
					}else{
						printf("data is not ready!\n");
					}
				}
			}
		}
		//master sends beacons
		if(IS_MASTER){
			if(slot == 0){
				//in first slot, master prepares to send beacon
				call AMControl.start();
				//send new beacon for next epoch
				call TimerBeaconTx.startOneShot(SENDDATADELAY);

			}
			//just make sure master will turn off radio even it could not receive data
			//so it will not enter sending ack to turn off radio, we turn off it here
			if(slot == slotAssignCounter){
				call AMControl.stop();
			}
		}
		// update the values
			printf("epoch is %d, slot is %d \n", epoch, slot);
			compute_next_slot();
		// set on timer useing the new values
		call TimerOn.startOneShotAt(epoch_reference_time, next_on);
	}

	event void TimerData.fired(){
		sendData();
	}

	event  void TimerTurnoffRadio.fired(){
		call AMControl.stop();
	}

	event void TimerSendJoinReq.fired(){
		JoinReq();
	}
	
	event void TimerOff.fired() {
		call Leds.set(0);
	}
	
	event message_t* ReceiveReplyJoin.receive(message_t* msg, void* payload, uint8_t len){
		
		
		if (!IS_MASTER && len == sizeof(ReplyJoinReqMsg)) {
			ReplyJoinReqMsg * m = (ReplyJoinReqMsg *) payload;
			mySlot = m->slotnum;
			printf("Node %d received its slot %d \n", TOS_NODE_ID, mySlot);
			GetSlotFlag = TRUE;
			if(GetSlotFlag)
				printf("GetSlotFlag is true \n");
			call AMControl.stop();
		} else {
			printf("Node %d cannot get slot\n", TOS_NODE_ID);
		}
		return msg;
	}

	event message_t* ReceiveAck.receive(message_t* msg, void* payload, uint8_t len){
		
		
		if (!IS_MASTER && len == sizeof(AckMsg)) {
			AckMsg * m = (AckMsg *) payload;
			printf("Node %d received its Ack msg %d\n", TOS_NODE_ID, m->ack);
			//check if ack info is correct
			if(m->ack == TOS_NODE_ID * 10){
				// update getack flag
				GetAckFlag = TRUE;
				// here we tell app the data is sent done because we received the ack
				signal AMSend.sendDone(DataOutput, SUCCESS);
				call AMControl.stop();
			}else {
				//ack is not correct, retry to send data again
				printf("Node %d received wrong Ack info!\n", TOS_NODE_ID);
				
			}	
		} else {
			//ack size is not correct, retry to send data again
			printf("Node %d received wrong Ack size!\n", TOS_NODE_ID);
			
		}
		return msg;
	}
/******************************************Below are sendDone & stopDone event**************************************************/
	event void SendBeacon.sendDone(message_t* msg, error_t err) {
		// call AMControl.stop();
	}
	
	event void SendJoinReq.sendDone(message_t* msg, error_t err) {
		if(err != SUCCESS) {
			printf("Node %d failed to sendDone join request!\n", TOS_NODE_ID);
		}
		SendingJoinReqFlag = FALSE;
	}

	event void SendReplyJoin.sendDone(message_t* msg, error_t err){
		if(err != SUCCESS) {
			printf("Master failed to sendDone assigned slot!\n");
			slotAssignCounter --;
		}
		SendingReplyJoinFlag = FALSE;
	}

	event void SendData.sendDone(message_t* msg, error_t err){
		if(err != SUCCESS) {
			printf("Node %d failed to sendDone data!\n", TOS_NODE_ID);
		}
		SendingDataFlag = FALSE;
		//signal AMSend.sendDone(msg, err);
	}
	event void SendAck.sendDone(message_t* msg, error_t err){
		if(err != SUCCESS) {
			printf("Master failed to sendDone ack!\n");
		}
		SendingAckFlag = FALSE;
	}
	event void AMControl.stopDone(error_t err) {}
}
