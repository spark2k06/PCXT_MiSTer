import os
import glob
import zipfile
import requests

URL = "http://www.retrowiki.es/download/file.php?id=20006264"
response = requests.get(URL)
open("jukost.zip", "wb").write(response.content)

with zipfile.ZipFile("jukost.zip", 'r') as zip_ref:
    zip_ref.extractall()

try:
    os.remove("jukost.zip")
except:
    print("Error while deleting file : jukost.zip")

zeros_length = 45056
rom_filename = "pcxt.rom"
xtidename = "ide_xtl.rom"
jukostname = "000o001.bin"

with open(rom_filename, "wb") as romf, open(xtidename, "rb") as f:
     romf.write(f.read())

with open(rom_filename, 'ab') as romf:
    romf.write(b'\x00' * zeros_length)

with open(rom_filename, "ab") as romf, open(jukostname, "rb") as f:
     romf.write(f.read())

try:
    os.remove(jukostname)
except:
    print("Error while deleting file : ", jukostname)
    