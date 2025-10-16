from tkinter import *
from tkinter import ttk
import logging
from datetime import datetime, timedelta
import time
from time import sleep
import threading
import sys

def init_logging(include_console=False):
    logging.basicConfig(level=logging.INFO)
    log_formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
    logger = logging.getLogger()

    file_handler = logging.FileHandler("temp.log")
    file_handler.setFormatter(log_formatter)
    logger.addHandler(file_handler)

    if include_console:
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(log_formatter)
        logger.addHandler(console_handler)

init_logging(False)

def dummy_cycle_loop(push_to_text_box, update_text_box, done_callback):
    n = 0
    while not done_callback():
        targettime = datetime.now() + timedelta(seconds=1)

        push_to_text_box(f"Cycle {n}", False)
        update_text_box()

        logging.info(f"Cycle {n}")
        n += 1
        timeleft = (targettime - datetime.now()).total_seconds()
        if timeleft > 0:
            time.sleep(timeleft)

next_text_box_string = []
def push_to_text_box(text_box, s, immediate=False):
    global next_text_box_string
    next_text_box_string.append(s)
    if immediate:
        text_box.delete(1.0, END)
        text_box.insert(1.0, '\n'.join(next_text_box_string))
        next_text_box_string = []
def update_text_box(text_box):
    global next_text_box_string
    text_box.delete(1.0, END)
    text_box.insert(1.0, '\n'.join(next_text_box_string))
    next_text_box_string = []

from test import run_test

if __name__ == '__main__':
    # Create the main window
    root = Tk()
    root.title('Basys 3 Test')
    
    settings = {
        "enable_xadc":          BooleanVar(root, True),
        "enable_flash_id":      BooleanVar(root, True),
        "enable_flash_verify":  BooleanVar(root, True),
        "enable_uart_echo":     BooleanVar(root, True),
        "enable_dio_test":      BooleanVar(root, True),
        "enable_mouse":         BooleanVar(root, True),
        "enable_bram_test":     BooleanVar(root, True),
        "dio_divider":          IntVar(root, 4),
        "dio_mode":             IntVar(root, 0),
        "com_port":             sys.argv[1]
    }

    loop_done = False
    thread = None
    def start_loop(text_box):
        global thread, loop_done
        if not thread is None: return

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

        # thread = threading.Thread(target=lambda: dummy_cycle_loop(lambda a, b: push_to_text_box(text_box, a, b), lambda: update_text_box(text_box)), args=())
        thread = threading.Thread(target=lambda: run_test(
            lambda a, b: push_to_text_box(text_box, a, b),
            lambda: update_text_box(text_box),
            done_callback = lambda: loop_done,
            settings = settings
        ), args=())
        thread.daemon = True
        thread.start()
        logging.info("Started test loop")

    def stop_loop():
        global loop_done, thread
        loop_done = True
        logging.info(f'Halting test')
        if thread is None:
            logging.info(f'No test running to stop')
            return
        while thread.is_alive():
            logging.info("Waiting for test to finish...")
            sleep(1)
        loop_done = False
        logging.info("Test thread closed")
        thread = None

    def quit_app():
        stop_loop()
        logging.info(f"Quitting test app")
        root.destroy()

    frm          = ttk.Frame(root, padding=10)
    mode_frm     = ttk.Frame(frm, padding=10)
    settings_frm = ttk.Frame(frm, padding=10)
    dio_numeric_frm = ttk.Frame(frm, padding=10)
    control_frm  = ttk.Frame(frm, padding=10)
    log_frame    = ttk.Frame(frm, padding=10)
    frm.grid()
    mode_frm.grid(column=0, row=0)
    dio_numeric_frm.grid(column=0, row=1)
    settings_frm.grid(column=0, row=2)
    control_frm.grid(column=0, row=3)
    log_frame.grid(column=1, row=0, rowspan=3)

    ttk.Checkbutton(settings_frm, text="enable_xadc", variable=settings["enable_xadc"]).grid(sticky='nw')
    ttk.Checkbutton(settings_frm, text="enable_flash_id", variable=settings["enable_flash_id"]).grid(sticky='nw')
    ttk.Checkbutton(settings_frm, text="enable_flash_verify", variable=settings["enable_flash_verify"]).grid(sticky='nw')
    ttk.Checkbutton(settings_frm, text="enable_uart_echo", variable=settings["enable_uart_echo"]).grid(sticky='nw')
    ttk.Checkbutton(settings_frm, text="enable_dio_test", variable=settings["enable_dio_test"]).grid(sticky='nw')
    ttk.Checkbutton(settings_frm, text="enable_mouse", variable=settings["enable_mouse"]).grid(sticky='nw')
    ttk.Checkbutton(settings_frm, text="enable_bram_test", variable=settings["enable_bram_test"]).grid(sticky='nw')

    Label(dio_numeric_frm, text="DIO frequency divider (0-255)").grid(sticky='nw')
    Entry(dio_numeric_frm, textvariable=settings["dio_divider"]).grid(sticky='nw')
    
    dio_radio = [
        ttk.Radiobutton(mode_frm, text='DIO_MODE_OFF',                      value=0, variable=settings["dio_mode"]),
        ttk.Radiobutton(mode_frm, text='DIO_MODE_IMMUNITY_TOP_TO_BOTTOM',   value=1, variable=settings["dio_mode"]),
        ttk.Radiobutton(mode_frm, text='DIO_MODE_IMMUNITY_PORT_PAIRS',      value=2, variable=settings["dio_mode"]),
        ttk.Radiobutton(mode_frm, text='DIO_MODE_EMISSIONS',                value=3, variable=settings["dio_mode"])
    ]
    for r in dio_radio:
        r.grid(sticky='nw')
    text_box = Text(log_frame, height=20, width=80)
    text_box.pack()

    # Create a button widget
    ttk.Button(control_frm, text="Start", command=lambda: start_loop(text_box)).grid(column=0, row=0)
    ttk.Button(control_frm, text="Stop", command=stop_loop).grid(column=1, row=0)
    ttk.Button(control_frm, text="Quit", command=quit_app).grid(column=2, row=0)

    # Start the main event loop
    root.mainloop()