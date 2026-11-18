# The device is 32-bit armeabi-v7a, so a straight arm-linux-gnueabihf build.
# -nostdlib keeps the binary dependency-free; -no-pie because a static PIE
# would need self-relocation code we have no loader for.
CC    = arm-linux-gnueabihf-gcc
STRIP = arm-linux-gnueabihf-strip
CFLAGS ?= -Os -marm -nostdlib -static -no-pie -fno-stack-protector \
          -fno-builtin -Wall -Wextra

su: su.c
	$(CC) $(CFLAGS) -o $@ $<
	$(STRIP) $@

clean:
	rm -f su

.PHONY: clean
