import os
import glob
import zipfile
import requests

URL = "http://www.minuszerodegrees.net/bios/BIOS_5160_09MAY86.zip"
response = requests.get(URL)
open("ibm5160.zip", "wb").write(response.content)

with zipfile.ZipFile("ibm5160.zip", 'r') as zip_ref:
    zip_ref.extractall()

try:
    os.remove("ibm5160.zip")
except:
    print("Error while deleting file : ibm5160.zip")

rom_filename = "boot.rom"
ibm5160_basename = "BIOS_5160_09MAY86_"

with open(rom_filename, "wb") as romf, open(ibm5160_basename + "U19_62X0819_68X4370_27256_F000.bin", "rb") as f:
     romf.write(f.read())

with open(rom_filename, "ab") as romf, open(ibm5160_basename + "U18_59X7268_62X0890_27256_F800.bin", "rb") as f:
     romf.write(f.read())

fileList = glob.glob(ibm5160_basename + "*.bin")

for filePath in fileList:
    try:
        os.remove(filePath)
    except:
        print("Error while deleting file : ", filePath)
        

    