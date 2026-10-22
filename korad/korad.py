# ==============================================================================
# Filename:         korad.py
# Description:      Cross platform tui for single channel programable Korad power
#                   supplies via a serial tty.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-8-6
# License:          AGPL-3.0
# ==============================================================================


import argparse
import atexit
from datetime import datetime
import enum
import logging
import os
import signal
import struct
import sys
import threading
import time
import traceback
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Callable

import serial
from rich import print
from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.logging import RichHandler
from rich.panel import Panel
from rich.prompt import Prompt
from rich.table import Table
from rich.text import Text

if os.name == "nt":
    import msvcrt
    import win32api
    import win32event
    import winerror
elif os.name == "posix":
    import fcntl
    import termios
else:
    raise Exception("Unsupported os")

PROG_GUID = "32d5eb97-79e5-4882-b9f0-436c5d1a1797"

NS_PER_SEC = 1e9

PORT_READ_TIMEOUT_SEC = 2
THREAD_JOIN_TIMEOUT_SEC = 5.0

class GlobalState:
    __instance = None

    def __new__(cls):
        if cls.__instance is not None:
            return cls.__instance
        cls.__instance = super().__new__(cls)
        return cls.__instance

    def __init__(self):
        if hasattr(self, '_initialized'):
            return

        self._initialized = True
        self.signaled = False
        self.die = False
        self.errored = False
        self.refresh_event = threading.Event()
        self.ithread: threading.Thread = None
        self.pthread: threading.Thread = None
        self.old_title = "UNK"

        # Set initial render
        self.refresh_event.set()

    @staticmethod
    def get_state():
        return GlobalState()

def readfile(path):
    with open(path) as f:
        return f.read()

def timens_iso8601():
    return datetime.fromtimestamp(time.time_ns()/NS_PER_SEC).isoformat()

class ProcessLockOsOps(ABC):
    @abstractmethod
    def init_lock(self) -> bool: ...

    @abstractmethod
    def signal_lock(self) -> bool: ...

    @abstractmethod
    def wait_lock(self) -> bool: ...

    @abstractmethod
    def poll_lock(self) -> bool: ...

    @abstractmethod
    def release_lock(self) -> bool: ...

if os.name == "nt":
    class WindowsProcLockOps(ProcessLockOsOps):
        def __init__(self, guid):
            self.__guid = guid
            self.__hndl = None

        def init_lock(self):
            self.__hndl = win32event.CreateEvent(None, True, False, f"Global\\{self.__guid}")
            if win32api.GetLastError() == winerror.ERROR_ALREADY_EXISTS:
                win32api.CloseHandle(self.__hndl)
                return False

            return True

        def signal_lock(self):
            # We already have the lock
            if self.__hndl:
                return

            try:
                hndl = win32event.OpenEvent(win32event.EVENT_MODIFY_STATE | win32event.SYNCHRONIZE, False, f"Global\\{self.__guid}")
                win32event.SetEvent(hndl)
                win32api.CloseHandle(hndl)
            except Exception:
                pass

        def wait_lock(self):
            if self.__hndl:
                return True

            return self.init_lock()

        def poll_lock(self):
            return win32event.WaitForSingleObject(self.__hndl, 0) == win32event.WAIT_OBJECT_0

        def release_lock(self):
            if self.__hndl:
                win32event.ResetEvent(self.__hndl)
                win32api.CloseHandle(self.__hndl)
                self.__hndl = None

elif os.name == "posix":
    class LinuxProcLockOps(ProcessLockOsOps):
        def __init__(self, guid):
            if os.access("/run/lock", os.R_OK | os.W_OK):
                self.__fpath = f"/run/lock/korad-{guid}.lock"
            else:
                if not os.access("/tmp", os.R_OK | os.W_OK):
                    raise Exception("No permissions, cannot create lock file at /run/lock or /tmp")
                self.__fpath = f"/tmp/korad-{guid}.lock"

            self.__signaled = False

        def __pid_alive(self, pid):
            try:
                os.kill(pid, 0)
                return True
            except OSError:
                return False

        def init_lock(self):
            try:
                with open(self.__fpath, "x") as f:
                    f.write(str(os.getpid()))

            except FileExistsError:
                pid = int(readfile(self.__fpath))
                if self.__pid_alive(pid):
                    return False

                logging.warning(f"Removing stale lock file (pid {pid} is dead)")
                try:
                    os.remove(self.__fpath)
                    with open(self.__fpath, "w") as f:
                        f.write(str(os.getpid()))
                except OSError:
                    logging.error(f"Failed to create lock file after stale pid")
                    return False

            signal.signal(signal.SIGINT, self.__sig_handler)
            signal.signal(signal.SIGTERM, self.__sig_handler)

            return True

        def __sig_handler(self, signum, frame):
            self.__signaled = True

        def signal_lock(self):
            try:
                pid = readfile(self.__fpath)
                if pid == str(os.getpid()):
                    return

                os.kill(int(pid), signal.SIGTERM)
            except Exception:
                pass

        def wait_lock(self):
            if os.path.exists(self.__fpath) and (readfile(self.__fpath) == str(os.getpid())):
                return True

            return self.init_lock()

        def poll_lock(self):
            return self.__signaled

        def release_lock(self):
            os.remove(self.__fpath)
else:
    raise Exception("Unsupported os")

class ProcessSingletonLock:
    def __init__(self):
        if os.name == "nt":
            self._lock_ops = WindowsProcLockOps(PROG_GUID)
        elif os.name == "posix":
            self._lock_ops = LinuxProcLockOps(PROG_GUID)
        else:
            raise Exception("Unsupported os")

    def __enter__(self):
        if not self._lock_ops.init_lock():
            should_kill = prompt_yn("Another instance of Korad is already running. Would you like to kill it?")
            if not should_kill:
                exit(0)

            self._lock_ops.signal_lock()

            attempts = 15
            for i in range(attempts):
                if self._lock_ops.wait_lock():
                    break

                print(f"[{i+1}/{attempts}] Waiting for shutdown...")
                time.sleep(1)

            else:
                # Couldnt confirm shutdown
                print("[red]Failed to receive close signal from other instance[/red]")
                exit(1)

        atexit.register(self._lock_ops.release_lock)
        return self

    def poll(self):
        return self._lock_ops.poll_lock()

    def __exit__(self, exc_type, exc, tb):
        self._lock_ops.release_lock()
        atexit.unregister(self._lock_ops.release_lock)

class Settings(enum.Enum):
    IDENT = 1
    SET_CURRENT = 2
    SET_VOLTAGE = 3
    ACT_CURRENT = 4
    ACT_VOLTAGE = 5
    OUTPUT = 6
    OUTPUT_MODE = 7
    BEEP = 8
    LOCK = 9
    STATUS = 10
    OCP_MODE = 11
    OVP_MODE = 12

class Commands(enum.StrEnum):
    IDENT = "*IDN?"
    QUERY_SET_CURRENT = "ISET1?"
    QUERY_SET_VOLTAGE = "VSET1?"
    QUERY_ACT_CURRENT = "IOUT1?"
    QUERY_ACT_VOLTAGE = "VOUT1?"
    QUERY_STATUS = "STATUS?"

@dataclass
class Setting:
    rx_function: Callable[[bytes], str] | None
    value: str = "Unknown"

@dataclass
class SettingQuery:
    rx_setting: Settings | list[Settings]
    poll_interval: float
    last_ns: float = 0.0

def bytes_to_str(b):
    return b.decode()

def read_status_output(b):
    status = b[0]
    output = status & 1 << 6
    return "ON" if output else "OFF"

def read_status_beep(b):
    status = b[0]
    beep = status & 1 << 4
    return "ON" if beep else "OFF"

def read_status_lock(b):
    status = b[0]
    lock = status & 1 << 5
    return "UNLOCKED" if lock else "LOCKED"

def read_status_dbg(b):
    status = b[0]
    sb = ""
    for i in range(8):
        sb += f"{status >> i & 1} "
    return sb

def read_status_output_mode(b):
    status = b[0]

    output = status & 1 << 6
    output_mode = status & 1

    if not output:
        return "N/A"

    return "CV" if output_mode else "CC"

def read_status_ocp(b):
    status = b[0]
    ocp = status & 1 << 5
    return "Enabled" if ocp else "Disabled"

def read_status_ovp(b):
    status = b[0]
    ovp = status & 1 << 7
    return "Enabled" if ovp else "Disabled"

SETTINGS = {
    Settings.IDENT :        Setting(bytes_to_str),
    Settings.SET_CURRENT :  Setting(bytes_to_str),
    Settings.SET_VOLTAGE :  Setting(bytes_to_str),
    Settings.ACT_CURRENT :  Setting(bytes_to_str),
    Settings.ACT_VOLTAGE :  Setting(bytes_to_str),
    Settings.OUTPUT :       Setting(read_status_output),
    Settings.OUTPUT_MODE :  Setting(read_status_output_mode),
    Settings.BEEP :         Setting(read_status_beep),
    Settings.OCP_MODE :     Setting(read_status_ocp),
    Settings.OVP_MODE :     Setting(read_status_ovp),
    }

SETTINGS_QUERIES = {
    Commands.IDENT:             SettingQuery(Settings.IDENT, 10),
    Commands.QUERY_SET_CURRENT: SettingQuery(Settings.SET_CURRENT, 2),
    Commands.QUERY_SET_VOLTAGE: SettingQuery(Settings.SET_VOLTAGE, 2),
    Commands.QUERY_ACT_CURRENT: SettingQuery(Settings.ACT_CURRENT, 0),
    Commands.QUERY_ACT_VOLTAGE: SettingQuery(Settings.ACT_VOLTAGE, 0),
    Commands.QUERY_STATUS:      SettingQuery([Settings.OUTPUT, Settings.OUTPUT_MODE, Settings.BEEP, Settings.OCP_MODE, Settings.OVP_MODE], 1),
    }

COMMANDS_HELP = [
    "ISET<X>:<VALUE> - Set the current for channel X to VALUE",
    "VSET<X>:<VALUE> - Set the voltage for channel X to VALUE",
    "BEEP<0|1> - Turn the beep on or off",
    "OUT<0|1> - Turn the output on or off",
    "RCL<BANK> - Recall a panel setting from bank BANK",
    "SAV<BANK> - Save the panel setting to recall bank BANK",
    "OCP<0|1> - Set OCP on or off",
    "OVP<0|1> - Set OVP on or off"
    ]


def prompt_yn(question, default="n"):
    while True:
        answer = Prompt.ask(
            question,
            choices=["y", "n"],
            default=default
        ).strip().lower()

        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False

        print("[red]Please answer with y/n or yes/no.[/red]")

def port_write(port, s):
    port.write(s.encode())

def port_read(port: serial.Serial):
    data = None
    start = time.time()

    while time.time() < (start + PORT_READ_TIMEOUT_SEC):
        data = port.read_all()
        if data is not None and data != b"":
            return data

    else:
        raise TimeoutError("Timeout reading from port")

def port_clear(port: serial.Serial):
    data = port.read_all()
    return len(data) if data else 0

def poll_state(port: serial.Serial, port_lock):
    updated = False

    for rx_cmd, query in SETTINGS_QUERIES.items():
        if query.poll_interval > 0 and (time.time_ns() - query.last_ns) < (query.poll_interval * NS_PER_SEC):
            continue

        with port_lock:
            if port_clear(port):
                logging.warning("Unread bytes in port during poll write, discarding")

            port_write(port, rx_cmd)

            try:
                rx = port_read(port)
                mapped_settings_keys = query.rx_setting if isinstance(query.rx_setting, list) else [query.rx_setting]
                mapped_settings_values = map(lambda k: SETTINGS[k], mapped_settings_keys)

                for setting_key, setting_value in zip(mapped_settings_keys, mapped_settings_values):
                    tmp = setting_value.rx_function(rx)
                    if tmp != setting_value.value:
                        setting_value.value = tmp
                        updated = True

                query.last_ns = time.time_ns()

            except TimeoutError as e:
                continue

    return updated

def create_layout():
    layout = Layout()
    layout.split_column(Layout(name="output"), Layout(name="input"))
    return layout

def update_info_box(layout):
    table = Table.grid(padding=1)
    table.add_column("content")

    utable = Table.grid(padding=(0, 3))
    utable.add_column("tag")
    utable.add_column("display", style="magenta")
    utable.add_row("Unit:", SETTINGS[Settings.IDENT].value, style="green")
    utable.add_row("Output:", SETTINGS[Settings.OUTPUT].value)
    utable.add_row("Output Mode:", SETTINGS[Settings.OUTPUT_MODE].value)
    utable.add_row("Beep:", SETTINGS[Settings.BEEP].value)
    utable.add_row("OCP:", SETTINGS[Settings.OCP_MODE].value)
    utable.add_row("OVP:", SETTINGS[Settings.OVP_MODE].value)
    table.add_row(utable)

    stable = Table.grid(padding=(0, 3))
    stable.add_column("setting")
    stable.add_column("set", style="blue")
    stable.add_column("act", style="magenta")
    stable.add_row("Setting", "Set", "Actual", style="green")
    stable.add_row("Voltage:", SETTINGS[Settings.SET_VOLTAGE].value, SETTINGS[Settings.ACT_VOLTAGE].value)
    stable.add_row("Current:", SETTINGS[Settings.SET_CURRENT].value, SETTINGS[Settings.ACT_CURRENT].value)
    table.add_row(stable)

    htable = Table.grid(padding=(0, 3))
    htable.add_column("msg")
    htable.add_row("Input Command Usage:", style="green")
    for help in COMMANDS_HELP:
        htable.add_row(help)
    table.add_row(htable)

    layout.update(Panel(table, title="Korad", title_align="left"))

if os.name == "nt":
    kbhit = msvcrt.kbhit
    getch = lambda : msvcrt.getch().decode()
elif os.name == "posix":
    def init_term_input():
        __stdin_fd = sys.stdin.fileno()
        __stdin_old_term = termios.tcgetattr(__stdin_fd)
        __stdin_new_term = termios.tcgetattr(__stdin_fd)
        __stdin_new_term[3] = (__stdin_new_term[3] & ~termios.ICANON & ~termios.ECHO)
        termios.tcsetattr(__stdin_fd, termios.TCSAFLUSH, __stdin_new_term)
        atexit.register(termios.tcsetattr, __stdin_fd, termios.TCSAFLUSH, __stdin_old_term)

    def kbhit():
        return struct.unpack('I', fcntl.ioctl(sys.stdin.fileno(), termios.FIONREAD, struct.pack('I', 0)))[0] > 0
    def getch():
        return sys.stdin.read(1)

else:
    raise Exception("Unsupported os")

def handle_keyboard_input(inputbuf:list[str], port, port_lock):
    if kbhit():
        try:
            char = getch()
            if char == "\xe0" or char == "\x00":
                getch()
                return False

            if char == "\r" or char == "\n":
                cmd = "".join(inputbuf)
                inputbuf.clear()

                with port_lock:
                    if port_clear(port):
                        logging.warning("Unread bytes in port during command write, discarding")

                    port_write(port, cmd)

            elif char == "\b" or char == "\x7f" or char == "\x08":
                if len(inputbuf) > 0:
                    inputbuf.pop()
            else:
                inputbuf.append(char)

            return True
        except UnicodeDecodeError as e:
            logging.error(f"Error unicode decode: {e}")
            return False
    else:
        return False

inputgrow = True
def test_input(inputbuf, _port, _port_lock):
    global inputgrow

    if len(inputbuf) == 0:
        inputgrow = True
    elif len(inputbuf) == 26:
        inputgrow = False

    if inputgrow:
        inputbuf.append(chr(len(inputbuf) + 97))
    else:
        inputbuf.pop()

    time.sleep(.05)
    return True

def input_thread(input_func, layout: Layout, port, port_lock):
    gs = GlobalState()
    uinput = []
    update = True
    while 1:
        if gs.die:
            return

        output_table = Table.grid(padding=(1, 1))
        output_table.add_column("text")

        if input_func(uinput, port, port_lock):
            update = True

        if update:
            output_table.add_row(Panel(Text("".join(uinput)), title="INPUT",title_align="left", width=Console().size.width))
            layout.update(output_table)

            gs.refresh_event.set()

            update = False

def poll_thread(poll_func, layout, port, port_lock):
    gs = GlobalState()
    updated = True
    while 1:
        if updated:
            update_info_box(layout)
            gs.refresh_event.set()
            updated = False

        if gs.die:
            return

        if poll_func(port, port_lock):
            updated = True

def set_terminal_title(title):
    if os.name == "nt":
        win32api.SetConsoleTitle(title)
    else:
        sys.stdout.write(f"\033]0;{title}\007")
        sys.stdout.flush()

def get_terminal_title():
    if os.name == "nt":
        return win32api.GetConsoleTitle()
    else:
        return ""

def main():
    gs = GlobalState()
    gs.old_title = get_terminal_title()
    set_terminal_title("Korad PSU Controller")

    parser = argparse.ArgumentParser(description="Open a connection to a specified COM port.")
    parser.add_argument("-p", "--port", help="COM port to connect to (e.g., COM3 or /dev/ttyUSB0)", required=False)
    parser.add_argument("--input-test-mode", help="Generate test input for terminal viewing testing", action="store_true", required=False)
    parser.add_argument("--log-level", help="Log Level", choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], default="WARNING")
    args = parser.parse_args()

    port = args.port
    if port is None:
        port = input("Enter the COM port:>")

    with ProcessSingletonLock() as process_lock:
        try:
            serial_port = serial.Serial(
                port=port,
                baudrate=9600,
                bytesize=serial.EIGHTBITS,
                stopbits=serial.STOPBITS_ONE,
                parity=serial.PARITY_NONE,
                xonxoff=False,
                rtscts=False,
                dsrdtr=False
            )
            serial_lock = threading.Lock()
        except serial.SerialException as e:
            print(f"Failed to open port {args.port}: {e}")
            quit(1)

        if os.name == "posix":
            init_term_input()

        layout = create_layout()
        with Live(layout, auto_refresh=False) as live:
            logging.basicConfig(level=args.log_level, handlers=[RichHandler(console=live.console)])

            ithread_args = [handle_keyboard_input if not args.input_test_mode else test_input]
            ithread_args += [layout["input"], serial_port, serial_lock]
            gs.ithread = threading.Thread(target=input_thread, args=ithread_args, daemon=True)
            gs.ithread.start()

            gs.pthread = threading.Thread(target=poll_thread, args=[poll_state, layout["output"], serial_port, serial_lock], daemon=True)
            gs.pthread.start()

            # Loop until exception or signaled by new instance to die
            try:
                main_loop(process_lock, live)
            # Error in main loop
            except Exception:
                print(traceback.format_exc())
                gs.errored = True
            # Ctrl+C
            except KeyboardInterrupt:
                pass

            # Exit flow, join threads
            gs.die = True
            gs.ithread.join(THREAD_JOIN_TIMEOUT_SEC)
            gs.pthread.join(THREAD_JOIN_TIMEOUT_SEC)

def main_loop(proc_lock, live):
    gs = GlobalState()
    while 1:
        if gs.refresh_event.wait(timeout=0):
            gs.refresh_event.clear()

            live.refresh()

        if proc_lock.poll():
            gs.signaled = True
            return

if __name__ == "__main__":
    def _cleanup():
        gs = GlobalState()
        if gs.errored:
            print("[red]Exiting due to error[/red]")
        else:
            print("[yellow]Exiting...[/yellow]")

        if gs.signaled:
            print("[yellow]Received shutdown event from new instance[/yellow]")


        if (gs.ithread and gs.ithread.is_alive()) \
        or (gs.pthread and gs.pthread.is_alive()):
            print("[red]Failed to cleanup threads[/red]")

        sys.stdout.flush()

        set_terminal_title(gs.old_title)
    atexit.register(_cleanup)
    main()



