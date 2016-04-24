#include <Timer.h>
#include <AM.h>
#include "messages.h"

module AppP {
	uses interface Boot;
	uses interface Timer < TMilli > as StartTimer;
	uses interface Timer < TMilli > as PeriodicTimer;
	uses interface Timer < TMilli > as JitterTimer;
	uses interface Random;
	 
	uses interface AMSend;
	uses interface Receive;
	uses interface tdma;
	uses interface AMPacket;
}
implementation {
#define IMI (1024L)
#define SECOND 32768L
#define JITTER (512L)
#define IS_MASTER (TOS_NODE_ID==1)

	uint16_t DataCnt = 1; // a simple counter to make fake data
	message_t message;
	event void Boot.booted() {
		if (IS_MASTER)
			call tdma.init();
		else{
			call StartTimer.startOneShot(10 * 1024);
		}
	}

	event void StartTimer.fired() {
		if (!IS_MASTER) {
			call PeriodicTimer.startPeriodic(IMI);
		}
	}

	event void PeriodicTimer.fired() {
		call JitterTimer.startOneShot(call Random.rand16() % JITTER);
	}

	event void JitterTimer.fired() {
		DataMsg *m = call AMSend.getPayload(&message, sizeof(DataMsg));
		m->data = DataCnt;
		//I don't use flag for data senging, just periodically send data, because only if 
		//this node receives Ack from master then I update DataCnt, otherwise just repeatly
		// send the same data
		call AMSend.send(1, &message, sizeof(DataMsg));
	}

	event void AMSend.sendDone(message_t * msg, error_t err) {
		//only if data is successfully sent, we update data counter
		if (err == SUCCESS) {
			printf("Data is successfully sent by App\n");
			DataCnt ++;
		}
	}

	event message_t *Receive.receive(message_t * msg, void *payload, uint8_t length) {
		am_addr_t from = call AMPacket.source(msg);
		DataMsg *m = (DataMsg*) payload;
		printf("Sink receives data %d from node %d\n", m->data, from);
		return msg;
	}

}
