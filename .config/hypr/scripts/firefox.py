import json
import pprint
import subprocess
from time import sleep

subprocess.run(["hyprctl", "dispatch", "exec", "firefox"])

sleep(5)

text = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True)
tlist = []
for i in json.loads(text.stdout.decode()):
    # pprint.PrettyPrinter().pprint(i)
    if i["class"] == "firefox":
        tlist.append(i["address"])
for n, i in enumerate(tlist):
    subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{i}"])
    subprocess.run(["hyprctl", "dispatch", "movetoworkspacesilent", f"{n+1}"])
