
#ifndef __UART_HH__
#define __UART_HH__

#include "device.h"

class UARTDevice : public Device {
public:
	UARTDevice(const char * path) : Device() {
		fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
		if (fd < 0) {
			perror("open serial port");
			exit(-1);
		}

		int ret;
		ret = fcntl(fd, F_SETFL, O_RDWR);
		if (ret < 0) {
			perror("fcntl");
			exit(-1);
		}

		struct termios tp;

		ret = tcgetattr(fd, &tp);
		if (ret < 0)
			perror("tcgetattr");

		cfmakeraw(&tp);

		cfsetspeed(&tp, B115200);

		ret = tcsetattr(fd, TCSANOW, &tp);
		if (ret < 0)
			perror("tcsetattr");

		ret = tcflush(fd, TCIOFLUSH);
		if (ret < 0)
			perror("tcflush");
	}

	virtual ~UARTDevice() {
		close(fd);
	}

	virtual ssize_t write(const void * buffer, size_t size) {
		return ::write(fd, buffer, size);
	}
	virtual ssize_t read(void * buffer, size_t size) {
		return ::read(fd, buffer, size);
	}

	virtual void flush() { tcflush(fd, TCIOFLUSH); }

private:
	int fd;
};

#endif

