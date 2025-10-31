if __name__ == '__main__':
    from tkinter import *
    from tkinter import ttk
    import logging
    from datetime import datetime, timedelta
    from time import sleep
    import sys
    import os
    from daemon import daemon_handler
    from test import test_obj

    def init_logging(include_console=False, text_handler=None):
        logging.basicConfig(level=logging.INFO)
        log_formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
        logger = logging.getLogger()

        i = 0
        while os.path.exists("run_{i}.log"): i += 1
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

    # TextHandler for logging that connects the logger to a tkinter text widget.
    #   only maintains the last several "blocks", sections of text defined by a detectable pattern in the logged strings
    class TextHandler(logging.Handler):
        def __init__(self, text_widget):
            super().__init__()
            self.text_widget = text_widget
            self.start_of_block = "1.0"
        def emit(self, record):
            msg = self.format(record)
            self.text_widget.configure(state='normal') # allow writing to the block
            # if the controlling thread sends a block marker, clear everything before the previous and append latest
            if self.mark_block(msg):
                r = int(self.start_of_block.split('.')[0]) - 1
                if r > 0: self.text_widget.delete(1.0, f"{r}.0")
                self.start_of_block = self.text_widget.index(END)
            self.text_widget.insert(END, msg + '\n')
            self.text_widget.configure(state='disabled') # disable user from writing to the block
        def mark_block(self, msg):
            if msg.split(' ')[0] == "Cycle":
                return True
            if msg == "Wrapped up": 
                return True
            return False

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
        "dio_divider":          IntVar(root, 49),
        "dio_mode":             IntVar(root, 1),
        "bram_both_banks":      BooleanVar(root, True),
        "bram_max_address":     IntVar(root, 0x1fff),
        "bram_passes":          IntVar(root, 8000),
        "com_port":             sys.argv[1]
    }

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
    ttk.Checkbutton(settings_frm, text="bram_both_banks", variable=settings["bram_both_banks"]).grid(stick='nw')

    Label(dio_numeric_frm, text="DIO frequency divider").grid(sticky='nw')
    Entry(dio_numeric_frm, textvariable=settings["dio_divider"]).grid(sticky='nw')
    
    Label(dio_numeric_frm, text="BRAM write/read passes per loop").grid(sticky='nw')
    Entry(dio_numeric_frm, text="bram_passes", textvariable=settings["bram_passes"]).grid(sticky='nw')

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
    ttk.Button(control_frm, text="Start", command=lambda: test.enlist_daemon(settings)).grid(column=0, row=0)
    ttk.Button(control_frm, text="Stop", command=lambda: test.stop_daemon()).grid(column=1, row=0)
    ttk.Button(control_frm, text="Quit", command=lambda: quit_app(test)).grid(column=2, row=0)

    # Start the main event loop
    root.mainloop()