# make sure to log which setups are getting used.

import serial as ser
import serial.tools.list_ports
import sys
import os
import subprocess
import numpy as np
import logging
from datetime import datetime, timedelta
import time

def lfsr_next(lfsr):
    pickbit = lambda x, i: (x >> i) & 0x1
    return ((lfsr << 1) | (pickbit(lfsr, 31) ^ pickbit(lfsr, 21) ^ pickbit(lfsr, 1) ^ pickbit(lfsr, 0))) & 0xffffffff

def generate_qspi_simfile(seed):
    size = 1024 * 128 # reading a single page burst per loop keeps the read time below a second; 1024*1024 = 32 Mebi-bit flash part
    lfsr = seed
    binfile_name = os.path.join(os.path.dirname(__file__), "random_data.bin")
    logging.info(f"Writing {binfile_name} with random data (seed={hex(seed)}, expecting first word {hex(lfsr_next(seed))})")
    with open(binfile_name, "wb") as binfile:
        for _ in range(size):
            lfsr = lfsr_next(lfsr)
            binfile.write(np.uint32.tobytes(lfsr))

def write_qspi_binfile(seed):
    generate_qspi_simfile(seed)
    script = os.path.join(os.path.dirname(__file__), "program_qspi.tcl")
    if 0 == subprocess.call(["vivado", "-mode", "batch", "-source", script], shell=True):
        return True
    return False

def program_device():
    script = os.path.join(os.path.dirname(__file__), "program_device.tcl")
    if not os.path.exists(script):
        logging.error(f"Can't find {script}")
        return False
    logging.info(f"Calling {script}")
    result = subprocess.call(["vivado", "-mode", "batch", "-source", script], shell=True)
    if result != 0:
        logging.error(f"Couldn't program bitstream into the board")
        return False
    return True

def sendint(port, n, w):
    port.write(hex(n)[2:].zfill(w).encode('utf-8'))

def sendchr(port, c):
    port.write(c.encode('utf-8'))

def ReadXadc(port):
    port.write('x'.encode('utf-8'))

    raw = port.read(4)
    temp = ((int(raw, 16) // 16) * 503.975) / 4096 - 273.15
    logging.info(f"XSM_CH_TEMP:    {temp} degrees C ({raw})")

    raw = port.read(4)
    temp = (int(raw, 16) // 16) / 4096 * 3.0
    logging.info(f"XSM_CH_VCCINT:  {temp} V ({raw})")
    
    raw = port.read(4)
    temp = (int(raw, 16) // 16) / 4096 * 3.0
    logging.info(f"XSM_CH_VCCAUX:  {temp} V ({raw})")
    
    raw = port.read(4)
    temp = (int(raw, 16) // 16) / 4096 * 3.0
    logging.info(f"XSM_CH_VBRAM:   {temp} V ({raw})")

def TestEcho(port, size=100):
    sendchr(port, 'e')
    sendint(port, 100, 2)
    random_data = np.random.randint(0, 128, size=100).astype(np.uint8)
    data = (''.join([chr(x) for x in random_data])).encode('utf-8')
    port.write(data)
    echo = port.read(100)
    for i in range(0, 100):
        if echo[i] != data[i]:
            logging.error(f"Echo test failed: Mismatch in echoed data at position {i}, {echo[i]} != {data[i]}")
            break
    else:
        logging.info("Echo test passed")

def FlashReadId(port):
    sendchr(port, 'f')
    id = int(port.read(6), 16)
    if id != 0x1620c2:
        logging.error(f"Flash read ID failed: Unexpected flash ID of {hex(id)}")
    else:
        logging.info(f"Flash read ID succeeded: Macronix flash ID ({hex(id)}) detected")

def FlashRead(port, seed):
    sendchr(port, 'q')
    sendint(port, seed, 8)

    time.sleep(0.2)
    
    starttime = datetime.now()
    done = False
    while not done:
        read_passes = port.read(1)
        if read_passes != b'':
            done = True
    read_passes = int(read_passes, 16) # '0' is a pass
    timepassed = (datetime.now() - starttime).total_seconds()
    logging.info(f"Flash read completed after {timepassed} seconds")
    
    error_count = int(port.read(8), 16)
    first = int(port.read(8), 16)
    last  = int(port.read(8), 16)
    if read_passes != 0:
        logging.error(f"Flash read failed: Contents did not match expectation, error_count={error_count}, first={hex(first).zfill(8)}, last={hex(last).zfill(8)}")
    else:
        logging.info(f"Flash read passed, first value seen: {hex(first).zfill(8)}, last: {hex(last).zfill(8)}")
    
DIO_SETTINGS_ADDR = 12
DIO_STATUS_ADDR = 16
PS2_POS_ADDR = 20
BRAM_SEED_ADDR = 24
BRAM_ADDR_MAX_ADDR = 28
BRAM_STATUS_ADDR = 32
BRAM_ADDR_BITS = 13

DIO_MODE_OFF = 0
DIO_MODE_IMMUNITY_TOP_TO_BOTTOM = 1
DIO_MODE_IMMUNITY_PORT_PAIRS = 2
DIO_MODE_EMISSIONS = 3
# phase = uint8_t
# divider = uint8_t

def testbit(n, b):
    return ((n >> b) & 0x1) == 1

def CheckDio(port):
    sendchr(port, 'r')
    sendint(port, DIO_STATUS_ADDR, 2)
    status = int(port.read(8), 16)

    if (status & 0x10000) != 0:
        logging.error(f"DIO not running")
    else:
        logging.info(f"DIO counters are running")
    
    if (status & 0x20000) != 0:
        logging.error(f"Invalid DIO phase/divider configuration - check setup")
    
    if (status & 0xffff) != 0:
        logging.error(f"Invalid DIO bits detected ({hex(status & 0xffff).zfill(4)}) since the last read")
    else:
        logging.info(f"All DIO samples match")

def StartDio(port, mode, phase, divider):
    settings = ((mode & 0x3) << 16) | ((phase & 0xff) << 8) | ((divider & 0xff))
    logging.info(f"Starting DIO with settings: mode:{mode}, phase:{phase}, divider:{divider}")
    sendchr(port, 'w')
    sendint(port, DIO_SETTINGS_ADDR, 2)
    sendint(port, settings, 8)
    CheckDio(port)

def CheckMouse(port):
    sendchr(port, 'r')
    sendint(port, PS2_POS_ADDR, 2)
    status = int(port.read(8), 16)

    if not testbit(status, 26):
        logging.error("Mouse data is stale")
        return False
    else:
        logging.info(f"New status received from mouse")
        
    if testbit(status, 25):
        logging.error("Mouse not initialized")
        
    if testbit(status, 24):
        logging.error("Mouse read ID failed, possible disconnect")
        
    logging.info(f"Mouse position: Y={(status>>12) & 0xfff}; X={(status & 0xfff)}")
    return True

def CheckBram(port):
    seed = np.random.randint(0, 2**32, dtype=np.uint32)
    
    sendchr(port, 'w')
    sendint(port, BRAM_ADDR_MAX_ADDR, 2)
    sendint(port, ((1 << BRAM_ADDR_BITS) - 1) | (0x0 << BRAM_ADDR_BITS), 8)

    sendchr(port, 'w')
    sendint(port, BRAM_SEED_ADDR, 2)
    sendint(port, seed, 8)
    
    sendchr(port, 'r')
    sendint(port, BRAM_STATUS_ADDR, 2)
    status = int(port.read(8), 16)
    
    if testbit(status, 1):
        if testbit(status, 0):
            logging.info("BRAM test passed")
        else:
            logging.error("BRAM test failed")
        return True

    logging.error("BRAM test not complete")
    return False

def get_portlist():
    print ([port.device for port in serial.tools.list_ports.comports()])

class test_obj:
    def __init__(self):
        self.port = None
    def setup_test(self, settings):
        self.dio_mode = settings["dio_mode"].get()
        self.com_port = settings["com_port"]
        self.dio_divider = settings["dio_divider"].get()
        self.dio_mode = settings["dio_mode"].get()
        self.enable_xadc = settings["enable_xadc"].get()
        self.enable_flash_id = settings["enable_flash_id"].get()
        self.enable_flash_verify = settings["enable_flash_verify"].get()
        self.enable_uart_echo = settings["enable_uart_echo"].get()
        self.enable_dio_test = settings["enable_dio_test"].get()
        self.enable_mouse = settings["enable_mouse"].get()
        self.enable_bram_test = settings["enable_bram_test"].get()

        logging.info("Starting Test")
        logging.info(f'Setting enable_xadc:         {settings["enable_xadc"].get()}')
        logging.info(f'Setting enable_flash_id:     {settings["enable_flash_id"].get()}')
        logging.info(f'Setting enable_flash_verify: {settings["enable_flash_verify"].get()}')
        logging.info(f'Setting enable_uart_echo:    {settings["enable_uart_echo"].get()}')
        logging.info(f'Setting enable_dio_test:     {settings["enable_dio_test"].get()}')
        logging.info(f'Setting enable_mouse:        {settings["enable_mouse"].get()}')
        logging.info(f'Setting enable_bram_test:    {settings["enable_bram_test"].get()}')
        logging.info(f'Setting dio_mode:            {settings["dio_mode"].get()}')
        logging.info(f'Setting com_port:            {settings["com_port"]}')
        logging.info(f'Setting dio_divider:         {settings["dio_divider"].get()}')
    
        if self.dio_mode == DIO_MODE_IMMUNITY_TOP_TO_BOTTOM or self.dio_mode == DIO_MODE_IMMUNITY_PORT_PAIRS:
            logging.info("Starting IMMUNITY test sequence")
        elif self.dio_mode == DIO_MODE_EMISSIONS:
            logging.info("Starting EMISSIONS test sequence")
        else:
            logging.info("Starting test sequence with DIO off")

        self.qspi_seed = np.random.randint(0, 2**32, dtype=np.uint32)
        self.init_sequence = 0

    def write_qspi(self):
        if self.enable_flash_verify:
            logging.info(f"Writing QSPI...")
            if not write_qspi_binfile(self.qspi_seed):
                return
        else:
            logging.info(f"Skipping QSPI write, Flash read test is not enabled")

    def program_device(self):
        logging.info(f"Writing FPGA image...")
        if not program_device():
            return
        
    def run_test(self):
        # implemented as a state machine so that the loop controller can check for a stop button press between long blocking calls
        if self.init_sequence == 0:
            self.write_qspi()
            self.init_sequence += 1
            return
        if self.init_sequence == 1:
            self.program_device()
            self.init_sequence += 1
            return
        if self.init_sequence == 2:
            logging.info(f"Connecting to board on port {self.com_port}")
            # note: a much shorter timeout can't be used as long as the flash read cycle stays fully blocking
            self.port = ser.Serial(port=self.com_port, baudrate=115200, timeout=0.4)
            self.phase = ((self.dio_divider + 1) // 2) - 1
            StartDio(self.port, self.dio_mode, self.phase, self.dio_divider)
            logging.info(f"DIO counter output frequency is set to {100_000_000 / (2 * (self.dio_divider + 1))} MHz")
            logging.info(f"DIO readback phase count is set to {self.phase} / {self.dio_divider}")
            # ConfigureBram(self.port, self.bram_bank_1_en, self.bram_max_addr)
            # logging.info(f"DIO counter output frequency is set to {100_000_000 / (2 * (self.dio_divider + 1))} MHz")
            # logging.info(f"DIO readback phase count is set to {self.phase} / {self.dio_divider}")
            self.init_sequence += 1
            self.iteration = 0
            return
        if self.init_sequence >= 3:
            targettime = datetime.now() + timedelta(seconds=1)
            
            if self.enable_xadc: ReadXadc(self.port)
            if self.enable_flash_id: FlashReadId(self.port)
            if self.enable_flash_verify: FlashRead(self.port, self.qspi_seed)
            if self.enable_uart_echo: TestEcho(self.port)
            if self.enable_dio_test: CheckDio(self.port)
            if self.enable_mouse: CheckMouse(self.port)
            if self.enable_bram_test: CheckBram(self.port, )
            
            timeleft = (targettime - datetime.now()).total_seconds()
            if timeleft > 0: time.sleep(timeleft)

    def stop_test(self):
        if not self.port is None:
            self.port.close()

def run_test(done_callback, settings):
    dio_mode = settings["dio_mode"].get()
    com_port = settings["com_port"]
    dio_divider = settings["dio_divider"].get()
    dio_mode = settings["dio_mode"].get()
    enable_xadc = settings["enable_xadc"].get()
    enable_flash_id = settings["enable_flash_id"].get()
    enable_flash_verify = settings["enable_flash_verify"].get()
    enable_uart_echo = settings["enable_uart_echo"].get()
    enable_dio_test = settings["enable_dio_test"].get()
    enable_mouse = settings["enable_mouse"].get()
    enable_bram_test = settings["enable_bram_test"].get()

    if dio_mode == DIO_MODE_IMMUNITY_TOP_TO_BOTTOM or dio_mode == DIO_MODE_IMMUNITY_PORT_PAIRS:
        logging.info("Starting IMMUNITY test sequence")
    elif dio_mode == DIO_MODE_EMISSIONS:
        logging.info("Starting EMISSIONS test sequence")
    else:
        logging.info("Starting test sequence with DIO off")

    qspi_seed = np.random.randint(0, 2**32, dtype=np.uint32)

    if done_callback(): return

    if enable_flash_verify:
        logging.info(f"Writing QSPI...")
        if not write_qspi_binfile(qspi_seed):
            return
    else:
        logging.info(f"Skipping QSPI write, Flash read test is not enabled")
    
    if done_callback(): return
    
    logging.info(f"Writing FPGA image...")
    if not program_device():
        return

    program_only = False
    if program_only: exit()

    logging.info(f"Connecting to board on port {com_port}")

    iteration = 0

    with ser.Serial(port=com_port, baudrate=115200, timeout=0.4) as port:
    # with ser.Serial(port=sys.argv[1], baudrate=115200, timeout=0.1) as port:
        # Start DIO test
        phase = ((dio_divider + 1) // 2) - 1
        
        StartDio(port, dio_mode, phase, dio_divider)
        logging.info(f"DIO counter output frequency is set to {100_000_000 / (2 * (dio_divider + 1))} MHz")
        logging.info(f"DIO readback phase count is set to {phase} / {dio_divider}")

        while not done_callback():
            targettime = datetime.now() + timedelta(seconds=1)
            iteration += 1
            logging.info(f"Cycle #{iteration}")
            # Read XADC
            if enable_xadc: ReadXadc(port)
            # Do a Read ID
            if enable_flash_id: FlashReadId(port)
            # Do a SPI read
            if enable_flash_verify: FlashRead(port, qspi_seed)
            # Echo random data
            if enable_uart_echo: TestEcho(port)
            # Check DIO test
            if enable_dio_test: CheckDio(port)
            # Check mouse connectivity
            if enable_mouse: CheckMouse(port)
            # Run BRAM memory test
            if enable_bram_test: CheckBram(port)
            
            timeleft = (targettime - datetime.now()).total_seconds()
            if timeleft > 0: time.sleep(timeleft)

if __name__ == "__main__":
    def init_logging():
        logging.basicConfig(level=logging.INFO)
        log_formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
        logger = logging.getLogger()

        file_handler = logging.FileHandler("test.log")
        file_handler.setFormatter(log_formatter)
        logger.addHandler(file_handler)

        console_handler = logging.StreamHandler()
        console_handler.setFormatter(log_formatter)
        logger.addHandler(console_handler)
    init_logging()
    settings = {
        "enable_xadc":         True,
        "enable_flash_id":     True,
        "enable_flash_verify": True,
        "enable_uart_echo":    True,
        "enable_dio_test":     True,
        "enable_mouse":        True,
        "enable_bram_test":    True,
        "dio_divider":         3,
        "dio_mode":            2,
        "com_port":            sys.argv[1]
    }
    run_test(lambda a, b: True, lambda a: True, settings)

# BRAM: Add continuous immunity mode?
#       Implement controls for bank 1 and addressing in GUI.