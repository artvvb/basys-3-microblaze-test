#include "xadc.h"

/* Function Definitions */

int XadcInitialize(uint32_t BaseAddress) {
	XSysMon_Config *cfgptr;
	XSysMon *InstancePtr = (&Xadc);
	uint32_t Status;

	#ifdef SDT
	cfgptr = XSysMon_LookupConfig(BaseAddress);
	#else
	cfgptr = XSysMon_LookupConfig(BaseAddress);
	#endif

	if (cfgptr == NULL) {
		xil_printf("cfgptr null\r\n");
		return XST_FAILURE;		
	}

	if (XSysMon_CfgInitialize(InstancePtr, cfgptr, cfgptr->BaseAddress) != XST_SUCCESS) {
		xil_printf("bad XSysMon_CfgInitialize\r\n");
        return XST_FAILURE;
    }
	
	XSysMon_SetSequencerMode(InstancePtr, XSM_SEQ_MODE_SAFE);
	XSysMon_SetAvg(InstancePtr, XSM_AVG_16_SAMPLES);
	
	Status =  XSysMon_SetSeqAvgEnables(InstancePtr, XSM_SEQ_CH_TEMP |
						XSM_SEQ_CH_VCCAUX |
						XSM_SEQ_CH_VCCINT |
						XSM_SEQ_CH_VBRAM);
	if (Status != XST_SUCCESS) {
		xil_printf("bad XSysMon_SetSeqAvgEnables\r\n");
		return XST_FAILURE;
	}

	Status =  XSysMon_SetSeqChEnables(InstancePtr, XSM_SEQ_CH_TEMP |
						XSM_SEQ_CH_VCCAUX |
						XSM_SEQ_CH_VCCINT |
						XSM_SEQ_CH_VBRAM);
	if (Status != XST_SUCCESS) {
		xil_printf("bad XSysMon_SetSeqChEnables\r\n");
		return XST_FAILURE;
	}

	XSysMon_SetAdcClkDivisor(InstancePtr, 32);
	XSysMon_SetSequencerMode(InstancePtr, XSM_SEQ_MODE_CONTINPASS);

	XSysMon_SetAlarmEnables(InstancePtr, 0x0);

    return XST_SUCCESS;
}

int Xadc_ReadData (uint16_t Data[Xadc_NumChannels])
{
	XSysMon *InstancePtr = (&Xadc);
	
	// Clear the Status
	XSysMon_GetStatus(InstancePtr);

	// Wait until the End of Sequence occurs
	while ((XSysMon_GetStatus(InstancePtr) & XSM_SR_EOS_MASK) != XSM_SR_EOS_MASK);

	for (uint8_t Channel = 0; Channel < Xadc_NumChannels; Channel++) {
		Data[Channel] = XSysMon_GetAdcData(InstancePtr, Xadc_Channels[Channel]);
	}
	// Value = XSysMon_GetMinMaxMeasurement(InstancePtr, XSM_MAX_VCCAUX);
	return XST_SUCCESS;
}

int XadcPrint() {
	uint16_t rawdata[32];
	uint32_t data;
	float fdata;

	if (Xadc_ReadData(rawdata) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	for (uint32_t Channel = 0; Channel < Xadc_NumChannels; Channel++) {
		data = rawdata[Channel] >> 4;
		if (Xadc_Channels[Channel] == XSM_CH_TEMP) {
			fdata = ((float)data * 503.975) / 4096 - 273.15;
			xil_printf("Temp: %d.%03d degrees C\t(raw: 0x%03x)\r\n", (int)fdata, (int)(fdata*1000)%1000, data);
		} else if (Xadc_Channels[Channel] == XSM_CH_VCCINT) {
			fdata = ((float)data / 4096) * 3.0;
			xil_printf("VCCINT: %d.%03d V\t(raw: 0x%03x)\r\n", (int)fdata, (int)(fdata*1000)%1000, data);
		} else if (Xadc_Channels[Channel] == XSM_CH_VCCAUX) {
			fdata = ((float)data / 4096) * 3.0;
			xil_printf("VCCAUX: %d.%03d V\t(raw: 0x%03x)\r\n", (int)fdata, (int)(fdata*1000)%1000, data);
		} else if (Xadc_Channels[Channel] == XSM_CH_VBRAM) {
			fdata = ((float)data / 4096) * 3.0;
			xil_printf("VBRAM: %d.%03d V\t(raw: 0x%03x)\r\n", (int)fdata, (int)(fdata*1000)%1000, data);
		} else {
			xil_printf("V(%d) raw: 0x%03x\r\n", Xadc_Channels[Channel], data);
		}
	}
	return XST_SUCCESS;
}