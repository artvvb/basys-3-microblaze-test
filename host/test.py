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
    logging.info(f"Writing {binfile_name} with random data (seed={hex(seed)}, expected first word {hex(lfsr_next(seed))})")
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

def program_device(push_to_text_box):
    script = os.path.join(os.path.dirname(__file__), "program_device.tcl")
    if not os.path.exists(script):
        logging.error(f"Can't find {script}")
        push_to_text_box(f"[ERROR] Can't find {script}", False)
        return False
    logging.info(f"Calling {script}")
    result = subprocess.call(["vivado", "-mode", "batch", "-source", script], shell=True)
    if result != 0:
        logging.error(f"Couldn't program bitstream into the board")
        push_to_text_box(f"[ERROR] Couldn't program bitstream into the board", False)
        return False
    return True

def sendint(port, n, w):
    port.write(hex(n)[2:].zfill(w).encode('utf-8'))

def sendchr(port, c):
    port.write(c.encode('utf-8'))

def ReadXadc(port, push_to_text_box):
    port.write('x'.encode('utf-8'))

    raw = port.read(4)
    temp = ((int(raw, 16) // 16) * 503.975) / 4096 - 273.15
    logging.info(f"XSM_CH_TEMP:    {temp} degrees C ({raw})")
    push_to_text_box(f"XSM_CH_TEMP:    {temp} degrees C ({raw})", False)

    raw = port.read(4)
    temp = (int(raw, 16) // 16) / 4096 * 3.0
    logging.info(f"XSM_CH_VCCINT:  {temp} V ({raw})")
    push_to_text_box(f"XSM_CH_VCCINT:  {temp} V ({raw})", False)
    
    raw = port.read(4)
    temp = (int(raw, 16) // 16) / 4096 * 3.0
    logging.info(f"XSM_CH_VCCAUX:  {temp} V ({raw})")
    push_to_text_box(f"XSM_CH_VCCAUX:  {temp} V ({raw})", False)
    
    raw = port.read(4)
    temp = (int(raw, 16) // 16) / 4096 * 3.0
    logging.info(f"XSM_CH_VBRAM:   {temp} V ({raw})")
    push_to_text_box(f"XSM_CH_VBRAM:   {temp} V ({raw})", False)

def TestEcho(port, push_to_text_box, size=100):
    sendchr(port, 'e')
    sendint(port, 100, 2)
    random_data = np.random.randint(0, 128, size=100).astype(np.uint8)
    data = (''.join([chr(x) for x in random_data])).encode('utf-8')
    port.write(data)
    echo = port.read(100)
    for i in range(0, 100):
        if echo[i] != data[i]:
            logging.error(f"Echo test failed: Mismatch in echoed data at position {i}, {echo[i]} != {data[i]}")
            push_to_text_box(f"[ERROR] Echo test failed: Mismatch in echoed data at position {i}, {echo[i]} != {data[i]}", False)
            break
    else:
        logging.info("Echo test passed")
        push_to_text_box("Echo test passed", False)

def FlashReadId(port, push_to_text_box):
    sendchr(port, 'f')
    id = int(port.read(6), 16)
    if id != 0x1620c2:
        logging.error(f"Flash read ID failed: Unexpected flash ID of {hex(id)}")
        push_to_text_box(f"[ERROR] Flash read ID failed: Unexpected flash ID of {hex(id)}", False)
    else:
        logging.info(f"Flash read ID succeeded: Macronix flash ID ({hex(id)}) detected")
        push_to_text_box(f"Flash read ID succeeded: Macronix flash ID ({hex(id)}) detected", False)

def FlashRead(port, seed, push_to_text_box):
    sendchr(port, 'q')
    sendint(port, seed, 8)
    read_passes = int(port.read(1), 16) # '0' is a pass
    error_count = int(port.read(8), 16)
    first = int(port.read(8), 16)
    last  = int(port.read(8), 16)
    if read_passes != 0:
        logging.error(f"Flash read failed: Contents did not match expectation, error_count={error_count}, first={hex(first).zfill(8)}, last={hex(last).zfill(8)}")
        push_to_text_box(f"[ERROR] Flash read failed: Contents did not match expectation, error_count={error_count}, first={hex(first).zfill(8)}, last={hex(last).zfill(8)}", False)
    else:
        logging.info(f"Flash read passed, first value seen: {hex(first).zfill(8)}, last: {hex(last).zfill(8)}")
        push_to_text_box(f"Flash read passed, first value seen: {hex(first).zfill(8)}, last: {hex(last).zfill(8)}", False)

DIO_SETTINGS_ADDR = 12
DIO_STATUS_ADDR = 16
PS2_POS_ADDR = 20
BRAM_SEED_ADDR = 24
BRAM_STATUS_ADDR = 28

DIO_MODE_OFF = 0
DIO_MODE_IMMUNITY_TOP_TO_BOTTOM = 1
DIO_MODE_IMMUNITY_PORT_PAIRS = 2
DIO_MODE_EMISSIONS = 3
# phase = uint8_t
# divider = uint8_t

def testbit(n, b):
    return ((n >> b) & 0x1) == 1

def CheckDio(port, push_to_text_box):
    sendchr(port, 'r')
    sendint(port, DIO_STATUS_ADDR, 2)
    status = int(port.read(8), 16)

    if (status & 0x10000) != 0:
        logging.error(f"DIO not running")
        push_to_text_box(f"[ERROR] DIO not running", False)
    else:
        logging.info(f"DIO counters are running")
        push_to_text_box(f"DIO counters are running", False)
    
    if (status & 0x20000) != 0:
        logging.error(f"Invalid DIO phase/divider configuration - check setup")
        push_to_text_box(f"[ERROR] Invalid DIO phase/divider configuration - check setup", False)
    
    if (status & 0xffff) != 0:
        logging.error(f"Invalid DIO bits detected ({hex(status & 0xffff)}) since the last read")
        push_to_text_box(f"[ERROR] Invalid DIO bits detected ({hex(status & 0xffff)}) since the last read", False)
    else:
        logging.info(f"All DIO samples match")
        push_to_text_box(f"All DIO samples match", False)

def StartDio(port, mode, phase, divider, push_to_text_box):
    settings = ((mode & 0x3) << 16) | ((phase & 0xff) << 8) | ((divider & 0xff))
    print(f"DIO settings: {hex(settings)[2:].zfill(8)}")
    sendchr(port, 'w')
    sendint(port, DIO_SETTINGS_ADDR, 2)
    sendint(port, settings, 8)
    CheckDio(port, push_to_text_box)
    
def CheckMouse(port, push_to_text_box):
    sendchr(port, 'r')
    sendint(port, PS2_POS_ADDR, 2)
    status = int(port.read(8), 16)

    if not testbit(status, 26):
        logging.info("Mouse data is stale")
        push_to_text_box("Mouse data is stale", False)
        return False
    else:
        logging.info(f"New status received from mouse")
        push_to_text_box(f"New status received from mouse", False)

    if testbit(status, 25):
        logging.error("Mouse not initialized")
        push_to_text_box("[ERROR] Mouse not initialized", False)

    if testbit(status, 24):
        logging.error("Mouse read ID failed, possible disconnect")
        push_to_text_box("[ERROR] Mouse read ID failed, possible disconnect", False)

    logging.info(f"Mouse position: Y={(status>>12) & 0xfff}; X={(status & 0xfff)}")
    push_to_text_box(f"Mouse position: Y={(status>>12) & 0xfff}; X={(status & 0xfff)}", False)
    return True

def CheckBram(port, push_to_text_box):
    seed = np.random.randint(0, 2**32, dtype=np.uint32)
    
    sendchr(port, 'w')
    sendint(port, BRAM_SEED_ADDR, 2)
    sendint(port, seed, 8)
    
    sendchr(port, 'r')
    sendint(port, BRAM_STATUS_ADDR, 2)
    status = int(port.read(8), 16)
    
    if testbit(status, 1):
        if testbit(status, 0):
            logging.info("BRAM test passed")
            push_to_text_box("BRAM test passed", False)
        else:
            logging.error("BRAM test failed")
            push_to_text_box("[ERROR] BRAM test failed", False)
        return True

    logging.warning("BRAM test not complete")
    push_to_text_box("[WARNING] BRAM test not complete", False)
    return False

def get_portlist():
    print ([port.device for port in serial.tools.list_ports.comports()])

def run_test(push_to_text_box, update_text_box, done_callback, settings):
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
        push_to_text_box("Starting IMMUNITY test sequence", True)
    elif dio_mode == DIO_MODE_EMISSIONS:
        logging.info("Starting EMISSIONS test sequence")
        push_to_text_box("Starting EMISSIONS test sequence", True)
    else:
        logging.info("Starting test sequence with DIO off")
        push_to_text_box("Starting test sequence with DIO off", True)

    qspi_seed = np.random.randint(0, 2**32, dtype=np.uint32)

    if done_callback(): return

    logging.info(f"Writing QSPI...")
    push_to_text_box(f"Writing QSPI...", True)
    if not write_qspi_binfile(qspi_seed):
        return
    
    if done_callback(): return
    
    logging.info(f"Writing FPGA image...")
    push_to_text_box(f"Writing FPGA image...", True)
    if not program_device(push_to_text_box):
        return

    program_only = False
    if program_only: exit()

    logging.info(f"Connecting to board on port {com_port}")
    push_to_text_box(f"Connecting to board on port {com_port}", True)

    with ser.Serial(port=com_port, baudrate=115200) as port:
    # with ser.Serial(port=sys.argv[1], baudrate=115200, timeout=0.1) as port:
        # Start DIO test
        phase = ((dio_divider + 1) // 2) - 1
        
        StartDio(port, dio_mode, phase, dio_divider, push_to_text_box)
        logging.info(f"DIO counter output frequency is set to {100_000_000 / (2 * (dio_divider + 1))} MHz")
        logging.info(f"DIO readback phase count is set to {phase} / {dio_divider}")

        while not done_callback():
            targettime = datetime.now() + timedelta(seconds=1)
            # Read XADC
            if enable_xadc: ReadXadc(port, push_to_text_box)
            # Do a Read ID
            if enable_flash_id: FlashReadId(port, push_to_text_box)
            # Do a SPI read
            if enable_flash_verify: FlashRead(port, qspi_seed, push_to_text_box)
            # Echo random data
            if enable_uart_echo: TestEcho(port, push_to_text_box)
            # Check DIO test
            if enable_dio_test: CheckDio(port, push_to_text_box)
            # Check mouse connectivity
            if enable_mouse: CheckMouse(port, push_to_text_box)
            # Run BRAM memory test
            if enable_bram_test: CheckBram(port, push_to_text_box)
            
            update_text_box()

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

# Add UI or at least static view of most recent log pass; include com port and stop button
# Add controls to turn off each of the steps above
# Double check flash programming
# Add switch to flip into emissions mode
