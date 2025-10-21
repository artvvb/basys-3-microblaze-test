from tkinter import *
from tkinter import ttk
import logging
from datetime import datetime, timedelta
import time
from time import sleep
import threading
import sys

def init_logging(include_console=False, text_handler=None):
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

    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    logger = logging.getLogger()
    logger.addHandler(text_handler)

class TextHandler(logging.Handler):
    def __init__(self, text_widget):
        super().__init__()
        self.text_widget = text_widget
    def emit(self, record):
        msg = f"{record.levelname}: {self.format(record)}"
        def append():
            self.text_widget.configure(state='normal')
            self.text_widget.insert(END, msg + '\n')
            self.text_widget.configure(state='disabled')
            self.text_widget.yview(END)
        self.text_widget.after(0, append)

def dummy_cycle_loop(done_callback):
    n = 0
    while not done_callback():
        targettime = datetime.now() + timedelta(seconds=1)

        logging.info(f"Cycle {n}")
        n += 1
        timeleft = (targettime - datetime.now()).total_seconds()
        if timeleft > 0:
            time.sleep(timeleft)

loop_done = False

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
        "dio_divider":          IntVar(root, 3),
        "dio_mode":             IntVar(root, 1),
        "com_port":             sys.argv[1]
    }

    from daemon import daemon_handler
    from test import test_obj

    class test_daemon(daemon_handler):
        def enlist_daemon(self, settings):
            self.settings = settings
            self.test_obj = test_obj()
            return super().enlist_daemon(self.setup_task, self.loop_task, self.after_task)
        def stop_daemon(self):
            return super().stop_daemon()
        def setup_task(self):
            self.test_obj.setup_test(self.settings)
            logging.info("Starting my task")
        def loop_task(self, cycle):
            logging.info(f"Cycle {cycle} starting")
            self.test_obj.run_test()
        def after_task(self):
            self.test_obj.stop_test()
            logging.info("Wrapped up")

    test = test_daemon()

    # Button(root, text="Start", command=lambda: daemon.enlist_daemon()).pack()
    # Button(root, text="Stop", command=lambda: daemon.stop_daemon()).pack()

    # thread = None
    # def start_loop(text_box):
    #     global thread, loop_done
    #     if not thread is None: return

    #     logging.info("Starting Test")
    #     logging.info(f'Setting enable_xadc:         {settings["enable_xadc"].get()}')
    #     logging.info(f'Setting enable_flash_id:     {settings["enable_flash_id"].get()}')
    #     logging.info(f'Setting enable_flash_verify: {settings["enable_flash_verify"].get()}')
    #     logging.info(f'Setting enable_uart_echo:    {settings["enable_uart_echo"].get()}')
    #     logging.info(f'Setting enable_dio_test:     {settings["enable_dio_test"].get()}')
    #     logging.info(f'Setting enable_mouse:        {settings["enable_mouse"].get()}')
    #     logging.info(f'Setting enable_bram_test:    {settings["enable_bram_test"].get()}')
    #     logging.info(f'Setting dio_mode:            {settings["dio_mode"].get()}')
    #     logging.info(f'Setting com_port:            {settings["com_port"]}')
    #     logging.info(f'Setting dio_divider:         {settings["dio_divider"].get()}')

    #     # thread = threading.Thread(target=lambda: dummy_cycle_loop(args=())
    #     thread = threading.Thread(target=lambda: run_test(
    #         done_callback = lambda: loop_done,
    #         settings = settings
    #     ), args=())
    #     thread.daemon = True
    #     thread.start()
    #     logging.info("Started test loop")

    # def stop_loop():
    #     global loop_done, thread
    #     loop_done = True
    #     logging.info(f'Halting test')
    #     if thread is None:
    #         logging.info(f'No test running to stop')
    #         return
    #     while thread.is_alive():
    #         logging.info("Waiting for test to finish...")
    #         sleep(1)
    #     loop_done = False
    #     logging.info("Test thread closed")
    #     thread = None

    frm             = ttk.Frame(root, padding=10)
    mode_frm        = ttk.Frame(frm, padding=10)
    settings_frm    = ttk.Frame(frm, padding=10)
    dio_numeric_frm = ttk.Frame(frm, padding=10)
    control_frm     = ttk.Frame(frm, padding=10)
    log_frame       = ttk.Frame(frm, padding=10)
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

    init_logging(False, TextHandler(text_box))

    def quit_app(test: test_daemon):
        test.stop_daemon()
        logging.info(f"Quitting test app")
        root.destroy()

    # Create a button widget
    # ttk.Button(control_frm, text="Start", command=lambda: start_loop(text_box)).grid(column=0, row=0)
    # ttk.Button(control_frm, text="Stop", command=stop_loop).grid(column=1, row=0)
    ttk.Button(control_frm, text="Start", command=lambda: test.enlist_daemon(settings)).grid(column=0, row=0)
    ttk.Button(control_frm, text="Stop", command=lambda: test.stop_daemon()).grid(column=1, row=0)
    ttk.Button(control_frm, text="Quit", command=lambda: quit_app(test)).grid(column=2, row=0)

    # Start the main event loop
    root.mainloop()

# To reexport hardware and add error AXI GPIO out conditions to the sw image.
# To stabilize start/stop/restart loops
# To make sure timeout errors are logged and that flash verify can error
