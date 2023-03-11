import os
import glob
import zipfile
import requests

if __name__ == "__main__":
    URL = "http://minuszerodegrees.net/bios/BIOS_5160_08NOV82.zip"
    response = requests.get(URL)
    open("ibm5160.zip", "wb").write(response.content)

    with zipfile.ZipFile("ibm5160.zip", 'r') as zip_ref:
        zip_ref.extractall()

    try:
        os.remove("ibm5160.zip")
    except:
        print("Error while deleting file : ibm5160.zip")
        
    try:
        os.remove("README.TXT")
    except:
        print("Error while deleting file : README.TXT")

    rom_filename = "pcxt.rom"
    ibm5160_basename = "BIOS_5160_08NOV82_"

    with open(rom_filename, "wb") as romf, open(ibm5160_basename + "U19_5000027_27256.BIN", "rb") as f:
        romf.write(f.read())

    with open(rom_filename, "ab") as romf, open(ibm5160_basename + "U18_1501512.BIN", "rb") as f:
        romf.write(f.read())

    fileList = glob.glob(ibm5160_basename + "*.BIN")

    for filePath in fileList:
        try:
            os.remove(filePath)
        except:
            print("Error while deleting file : ", filePath)

