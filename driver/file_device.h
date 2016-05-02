
#ifndef __FILEDEV_HH__
#define __FILEDEV_HH__

#include "device.h"

class FileDevice : public Device {
public:
	FileDevice(const char * path) {
		fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IRWXU);
		if (fd < 0) {
			perror("open file output port");
			exit(-1);
		}
	}

	virtual ~FileDevice() {
		close(fd);
	}

	virtual ssize_t write(const void * buffer, size_t size) {
		return ::write(fd, buffer, size);
	}
	virtual ssize_t read(void * buffer, size_t size) {
		exit(0);
		return -1;
	}

private:
	int fd;
};

#endif

