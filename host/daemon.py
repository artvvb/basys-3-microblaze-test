import threading

class daemon_handler:
    def __init__(self):
        self.end_loop = False
        self.thread = None
    def daemon_task(self, task, after_task):
        cycle = 0
        while not self.end_loop:
            cycle += 1
            task(cycle)
        after_task()
    def enlist_daemon(self, setup, task, after_task):
        if not self.thread is None and self.thread.is_alive(): return
        self.end_loop = False
        setup()
        self.thread = threading.Thread(target=lambda: self.daemon_task(task, after_task), args=())
        self.thread.daemon = True
        self.thread.start()
    def stop_daemon(self):
        if self.thread is None: return
        self.end_loop = True
        # can't spinlock here to wait for loop end or it blocks logging

if __name__ == '__main__':
    import tkinter as tk
    import logging
    import time
    import queue

    class daemon_example(daemon_handler):
        def enlist_daemon(self):
            return super().enlist_daemon(self.setup_task, self.loop_task, self.after_task)
        def stop_daemon(self):
            return super().stop_daemon()
        def setup_task(self):
            logging.info("Starting my task")
        def loop_task(self, cycle):
            logging.info(f"Cycle {cycle} starting")
            time.sleep(0.5)
            logging.info("This is an info message")
            time.sleep(0.5)
            # logging.warning("This is a warning message")
            # time.sleep(0.5)
            # logging.error("This is an error message")
            # time.sleep(0.5)
        def after_task(self):
            print()
            logging.info("Wrapped up")

    def configure_logger(text_handler):
        logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
        logger = logging.getLogger()
        logger.addHandler(text_handler)

    class TextHandler(logging.Handler):
        def __init__(self, text_widget: tk.Text):
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
                self.start_of_block = self.text_widget.index(tk.END)
            self.text_widget.insert(tk.END, msg + '\n')
            self.text_widget.configure(state='disabled') # disable user from writing to the block
        def mark_block(self, msg):
            print("marking?")
            if msg.split(' ')[0] == "Cycle":
                return True
            if msg == "Wrapped up": 
                return True
            return False
            

    root = tk.Tk()

    st = tk.Text(root, state='disabled')
    st.configure(font='TkFixedFont')
    st.pack()

    text_handler = TextHandler(st)
    configure_logger(text_handler)

    daemon = daemon_example()

    tk.Button(root, text="Start", command=lambda: daemon.enlist_daemon()).pack()
    tk.Button(root, text="Stop", command=lambda: daemon.stop_daemon()).pack()

    logging.info("Entering main loop")

    root.mainloop()