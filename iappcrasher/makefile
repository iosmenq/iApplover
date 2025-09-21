# Makefile for overlay dylib
TARGET = iapplove.dylib
SRC = overlay.m
SDK = /usr/share/SDKs/iPhoneOS.sdk
CC = clang

CFLAGS = -fobjc-arc -isysroot $(SDK) -arch arm64 -miphoneos-version-min=12.0
LDFLAGS = -dynamiclib -undefined dynamic_lookup

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRC) -o $(TARGET) -framework UIKit -framework Foundation

clean:
	rm -f $(TARGET)
