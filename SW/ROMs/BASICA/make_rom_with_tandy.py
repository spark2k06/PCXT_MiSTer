import os
import glob
import zipfile
import requests

if __name__ == "__main__":
    URL = "http://retrograde.inf.ua/files/T1K_0101.ZIP"
    response = requests.get(URL)
    open("T1K_0101.ZIP", "wb").write(response.content)

    with zipfile.ZipFile("T1K_0101.ZIP", 'r') as zip_ref:
        zip_ref.extractall()

    try:
        os.remove("T1K_0101.ZIP")
    except:
        print("Error while deleting file : TK1_0101.ZIP")

    rom_filename = "tandy.rom"
    tandy_filename = "TANDY1T1.010"

    with open(rom_filename, "wb") as romf, open(tandy_filename, "rb") as f:
        romf.write(f.read())

    fileList = glob.glob(tandy_filename)

    for filePath in fileList:
        try:
            os.remove(filePath)
        except:
            print("Error while deleting file : ", filePath)

