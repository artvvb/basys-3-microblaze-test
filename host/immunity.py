# make sure to log which setups are getting used.

import serial as ser
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
    print(f"Calling {script} to write binary data to SPI flash")
    subprocess.call(["vivado", "-mode", "batch", "-source", script], shell=True)

def program_device():
    script = os.path.join(os.path.dirname(__file__), "program_device.tcl")
    if not os.path.exists(script):
        logging.error(f"Can't find {script}")
    logging.info(f"Calling {script}")
    result = subprocess.call(["vivado", "-mode", "batch", "-source", script], shell=True)
    if result != 0:
        logging.error(f"Couldn't program bitstream into the board")

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
            logging.error("Echo test failed: Mismatch in echoed data at position {i}, {echo[i]} != {data[i]}")
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
    read_passes = int(port.read(1), 16) # '0' is a pass
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
BRAM_STATUS_ADDR = 28

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
        logging.error(f"Invalid DIO bits detected ({hex(status & 0xffff)}) since the last read")
    else:
        logging.info(f"All DIO samples match")

def StartDio(port, mode, phase, divider):
    settings = ((mode & 0x3) << 16) | ((phase & 0xff) << 8) | ((divider & 0xff))
    print(f"DIO settings: {hex(settings)[2:].zfill(8)}")
    sendchr(port, 'w')
    sendint(port, DIO_SETTINGS_ADDR, 2)
    sendint(port, settings, 8)

    CheckDio(port)
    
def CheckMouse(port):
    sendchr(port, 'r')
    sendint(port, PS2_POS_ADDR, 2)
    status = int(port.read(8), 16)

    if not testbit(status, 26):
        logging.info("Mouse data is stale")
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

    logging.warning("BRAM test not complete")
    return False

if __name__ == "__main__":
    init_logging()
    logging.info("Starting IMMUNITY test sequence")

    qspi_seed = np.random.randint(0, 2**32, dtype=np.uint32)
    logging.info(f"Writing QSPI")
    write_qspi_binfile(qspi_seed)
    logging.info(f"Writing FPGA image")
    program_device()

    program_only = False
    if program_only: exit()

    logging.info(f"Connecting to board on port {sys.argv[1]}")
    with ser.Serial(port=sys.argv[1], baudrate=115200) as port:
    # with ser.Serial(port=sys.argv[1], baudrate=115200, timeout=0.1) as port:
        # Start DIO test
        divider = 3 # tested 15, 7, 4
        phase = ((divider + 1) // 2) - 1
        
        mode = DIO_MODE_IMMUNITY_PORT_PAIRS
        StartDio(port, mode=mode, phase=phase, divider=divider)
        logging.info(f"DIO counter output frequency is set to {100_000_000 / (2 * (divider + 1))} MHz")
        logging.info(f"DIO readback phase count is set to {phase} / {divider}")
        
        done = False
        while not done:
            targettime = datetime.now() + timedelta(seconds=1)
            # Read XADC
            ReadXadc(port)
            # Do a Read ID
            FlashReadId(port)
            # Do a SPI read
            FlashRead(port, qspi_seed)
            # Echo random data
            TestEcho(port)
            # Check DIO test
            CheckDio(port)
            # Check mouse connectivity
            CheckMouse(port)
            # Run BRAM memory test
            CheckBram(port)

            timeleft = (targettime - datetime.now()).total_seconds()
            if timeleft > 0: time.sleep(timeleft)

# Add UI or at least static view of most recent log pass; include com port and stop button
# Add controls to turn off each of the steps above
# Double check flash programming
# Add switch to flip into emissions mode
