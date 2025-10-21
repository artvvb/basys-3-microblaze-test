#include "xparameters.h"
#include "xil_printf.h"
#include "flash.h"
#include "xuartlite.h"
#include "xil_io.h"
#include "xadc.h"
#include "xgpio.h"

/* Base address for register file */
#define TOP_BASEADDR		XPAR_TOP_V_0_BASEADDR
#define XADC_ADDR 		XPAR_XADC_WIZ_0_BASEADDR

/* Axi register offsets for test hardware */
#define STATUS_ADDR			0	/* READ-ONLY */
#define XADC_SET_CHAN_ADDR	4	/* WRITE-ONLY */
#define XADC_DATA_ADDR		8	/* CLEAR-ON-READ */
#define DIO_SETTINGS_ADDR	12	/* WRITE-ONLY */
#define DIO_STATUS_ADDR		16	/* CLEAR-ON-READ */
#define PS2_POS_ADDR		20	/* READ-ONLY */
#define BRAM_SEED_ADDR		24	/* WRITE-ONLY */
#define BRAM_STATUS_ADDR	28	/* READ-ONLY */

/* Status register bit fields */
#define STATUS_ADDR_BRAM_STATUS_TVALID_MASK 	0x80
#define STATUS_ADDR_BRAM_START_TREADY_MASK 		0x40
#define STATUS_ADDR_BRAM_SEED_TREADY_MASK 		0x20
#define STATUS_ADDR_PS2_POS_TVALID_MASK 		0x10
#define STATUS_ADDR_DIO_STATUS_TVALID_MASK 		0x8
#define STATUS_ADDR_DIO_SETTINGS_TREADY_MASK 	0x4
#define STATUS_ADDR_XADC_TVALID_MASK 			0x2
#define STATUS_ADDR_XADC_SET_ADDR_TREADY_MASK 	0x1

// /* Interrupt vector table*/
// ivt_t ivt [] = {
// 	{}
// };

/* DIO controller defines */
typedef enum {
	DIO_MODE_OFF = 0,
	DIO_MODE_IMMUNITY_TOP_TO_BOTTOM=1,
	DIO_MODE_IMMUNITY_PORT_PAIRS=2,
	DIO_MODE_EMISSIONS=3
} dio_mode_t;

/* Phase/Divisor Pairs */
// Trying to see what happens when phase is adjusted, centering the input sample in the output eye/window is not exactly at halfway due to sync flops.
#define DIO_COUNTERS_25_MHZ 	0, 1
#define DIO_COUNTERS_12_5_MHZ 	1, 3
#define DIO_COUNTERS_7_5_MHZ 	1, 7
#define DIO_COUNTERS_5_MHZ 		4, 9
#define DIO_COUNTERS_2_5_MHZ 	9, 19
#define DIO_COUNTERS_1_MHZ 		24, 49

void ProcessCommands();
int DioCheckTest();
int DioStartTest(dio_mode_t mode, uint8_t phase, uint8_t divisor);
int Ps2Read();
int BramTest(uint32_t seed);
void receive(XUartLite *uartptr, uint8_t *buffer, uint8_t bytes_remaining);
void send(XUartLite *uartptr, uint8_t *buffer, uint8_t bytes_remaining);
void echo(XUartLite *uartptr, uint8_t *buffer, const uint8_t bytes);
void hextoint(uint32_t *i, uint8_t *a, uint8_t n);
void inttohex(uint32_t i, uint8_t *a, uint8_t n);
int InitializeErrGpio();
void ToggleFlashErr();
void ToggleUartErr();

static XGpio flash_err;
static XGpio uart_err;

int DioCheckTest() {
	// volatile uint32_t *SettingsPtr = (uint32_t*)(TOP_BASEADDR + DIO_SETTINGS_ADDR);
	volatile uint32_t *DioStatusPtr = (uint32_t*)(TOP_BASEADDR + DIO_STATUS_ADDR);
	volatile uint32_t *StatusPtr = (uint32_t*)(TOP_BASEADDR + STATUS_ADDR);
	int code = XST_SUCCESS;
	uint32_t Status;

	Status = *StatusPtr;
	if (!(Status & STATUS_ADDR_DIO_STATUS_TVALID_MASK)) {
		xil_printf("Error: DIO status register not valid\r\n");
		return XST_FAILURE;
	}
	
	Status = *DioStatusPtr;
	xil_printf("DIO status: %08x\r\n", Status);

	if (Status & 0x10000) {
		xil_printf("Error: DIO not running\r\n");
		code = XST_FAILURE;
	}
	
	if (Status & 0x20000) {
		xil_printf("Error: Bad phase/divisor combination\r\n");
		code = XST_FAILURE;
	}

	if ((Status & 0xFFFF) != 0) {
		xil_printf("Error: DIO error reported (%04x)\r\n", Status & 0xFFFF);
		code = XST_FAILURE;
	}

	return code;
}

int DioStartTest(dio_mode_t mode, uint8_t phase, uint8_t divisor) {
	volatile uint32_t *SettingsPtr = (uint32_t*)(TOP_BASEADDR + DIO_SETTINGS_ADDR);
	volatile uint32_t *StatusPtr = (uint32_t*)(TOP_BASEADDR + STATUS_ADDR);
	volatile uint32_t *DioStatusPtr = (uint32_t*)(TOP_BASEADDR + DIO_STATUS_ADDR);
	uint32_t Settings = (mode << 16) | (phase << 8) | (divisor);
	
	if (!(*StatusPtr & STATUS_ADDR_DIO_SETTINGS_TREADY_MASK)) {
		xil_printf("Error: DIO settings register not ready\r\n");
		return XST_FAILURE;
	}

	xil_printf("DIO status before start: %08x\r\n", *DioStatusPtr);
	xil_printf("DIO settings: %08x\r\n", Settings);
	*SettingsPtr = Settings;

	DioCheckTest();
	
	return XST_SUCCESS;
}

#define NewDataBit 				26
#define NewDataMask 			(1 << 26)
#define NotConnectedBit			25
#define NotConnectedMask 		(1 << 25)
#define MouseErrorBit 			24
#define MouseErrorMask 			(1 << 24)
#define MouseXPosMask 			(0xfff << 12)
#define MouseXPosBit 			(12)
#define MouseYPosMask 			(0xfff)
#define geterr(raw) 			((raw & MouseErrorMask) >> MouseErrorBit)
#define getnotconnected(raw) 	((raw & NotConnectedMask) >> NotConnectedBit)
#define getisnew(raw) 			((raw & NewDataMask) >> NewDataBit)
#define getxpos(raw) 			((raw & MouseXPosMask) >> MouseXPosBit)
#define getypos(raw) 			((raw & MouseYPosMask))

int Ps2Read() {
	volatile uint32_t *Ps2PosPtr = (uint32_t*)(TOP_BASEADDR + PS2_POS_ADDR);
	volatile uint32_t *StatusPtr = (uint32_t*)(TOP_BASEADDR + STATUS_ADDR);
	int timeout_count = 0; 

	while ((*StatusPtr & 0x10) == 0 && timeout_count < 100) {
		timeout_count++;
	}

	if (timeout_count == 100) {
		xil_printf("Error: PS/2 read timed out\r\n");
	}

	uint32_t data;
	data = *Ps2PosPtr;
	if (getisnew(data)) {
		xil_printf("PS/2 data is new: %d\r\n", getisnew(data));
		xil_printf("PS/2 error: %d\r\n", geterr(data));
		xil_printf("PS/2 mouse not connected: %d\r\n", getnotconnected(data));
		xil_printf("PS/2 position: %03x, %03x\r\n", getxpos(data), getypos(data));
	}

	return XST_SUCCESS;
}

int BramTest(uint32_t seed) {
	volatile uint32_t *BramSeedPtr = (uint32_t*)(TOP_BASEADDR + BRAM_SEED_ADDR);
	volatile uint32_t *BramStatusPtr = (uint32_t*)(TOP_BASEADDR + BRAM_STATUS_ADDR);
	volatile uint32_t *StatusPtr = (uint32_t*)(TOP_BASEADDR + STATUS_ADDR);
	uint32_t status;

	while (!((status = *StatusPtr) & 0x20)) xil_printf("wait for bram seed ready %08x\r\n", status); // wait for bram seed ready
	*BramSeedPtr = seed;
	while (!((status = *StatusPtr) & 0x40)) xil_printf("wait for bram status valid %08x\r\n", status); // 
	
	while (!((status = *BramStatusPtr) & 0x2)) {// wait for bram status done
		xil_printf("wait for bram status done %08x\r\n", status);
		while (!((status = *StatusPtr) & 0x40)) {
			xil_printf("wait for bram status valid %08x\r\n", status); // 
		}
	}
	
	if ((status & 0x1) == 0){
		xil_printf("Error: Bram test failed\r\n");
		return XST_FAILURE;
	}

	xil_printf("Bram test passed\r\n");
	return XST_SUCCESS;
}

int main () {
	ProcessCommands();
}

int InitializeErrGpio() {
	XGpio_Config *cfgptr;
	
	cfgptr = XGpio_LookupConfig(XPAR_CONTROL_0_FLASH_ERROR_GPIO_0_BASEADDR);
	if (XGpio_CfgInitialize(&flash_err, cfgptr, cfgptr->BaseAddress) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	XGpio_DiscreteWrite(&flash_err, 1, 0);

	cfgptr = XGpio_LookupConfig(XPAR_CONTROL_0_UART_ERROR_GPIO_0_BASEADDR);
	if (XGpio_CfgInitialize(&uart_err, cfgptr, cfgptr->BaseAddress) != XST_SUCCESS) {
		return XST_FAILURE;
	}
	XGpio_DiscreteWrite(&uart_err, 1, 0);

	return XST_SUCCESS;
}

void ToggleFlashErr() {
	XGpio_DiscreteWrite(&flash_err, 1, 1);
	XGpio_DiscreteWrite(&flash_err, 1, 0);
}

void ToggleUartErr() {
	XGpio_DiscreteWrite(&uart_err, 1, 1);
	XGpio_DiscreteWrite(&uart_err, 1, 0);
}

void receive(XUartLite *uartptr, uint8_t *buffer, uint8_t bytes_remaining) {
	uint8_t received_bytes;
	while (bytes_remaining) {
		received_bytes = XUartLite_Recv(uartptr, buffer, bytes_remaining);
		buffer += received_bytes;
		bytes_remaining -= received_bytes;
	}
}

void send(XUartLite *uartptr, uint8_t *buffer, uint8_t bytes_remaining) {
	uint8_t sent_bytes;
	while (bytes_remaining > 0) {
		sent_bytes = XUartLite_Send(uartptr, buffer, bytes_remaining);
		buffer += sent_bytes;
		bytes_remaining -= sent_bytes;
	}
}

void echo(XUartLite *uartptr, uint8_t *buffer, const uint8_t bytes) {
	uint8_t *sendbuf = buffer, bytes_sent = 0;
	uint8_t *recvbuf = buffer, bytes_received = 0;
	
	while (recvbuf < buffer + bytes) {
		recvbuf += XUartLite_Recv(uartptr, recvbuf, buffer + bytes - recvbuf);
		if (recvbuf > sendbuf) {
			sendbuf += XUartLite_Send(uartptr, sendbuf, recvbuf - sendbuf);
		}
	}
	while (sendbuf < buffer + bytes) {
		sendbuf += XUartLite_Send(uartptr, sendbuf, recvbuf - sendbuf);
	}
}

void hextoint(uint32_t *i, uint8_t *a, uint8_t n) {
	if (n > 8) return;
	if (n <= 0) return;
	*i = 0;
	for (int c = 0; c < n; c++) {
		*i <<= 4;
		if (a[c] >= '0' && a[c] <= '9') {
			*i += a[c] - '0';
		} else if (a[c] >= 'a' && a[c] <= 'f') {
			*i += a[c] - 'a' + 10;
		} else if (a[c] >= 'F' && a[c] <= 'F') {
			*i += a[c] - 'A' + 10;
		} // else error
	}
}

void inttohex(uint32_t i, uint8_t *a, uint8_t n) {
	while (n-- > 0) {
		if ((i & 0xf) >= 0 && (i & 0xf) <= 9) {
			a[n] = (i & 0xf) + '0';
		} else {
			a[n] = (i & 0xf) - 10 + 'a';
		}
		i >>= 4;
	}
}

void ProcessCommands() {
	// {"w", hex(address[7:0]), hex(data[31:0])}		- write any address in control block
	// {"r", hex(address[7:0])} => {hex(data[31:0])}	- read any address in control block
	// {"e", hex(count[7:0]), ...} => {...}				- echo N characters
	// {"q", hex(seed[31:0])} => {pass[1], hex(error_count[31:0]))} - do quad read (blocking)
	// {"f"} => {hex(device_id[23:0]))} - read flash id
	// {"x"} => {hex(xadc_raw[11:0] x 4)}
	XUartLite_Config *cfgptr;
	XUartLite uart;
	XSpi spi;
	if (SpiInitialize(&spi, XPAR_AXI_QUAD_SPI_0_BASEADDR) != XST_SUCCESS) {
		xil_printf("Error! Spi failed to initialize.\r\n");
	}
	if (XadcInitialize(XPAR_XADC_WIZ_0_BASEADDR) != XST_SUCCESS) {
		xil_printf("Error! XADC failed to initialize.\r\n");	
	}
	cfgptr = XUartLite_LookupConfig(XPAR_AXI_UARTLITE_0_BASEADDR);
	if (!cfgptr) {
		xil_printf("Error! UART failed to initialize.\r\n");
	}
	if (XUartLite_CfgInitialize(&uart, cfgptr, cfgptr->RegBaseAddr) != XST_SUCCESS) {
		xil_printf("Error! UART failed to initialize.\r\n");
	}
	if (InitializeErrGpio() != XST_SUCCESS) {
		xil_printf("Error! GPIOs failed to initialize\r\n");
	}

	uint8_t bytecount;
	uint8_t buffer[256];
	uint16_t xadc_data[Xadc_NumChannels];
	int32_t addr, data, echo_bytes, error_count, device_id, first, last;
	uint8_t pass;

	while (1) {
		receive(&uart, buffer, 1);

		switch (buffer[0]) {
			case 'w':
				receive(&uart, buffer, 2);
				hextoint(&addr, buffer, 2);
				receive(&uart, buffer, 8);
				hextoint(&data, buffer, 8);
				*(uint32_t*)(TOP_BASEADDR + addr) = data;
				break;
			case 'r':
				receive(&uart, buffer, 2);
				hextoint(&addr, buffer, 2);
				data = *(uint32_t*)(TOP_BASEADDR + addr);
				inttohex(data, buffer, 8);
				send(&uart, buffer, 8);
				break;
			case 'e':
				receive(&uart, buffer, 2);
				hextoint(&data, buffer, 2);
				echo(&uart, buffer, data);
				break;
			case 'q':
				receive(&uart, buffer, 8);
				hextoint(&data, buffer, 8);
				pass = ValidateAgainstLfsr(&spi, data, &error_count, &first, &last);
				if (!pass) ToggleFlashErr();
				inttohex(pass, buffer, 1);
				send(&uart, buffer, 1);
				inttohex(error_count, buffer, 8);
				send(&uart, buffer, 8);
				inttohex(first, buffer, 8);
				send(&uart, buffer, 8);
				inttohex(last, buffer, 8);
				send(&uart, buffer, 8);
				break;
			case 'f':
				SpiFlashReadId(&spi, &device_id);
				inttohex(device_id, buffer, 6);
				send(&uart, buffer, 6);
				break;
			case 'x':
				Xadc_ReadData(xadc_data);
				inttohex(xadc_data[0], &(buffer[0]), 4);
				inttohex(xadc_data[1], &(buffer[4]), 4);
				inttohex(xadc_data[2], &(buffer[8]), 4);
				inttohex(xadc_data[3], &(buffer[12]), 4);
				send(&uart, buffer, 16);
				break;
			default:
				ToggleUartErr();
				break;
		}
	}
}