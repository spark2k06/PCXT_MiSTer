######################################################################
#
# Project:     XTIDE Universal BIOS, Serial Port Server
#
# File:        makefile
#
# Use with GNU Make
#

HEADERS = library/Library.h linux/LinuxFile.h linux/LinuxSerial.h library/File.h library/FlatImage.h

BASE     = arm-linux-gnueabihf
CXX      = $(BASE)-g++
CXXFLAGS = -g

LINUXOBJS = build/linux.o build/checksum.o build/serial.o build/process.o build/image.o

build/serdrive:	$(LINUXOBJS)
	$(CXX) -lrt -o build/serdrive $(LINUXOBJS)

build/linux.o:	linux/Linux.cpp $(HEADERS)
	$(CXX) -c $(CXXFLAGS) linux/Linux.cpp -o build/linux.o

build/checksum.o:	library/Checksum.cpp $(HEADERS)
	$(CXX) -c $(CXXFLAGS) library/Checksum.cpp -o build/checksum.o

build/serial.o:	library/Serial.cpp $(HEADERS)
	$(CXX) -c $(CXXFLAGS) library/Serial.cpp -o build/serial.o

build/process.o:	library/Process.cpp $(HEADERS)
	$(CXX) -c $(CXXFLAGS) library/Process.cpp -o build/process.o

build/image.o:	library/Image.cpp $(HEADERS)
	$(CXX) -c $(CXXFLAGS) library/Image.cpp -o build/image.o


clean:
	rm -rf ./build/*

build/checksum_test.exe:	library/checksum.cpp
	$(CXX) /Febuild/checksum_test.exe /Ox library/checksum.cpp /Fobuild/checksum_test.obj -D CHECKSUM_TEST

