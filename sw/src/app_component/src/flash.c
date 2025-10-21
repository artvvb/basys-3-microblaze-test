#include "flash.h"
#include "xil_printf.h"
#include <xstatus.h>

#define READ_WRITE_EXTRA_BYTES	8 /* Quad read extra bytes */
#define STATUS_READ_BYTES		2 /* Status read bytes count */
#define READ_ID_BYTES			4 /* Status read bytes count */
#define PAGE_SIZE				256

#define	COMMAND_WRITE_ENABLE	0x06 /* Write Enable */
#define	COMMAND_WRITE_DISABLE	0x04 /* Write Disable */
#define COMMAND_WRITE_STATUS	0x01 /* Write Status Reg */
#define COMMAND_READ_ID			0x9F /* Read Device ID */
#define COMMAND_QUAD_READ		0x6B /* Quad Fast Read */
#define COMMAND_STATUSREG_READ	0x05 /* Status Read */

#define FLASH_SR_QE_MASK		0x40 /* Quad Enable = 1 */
#define FLASH_SR_IS_READY_MASK	0x01 /* Ready mask */

#define	WRITE_ENABLE_BYTES		1 /* Write Enable bytes */
#define	WRITE_DISABLE_BYTES		1 /* Write Disable bytes */

/* Function Definitions */

int SpiInitialize(XSpi *SpiPtr, uint32_t BaseAddr)
{
    XSpi_Config *cfgptr;
    cfgptr = XSpi_LookupConfig(BaseAddr);
    
    if (XSpi_CfgInitialize(SpiPtr, cfgptr, cfgptr->BaseAddress) != XST_SUCCESS) {
        xil_printf("Error! SpiInitialize: XSpi_CfgInitialize\r\n");
        return XST_FAILURE;
    }

	if (XSpi_SetOptions(SpiPtr, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION) != XST_SUCCESS) {
        xil_printf("Error! SpiInitialize: XSpi_SetOptions\r\n");
        return XST_FAILURE;
    }

	if (XSpi_Start(SpiPtr) != XST_SUCCESS) {
        xil_printf("Error! SpiInitialize: XSpi_Start\r\n");
        return XST_FAILURE;
    }

    XSpi_IntrGlobalDisable(SpiPtr);
    return XST_SUCCESS;
}

int SpiFlashGetStatus(XSpi *SpiPtr, uint8_t *StatusRegPtr)
{
	uint8_t buffer[STATUS_READ_BYTES] = {COMMAND_STATUSREG_READ};

    if (XSpi_SetSlaveSelect(SpiPtr, 1) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (XSpi_Transfer(SpiPtr, buffer, buffer, STATUS_READ_BYTES) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 0) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	
	*StatusRegPtr = buffer[1];
	
	return XST_SUCCESS;
}

int SpiFlashReadId(XSpi *SpiPtr, uint32_t* DevIdPtr)
{
	uint8_t buffer[READ_ID_BYTES] = {COMMAND_READ_ID};
	
    if (XSpi_SetSlaveSelect(SpiPtr, 1) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_Transfer(SpiPtr, buffer, buffer, READ_ID_BYTES) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 0) != XST_SUCCESS) {
		return XST_FAILURE;
	}
    
	*DevIdPtr = buffer[1] | (buffer[2] << 8) | (buffer[3] << 16);

	return XST_SUCCESS;
}

int SpiFlashWaitForFlashReady(XSpi *SpiPtr)
{
	uint8_t StatusReg;

	while(1) {
		if(SpiFlashGetStatus(SpiPtr, &StatusReg) != XST_SUCCESS) {
			return XST_FAILURE;
		}

		if((StatusReg & FLASH_SR_IS_READY_MASK) == 0) {
			break;
		}
	}
	return XST_SUCCESS;
}

int SpiFlashWriteEnable(XSpi *SpiPtr)
{
	uint8_t buffer[WRITE_ENABLE_BYTES] = {COMMAND_WRITE_ENABLE};
	
	if (SpiFlashWaitForFlashReady(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 1) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (XSpi_Transfer(SpiPtr, buffer, NULL, WRITE_ENABLE_BYTES) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 0) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	
	return XST_SUCCESS;
}

int SpiFlashWriteDisable(XSpi *SpiPtr)
{
	uint8_t buffer[WRITE_DISABLE_BYTES] = {COMMAND_WRITE_DISABLE};

	if (SpiFlashWaitForFlashReady(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 1) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (XSpi_Transfer(SpiPtr, buffer, NULL, WRITE_DISABLE_BYTES) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 0) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}

int SpiFlashRead(XSpi *SpiPtr, uint8_t *WriteBuffer, uint8_t *ReadBuffer, uint32_t Addr, uint32_t ByteCount)
{
	if (SpiFlashWaitForFlashReady(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	WriteBuffer[0] = COMMAND_QUAD_READ;
	WriteBuffer[1] = (u8) (Addr >> 16);
	WriteBuffer[2] = (u8) (Addr >> 8);
	WriteBuffer[3] = (u8) Addr;

    if (XSpi_SetSlaveSelect(SpiPtr, 1) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (XSpi_Transfer( SpiPtr, WriteBuffer, ReadBuffer, (ByteCount + READ_WRITE_EXTRA_BYTES)) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (XSpi_SetSlaveSelect(SpiPtr, 0) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}

int SpiFlashQuadEnable(XSpi *SpiPtr)
{
	uint8_t buffer[2];

	if (SpiFlashWriteEnable(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	
	if (SpiFlashWaitForFlashReady(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	buffer[0] = COMMAND_WRITE_STATUS;
	buffer[1] = FLASH_SR_QE_MASK; /* QE = 1 */

    if (XSpi_SetSlaveSelect(SpiPtr, 1) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (XSpi_Transfer(SpiPtr, buffer, NULL, 2) != XST_SUCCESS) {
		return XST_FAILURE;
	}

    if (XSpi_SetSlaveSelect(SpiPtr, 0) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	if (SpiFlashWaitForFlashReady(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	
	if (SpiFlashWriteDisable(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	
	if (SpiFlashWaitForFlashReady(SpiPtr) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	
	return XST_SUCCESS;
}

uint32_t pickbit(uint32_t v, uint8_t bit) {
	return (v >> bit) & 0x1;
}

void reverse(uint8_t buf[4]) {
	uint8_t tmp = buf[0];
	buf[0] = buf[3];
	buf[3] = tmp;
	tmp = buf[1];
	buf[1] = buf[2];
	buf[2] = tmp;
}

uint32_t LfsrNext(uint32_t lfsr)
{
	return ((lfsr << 1) | (pickbit(lfsr, 31) ^ pickbit(lfsr, 21) ^ pickbit(lfsr, 1) ^ pickbit(lfsr, 0)));
}

int ValidateAgainstLfsr(XSpi *SpiPtr, const uint32_t seed, uint32_t *error_count, uint32_t *first_value_read, uint32_t *last_value_read)
{
	const uint32_t flash_size = 128*1024; // A full flash read, 1024*1024 bytes, takes ~5 seconds;
	const uint32_t row_size = 128;
	uint32_t lfsr = seed;
	*error_count = 0;
	uint8_t ReadBuffer[row_size + READ_WRITE_EXTRA_BYTES];
	uint8_t WriteBuffer[row_size + READ_WRITE_EXTRA_BYTES];

	SpiFlashQuadEnable(SpiPtr);

	for (uint32_t addr = 0; addr < flash_size; addr += row_size)
	{
		uint32_t *dataptr = (uint32_t*)(ReadBuffer + READ_WRITE_EXTRA_BYTES);
		if (SpiFlashRead(SpiPtr, WriteBuffer, ReadBuffer, addr, row_size) != XST_SUCCESS) {
			return XST_FAILURE;
		}
		
		for (uint32_t i=0; i < row_size / sizeof(uint32_t); i++) {
			// reverse((uint8_t*)dataptr);

			if (lfsr == seed) *first_value_read = *dataptr;
			
			lfsr = LfsrNext(lfsr);
			
            uint32_t position = addr + i * sizeof(uint32_t);
            
			*last_value_read = *dataptr;

			if (*dataptr != lfsr) {
				(*error_count)++;
			}
			dataptr++;
		}
	}

	if (*error_count == 0) {
		return XST_SUCCESS;
	} else {
		return XST_FAILURE;
	}
}