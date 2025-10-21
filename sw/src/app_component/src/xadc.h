#ifndef __XADC_H__
#define __XADC_H__

#include <xstatus.h>
#include "xsysmon.h"

/* Globals */

static XSysMon Xadc;
static const uint32_t Xadc_NumChannels = 4;
static const uint32_t Xadc_Channels[4] = {
	XSM_CH_TEMP,
	XSM_CH_VCCINT,
	XSM_CH_VCCAUX,
	XSM_CH_VBRAM
};

/* Forward Declarations */

int XadcInitialize(uint32_t BaseAddress);
int Xadc_ReadData (uint16_t Data[Xadc_NumChannels]);
int XadcPrint();

#endif