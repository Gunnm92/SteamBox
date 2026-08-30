CC = gcc
CFLAGS = -O2 -Wall
LIBS = -lwayland-client -lxkbcommon -lm
PROTO_SRC = protocols/wlr-virtual-pointer-unstable-v1-protocol.c \
            protocols/virtual-keyboard-unstable-v1-protocol.c
TARGET = evdev-bridge-native

all: $(TARGET)

$(TARGET): bridge.c $(PROTO_SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LIBS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)/usr/local/bin/$(TARGET)

.PHONY: all clean install
