import json
import platform
import subprocess
import sys
import time
from multiprocessing import Pool

import psutil
from pyroute2 import IPDB


def str_dyeing(text):
    return (
        text.replace("<key>", "<span color='#aabbcc'>")
        .replace("<endval>", "</span><span color='#ccbbaa'>")
        .replace("<val>", "<span color='#ccbbaa'>")
        .replace("<end>", "</span>")
    )


def percent_dyeing(i):
    i = int(i)
    if i == 100:
        i = f"<span color='#f55fd7'>{i}</span>"
    elif 10 > i:
        i = f"<span color='#23fa4e'>  {i}</span>"
    elif 20 > i:
        i = f"<span color='#86f093'> {i}</span>"
    elif 50 > i:
        i = f"<span color='#c4f067'> {i}</span>"
    elif 75 > i:
        i = f"<span color='#f0e967'> {i}</span>"
    elif 90 > i:
        i = f"<span color='#f2935c'> {i}</span>"
    elif 100 > i:
        i = f"<span color='#f54966'> {i}</span>"
    else:
        i = "?"

    i += "%"
    return i


def distro_info():
    system = platform.uname()
    if system.node == "archlinux":
        distro = "<span color='#1793d1'> Archlinux</span>"
    else:
        distro = system.node
    return str_dyeing(
        f"""\
{distro}
<key>Linux<endval> {system.release}<end>
"""
    )


def ram_info():
    mem = psutil.virtual_memory()
    return str_dyeing(
        "<span color='#aaaadd'> RAM:<end>\n"
        + "  <key>used: <endval>{}%  {:4.2f} GB<end>\n".format(
            mem.percent, mem.used / (1024**3)
        )
        + "  <key>available:  <endval>{:4.2f} GB<end>\n".format(
            mem.available / (1024**3)
        )
        + "  <key>total:      <endval>{:4.2f} GB<end>\n".format(
            mem.total / (1024**3)
        )
    )


def cpu_info():
    _c = psutil.cpu_freq()
    cpu_freq = "{:.2f} {:.2f} {:.2f}".format(
        int(_c[0]) / 1000, int(_c[1]) / 1000, int(_c[2]) / 1000
    )

    cpu_temp = psutil.sensors_temperatures()["k10temp"][0].current

    t = percent_dyeing(int(psutil.cpu_percent()))
    cpu_usage = t + "\n"

    _n = 1
    for i in psutil.cpu_percent(percpu=True):
        i = percent_dyeing(i)

        if _n == 1:
            cpu_usage += f"   {i}"
        elif _n == 4:
            _n = 0
            cpu_usage += f" {i}\n"
        else:
            cpu_usage += f" {i}"

        _n += 1

    r = str_dyeing(
        f"""
<span color='#fa4160'>󰍛 AMD Ryzen™ 7 3700X<end>
<val>{psutil.cpu_count(logical=False)}<end> <key>cores<end>, \
<val>{psutil.cpu_count()}<end> <key>logical processors<end>
  <key>freq: <endval>{cpu_freq} GHz<end>
  <key>temp: <endval>{int(cpu_temp*100)/100} °C<end>
  <key>usage:<endval>{cpu_usage}<end>\
"""
    )
    t = [
        percent_dyeing(i)
        for i in [x / psutil.cpu_count() * 100 for x in psutil.getloadavg()]
    ]
    r += str_dyeing(f"  <key>avg: in 1m   5m  15m<end>\n")
    r += str_dyeing(f"        <val>{t[0]} {t[1]} {t[2]}<end>\n")

    return r


def gpu_info():
    gpu = json.loads(
        subprocess.run(
            ["gpustat", "--json"], capture_output=True
        ).stdout.decode()
    )["gpus"][0]
    return str_dyeing(
        f"""
<span color='#a6e3a1'>󰢮 {gpu["name"]}<end>
  <key>temp:<endval> {gpu["temperature.gpu"]}°C<end>
  <key>mem:<endval> {gpu["memory.used"]}/{gpu["memory.total"]} MB<end>
  <key>usage:<end>
    <key>gpu:<endval> {gpu["utilization.gpu"]}%<end>
    <key>encode:<endval> {gpu["utilization.enc"]}%<end>
    <key>decode:<endval> {gpu["utilization.dec"]}%<end>
  <key>fan:<endval> {gpu["fan.speed"]} RPM<end>
  <key>power:<endval> {gpu["power.draw"]}/{gpu["enforced.power.limit"]} W<end>
"""
    )


def net_info():
    ip = IPDB()
    interface = ip.interfaces[ip.routes["default"]["oif"]]["ifname"]

    dt = 1.0

    ul, dl = [-1, -1]

    try:
        t0 = time.time()
        counter = psutil.net_io_counters(pernic=True)[interface]
        last_tot = (counter.bytes_sent, counter.bytes_recv)
        time.sleep(dt)
        counter = psutil.net_io_counters(pernic=True)[interface]
        tot = (counter.bytes_sent, counter.bytes_recv)
        t1 = time.time()
        ul, dl = map(
            int, [(now - last) / (t1 - t0) for now, last in zip(tot, last_tot)]
        )
    except KeyError:
        ...

    ip.release()

    def net_speed_tweak(v):
        vB = ""
        vb = ""
        vBu = ""
        vbu = ""
        if 1024 > v:
            vB = str(v)
            vb = str(v * 8)
            vBu = "Byte/s"
            vbu = "bps"
        elif 1024**2 > v:
            vB = str(int((v / 1024) * 100) / 100)
            vb = str(int((v * 8 / 1000) * 100) / 100)
            vBu = "KB/s"
            vbu = "Kbps"
        elif 1024**3 > v:
            vB = str(int((v / 1024**2) * 100) / 100)
            vb = str(int((v * 8 / 1000**2) * 100) / 100)
            vBu = "MB/s"
            vbu = "Mbps"
        elif 1024**4 > v:
            vB = str(int((v / 1024**3) * 100) / 100)
            vb = str(int((v * 8 / 1000**3) * 100) / 100)
            vBu = "GB/s"
            vbu = "Gbps"
        return f"{' '*(6-len(vB))}{vB} {vBu}; {' '*(6-len(vb))}{vb} {vbu}"

    ul_unit = net_speed_tweak(ul)
    dl_unit = net_speed_tweak(dl)

    return str_dyeing(
        """
<span color='#aaaadd'>󰛳 Network:<end>
  <key> <endval>{}<end>
  <key> <endval>{}<end>

""".format(
            ul_unit, dl_unit
        )
    )


def pkg_update():
    yay = set(
        subprocess.run(["yay", "-Qua"], capture_output=True)
        .stdout.decode()
        .split("\n")
    )
    pm = set(
        subprocess.run(["checkupdates"], capture_output=True)
        .stdout.decode()
        .split("\n")
    )
    pm.remove("")
    yay.remove("")
    return str_dyeing(
        f"<span color='#aaaadd'> Pacman {len(pm)}; Yay {len(yay)}<end>"
    )


try:
    p = pkg_update()
    while True:
        with Pool(processes=5) as pl:
            t0 = time.time()
            data = {}
            n = pl.apply_async(net_info)
            d = pl.apply_async(distro_info)
            r = pl.apply_async(ram_info)
            c = pl.apply_async(cpu_info)
            g = pl.apply_async(gpu_info)
            data["tooltip"] = (
                d.get() + p + n.get() + r.get() + c.get() + g.get()
            )
            t1 = time.time()
            data["text"] = f"  I use arch btw;"
            data["tooltip"] += f"\n  last loop: {int((t1-t0)*1000)}ms"
            print(json.dumps(data))

except RecursionError:
    sys.exit()
