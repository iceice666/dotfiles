import json
import pprint
import subprocess


def pacman():
    text = set(
        subprocess.run(["checkupdates"], capture_output=True)
        .stdout.decode()
        .split("\n")
    )
    text.remove("")

    return {"count": len(text), "text": text}


def yay():
    text = set(
        subprocess.run(["yay", "-Qua"], capture_output=True)
        .stdout.decode()
        .split("\n")
    )
    text.remove("")
    return {"count": len(text), "text": text}


def pkg_texts(pkg_list):
    text = ""
    for i in pkg_list:
        j = i.split(" ")
        text += f"<span color='#aabbcc'>{j[0]}</span> <span color='#ccbbaa'>{j[1]}</span><span color='#aaaadd'>  </span><span color='#ccbbaa'>{j[3]}</span>\n"
    return text


data = {}
pm = pacman()
ya = yay()
data["text"] = f" Pacman {pm['count']}; Yay {ya['count']}"
data[
    "tooltip"
] = f"<span color='#95f5ed'>Pacman</span><span color='#ccbbaa'> ({pm['count']})</span>\n"
data["tooltip"] += pkg_texts(pm["text"])

data[
    "tooltip"
] += f"\n<span color='#faf48e'>Yay</span><span color='#ccbbaa'>  ({ya['count']})</span>\n"
data["tooltip"] += pkg_texts(ya["text"])

print(json.dumps(data))
