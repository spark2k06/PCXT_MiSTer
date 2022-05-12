import os
import glob
import zipfile
import requests

URL = "http://www.minuszerodegrees.net/rom/bin/IBM/IBM%205150%20-%20Cassette%20BASIC%20version%20C1.00.zip"
response = requests.get(URL)
open("ibmbasic.zip", "wb").write(response.content)

with zipfile.ZipFile("ibmbasic.zip", 'r') as zip_ref:
    zip_ref.extractall()

try:
    os.remove("ibmbasic.zip")
except:
    print("Error while deleting file : ibmbasic.zip")

zeros_length = 24576
rom_filename = "boot0.rom"
ibmbasic_basename = "IBM 5150 - Cassette BASIC version C1.00"
bios_filename = "bios.com"

with open(rom_filename, 'wb') as romf:
    romf.write(b'\x00' * zeros_length)

with open(rom_filename, "ab") as romf, open(ibmbasic_basename + " - U29 - 5700019.bin", "rb") as f:
     romf.write(f.read())

with open(rom_filename, "ab") as romf, open(ibmbasic_basename + " - U30 - 5700027.bin", "rb") as f:
     romf.write(f.read())

with open(rom_filename, "ab") as romf, open(ibmbasic_basename + " - U31 - 5700035.bin", "rb") as f:
     romf.write(f.read())

with open(rom_filename, "ab") as romf, open(ibmbasic_basename + " - U32 - 5700043.bin", "rb") as f:
     romf.write(f.read())

with open(rom_filename, "ab") as romf, open(bios_filename, "rb") as f:
     romf.write(f.read())

fileList = glob.glob(ibmbasic_basename + "*.bin")

for filePath in fileList:
    try:
        os.remove(filePath)
    except:
        print("Error while deleting file : ", filePath)
        

    