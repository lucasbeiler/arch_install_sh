CFLAGS = -fPIE -pie -fPIC -fstack-protector-strong -fstack-protector-all -fstack-clash-protection -D_FORTIFY_SOURCE=3 -g -O2 -ftrivial-auto-var-init=pattern -Wformat-security -Wconversion -Werror=format-security -Wall -Wextra -flto -fvisibility=hidden -fsanitize=cfi -fcf-protection=full -mshstk
LDFLAGS = -Wl,-z,relro,-z,now -s

TARGET=allow_new_usb_tmp
CC=clang
OBJS=main.c

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)