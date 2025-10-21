#ifndef __FLASH_H__
#define __FLASH_H__

#include "xil_printf.h"
#include "xspi.h"
#include <xstatus.h>

/* Forward Declarations */

int SpiInitialize(XSpi *SpiPtr, uint32_t BaseAddr);
int SpiFlashGetStatus(XSpi *SpiPtr, uint8_t *StatusRegPtr);
int SpiFlashReadId(XSpi *SpiPtr, uint32_t* DevIdPtr);
int SpiFlashWaitForFlashReady(XSpi *SpiPtr);
int SpiFlashWriteEnable(XSpi *SpiPtr);
int SpiFlashWriteDisable(XSpi *SpiPtr);
int SpiFlashRead(XSpi *SpiPtr, uint8_t *WriteBuffer, uint8_t *ReadBuffer, uint32_t Addr, uint32_t ByteCount);
int SpiFlashQuadEnable(XSpi *SpiPtr);
uint32_t pickbit(uint32_t v, uint8_t bit);
void reverse(uint8_t buf[4]);
uint32_t LfsrNext(uint32_t lfsr);

int ValidateAgainstLfsr(XSpi *SpiPtr, const uint32_t seed, uint32_t *error_count, uint32_t *first_value_read, uint32_t *last_value_read);

void SpiHandler(void *CallBackRef, u32 StatusEvent, unsigned int ByteCount);
static int SetupInterruptSystem(XSpi *SpiPtr);

#endif