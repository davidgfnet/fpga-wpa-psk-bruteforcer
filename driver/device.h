
#ifndef __DEVICE_HH__
#define __DEVICE_HH__

class Device {
public:
	Device() {
		this->dnum = Device::device_counter++;
	}
	virtual ~Device() {}

	virtual ssize_t write(const void * buffer, size_t size) = 0;
	virtual ssize_t read(void * buffer, size_t size) = 0;

	virtual void flush() {}

public:
	int dnum;

	static int device_counter;
};

int Device::device_counter = 0;

#endif

