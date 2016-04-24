#ifndef MESSAGES_H
#define MESSAGES_H

enum {
	AM_BEACONMSG = 130,
	AM_JOINREQMSG = 150,
	AM_REPLYSLOTMSG = 170,
	AM_DATAMSG = 190,
	AM_ACKMSG = 210,
};

typedef nx_struct BeaconMsg {
	nx_uint16_t seqn;
} BeaconMsg;

typedef nx_struct JoinReqMsg {
	nx_uint16_t seqn;
} JoinReqMsg;

typedef nx_struct ReplyJoinReqMsg {
	nx_uint16_t slotnum;
} ReplyJoinReqMsg;

typedef nx_struct DataMsg {
	nx_uint16_t data;
} DataMsg;

typedef nx_struct AckMsg {
	nx_uint16_t ack;
} AckMsg;
#endif
