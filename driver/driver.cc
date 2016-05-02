
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources


#include <stdio.h>
#include <iostream>
#include <fstream>
#include <vector>
#include <map>
#include <math.h>
#include <assert.h>
#include <stdint.h>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <ctime>
#include <chrono>
#include <signal.h>
#include <cctype>
#include <clocale>
#include <openssl/md5.h>
#include <string.h>

#ifdef BUILD_FTDI_MODULE
#include "ftdi_device.h"
#endif

#include "file_device.h"
#include "uart_device.h"

#include "cap.h"

#define CMD_RESET          0x00
#define CMD_SET_OFFSET     0x01 
#define CMD_PUSH_MSG_BYTE  0x02
#define CMD_SEL_MSG_LEN    0x03
#define CMD_SEL_SSID_BYTE  0x04
#define CMD_SET_SSID_BYTE  0x05
#define CMD_SET_SSID_LEN   0x06
#define CMD_SEL_MAP_BYTE   0x07
#define CMD_SET_MAP_BYTE   0x08
#define CMD_SET_MAP_LEN    0x09
#define CMD_PUSH_MIC_BYTE  0x0A
#define CMD_SET_CLK_M_VAL  0x0B
#define CMD_SET_CLK_D_VAL  0x0C

#define CMD_WR_REG_LSB     0x0E
#define CMD_WR_REG_ADDR    0x0F

#define CMD_START          0x1F

#define RESP_HIT           0x01   // Found a hit!
#define RESP_FINISHED      0x1F   // All units finished!

#define NUM_DEVS  2  // 2 hashing cracker devices per UART port
#define PARALLEL (NUM_DEVS)

#define CLOCK_FREQ  25

pthread_mutex_t stdlock = PTHREAD_MUTEX_INITIALIZER; 

bool verbose = false;
std::string map;
std::string prefix, postfix;
unsigned char max_chars, max_chars_device;

std::string currtime() {
	std::chrono::system_clock::time_point today = std::chrono::system_clock::now();
	time_t tt = std::chrono::system_clock::to_time_t (today);
	return std::ctime(&tt);
}

// Produce a CMD targeting some cracker with the mentioned payload
uint16_t controlcmd(int cmd, int tgt, uint8_t payload) {
	switch (cmd) {
	case CMD_RESET:
		return 0;
	case CMD_START:
		return ~0;
	default:
		// MSB cmd bit is tgt (2 crackers/device)
		return ((cmd & 0x1F) << 8) | ((tgt & 0x7) << 13) | payload;
	};
}

#define show(x) printf("%02x\n%02x\n", x & 0xFF, x >> 8)

template <typename T>
inline T concat(const T & a, const T & b) {
	T ret;
	ret.insert( ret.end(), a.begin(), a.end());
	ret.insert( ret.end(), b.begin(), b.end());
	return ret;
}

std::vector <uint16_t> setCharMap(std::string map) {
	std::vector <uint16_t> ret;

	// This sets the map RAM
	for (unsigned i = 0; i < map.size(); i++) {
		ret.push_back(controlcmd(CMD_SEL_MAP_BYTE, 0, (unsigned char)i));
		ret.push_back(controlcmd(CMD_SET_MAP_BYTE, 0, (unsigned char)map[i]));
	}
	ret.push_back(controlcmd(CMD_SET_MAP_LEN, 0, map.size()));

	return ret;
}

std::vector <uint16_t> genEssid(const char * essid) {
	std::vector <uint16_t> ret;
	ret.push_back(controlcmd(CMD_SET_SSID_LEN, 0, strlen(essid)));

	char essid_reg[33] = {0};
	strcpy(essid_reg, essid);
	essid_reg[strlen(essid_reg) + 4] = 0x80;

	for (int i = 0; i < 32; i++) {
		ret.push_back(controlcmd(CMD_SEL_SSID_BYTE, 0, i));
		ret.push_back(controlcmd(CMD_SET_SSID_BYTE, 0, essid_reg[i]));
	}

	return ret;
}

int getEAPOL(const t_handshake * hi, char * eapol) {
	// Generate EAPOL register and length too
	memset(eapol, 0, 256);
	memcpy(eapol, hi->eapol, hi->eapol_len);

	// SHA1 padding
	eapol[hi->eapol_len] = 0x80;
	int nblocks = (hi->eapol_len+1+8+63)/64;
	int hsize = 8*(hi->eapol_len + 64); // Due to IPAD!

	eapol[nblocks * 64 - 1] = (hsize >>  0) & 0xFF;
	eapol[nblocks * 64 - 2] = (hsize >>  8) & 0xFF;
	eapol[nblocks * 64 - 3] = (hsize >> 16) & 0xFF;
	eapol[nblocks * 64 - 4] = (hsize >> 24) & 0xFF;

	return nblocks;
}

void genPKE(const t_handshake * hi, unsigned char * pke) {
	// Generate PKE register
	memset(pke, 0, 128);
	memcpy(pke, "Pairwise key expansion", 23);
	if(memcmp(hi->assid, hi->bssid, 6) < 0) {
		memcpy(pke + 23, hi->assid, 6);
		memcpy(pke + 29, hi->bssid, 6);
	}
	else{
		memcpy(pke + 23, hi->bssid, 6);
		memcpy(pke + 29, hi->assid, 6);
	}

	if( memcmp(hi->snonce, hi->anonce, 32) < 0) {
		memcpy(pke + 35, hi->snonce, 32);
		memcpy(pke + 67, hi->anonce, 32);
	} else {
		memcpy(pke + 35, hi->anonce, 32);
		memcpy(pke + 67, hi->snonce, 32);
	}
	pke[99] = 0x00; // Interation number
	pke[100] = 0x80; // SHA1 padding
	pke[126] = 0x05;
	pke[127] = 0x20;
}

// State select
#define UC_SEL_CNT   0x00
#define UC_SEL_OUT   0x80

// Write back
#define UC_NO_WB     0x00
#define UC_WB_80     0x40
#define UC_WB_00     0x60

// Msg selector
#define UC_SEL_SCRATCH_ZERO  (0x08 | 0x00)
#define UC_SEL_SCRATCH_PAD   (0x08 | 0x04)

// Xor!
#define UC_XOR_36    0x02
#define UC_XOR_5C    0x03

// Reg
#define UC_SEL_REG(r)   ((r) & 0x7)

// Nohash please
#define UC_NOHASH   0x10

void genUcode(char * ucode, int n_eapol_blocks) {
	// Work with PMK and PKE
	std::vector <unsigned char> uc;

	// PTK stages (1 to 5)
	uc.push_back(UC_SEL_CNT | UC_NO_WB | UC_SEL_SCRATCH_ZERO | UC_XOR_36);
	uc.push_back(UC_SEL_OUT | UC_NO_WB | UC_SEL_REG(0));
	uc.push_back(UC_SEL_OUT | UC_NO_WB | UC_SEL_REG(1));

	uc.push_back(UC_SEL_CNT | UC_WB_80 | UC_SEL_SCRATCH_ZERO | UC_XOR_5C);
	uc.push_back(UC_SEL_OUT | UC_NO_WB | UC_SEL_SCRATCH_PAD);

	uc.push_back(UC_NOHASH | UC_WB_00);

	// MIC stages
	uc.push_back(UC_SEL_CNT | UC_NO_WB | UC_SEL_SCRATCH_ZERO | UC_XOR_36);

	for (int i = 0; i < n_eapol_blocks; i++)
		uc.push_back(UC_SEL_OUT | UC_NO_WB | UC_SEL_REG(2+i));

	uc.push_back(UC_SEL_CNT | UC_WB_80 | UC_SEL_SCRATCH_ZERO | UC_XOR_5C);
	uc.push_back(UC_SEL_OUT | UC_NO_WB | UC_SEL_SCRATCH_PAD);

	while (uc.size() < 16)
		uc.push_back(UC_NOHASH);

	memcpy(ucode, &uc[0], 16);
}

// Convert sequence id in password (seq ids age generated using generalized gray code)
static std::string hit2pwd(unsigned cid, uint64_t n, std::string charset, int numchars, int numchars_dev) {
	int charlen = charset.size();
	std::vector<char> res;

	for (unsigned i = 0; i < numchars_dev; i++) {
		int c = n % charlen;
		if ((n / charlen) % 2 == 0)
			res.push_back(charset[c]);
		else
			res.push_back(charset[charlen - c - 1]);

		n /= charlen;
	}

	std::string ress;
	for (auto c: res)
		ress = ress + c;

	// Calculate device postfix
	std::string worker_chunk;
	for (int i = 0; i < numchars - numchars_dev; i++) {
		int c = cid % charset.size();
		cid = cid / charset.size();
		worker_chunk += charset[c];
	}

	return ress + worker_chunk;
}

std::vector <uint16_t> RamFill(const t_handshake * hi) {
	std::vector <uint16_t> ret;

	char eapol_pke[512];

	genPKE(hi, (unsigned char *)&eapol_pke[0]);
	int nb = getEAPOL(hi, &eapol_pke[128]);

	// Ucode generation
	char ucode[16];
	genUcode(ucode, nb);

	// Fill rams
	for (int i = 0; i < 512; i += 4) {
		ret.push_back(controlcmd(CMD_WR_REG_LSB, 0, eapol_pke[i+0]));
		ret.push_back(controlcmd(CMD_WR_REG_LSB, 0, eapol_pke[i+1]));
		ret.push_back(controlcmd(CMD_WR_REG_LSB, 0, eapol_pke[i+2]));
		ret.push_back(controlcmd(CMD_WR_REG_LSB, 0, eapol_pke[i+3]));

		ret.push_back(controlcmd(CMD_WR_REG_ADDR, 0, i/4));
	}
	for (int i = 0; i < 16; i++) {
		ret.push_back(controlcmd(CMD_WR_REG_LSB, 0, ucode[i]));
		ret.push_back(controlcmd(CMD_WR_REG_ADDR, 0, i | 0x80));
	}

	return ret;
}

std::vector <uint16_t> getMIC(const t_handshake * hi) {
	std::vector <uint16_t> ret;

	for (int i = 0; i < 16; i++)
		ret.push_back(controlcmd(CMD_PUSH_MIC_BYTE, 0, hi->mic[i]));

	return ret;
}


std::vector <uint16_t> generateInitialMessage(unsigned cid, unsigned int map_id) {

	std::vector <uint16_t> ret;

	// Initial & base message (16 bytes!)
	unsigned int length = prefix.size() + max_chars + postfix.size();
	assert(length < 16);
	unsigned char msg[16];
	for (unsigned i = 0; i < 16; i++) {
		if (i < prefix.size())
			msg[i] = prefix[i];
		else if (i < prefix.size() + max_chars - 1)
			msg[i] = map[0];
		else if (i == prefix.size() + max_chars - 1)
			msg[i] = (map_id < map.size()) ? map[map_id] : 0;
		else if (i < prefix.size() + max_chars + postfix.size())
			msg[i] = postfix[i - prefix.size() - max_chars];
		else
			msg[i] = 0;
		// Password length doesn't really care! Cause we use HMAC! (well as long as it's <= 64 bytes)
		// No need to zero pad or 0x80!

		ret.push_back(controlcmd(CMD_PUSH_MSG_BYTE, cid, msg[i]));
	}

	if (verbose) {
		pthread_mutex_lock(&stdlock);
		std::cerr << "Initial message for pipe " << (map_id % PARALLEL) << " ";
		for (unsigned i = 0; i < 16; i++)
			fprintf(stderr, "%02x", (int)msg[i]);
		std::cerr << std::endl;
		pthread_mutex_unlock(&stdlock);
	}

	return ret;
}

unsigned char brev(unsigned char x) {
    x = (((x & 0xaa) >> 1) | ((x & 0x55) << 1));
    x = (((x & 0xcc) >> 2) | ((x & 0x33) << 2));
    x = (((x & 0xf0) >> 4) | ((x & 0x0f) << 4));
	return x;
}

void calcFreq(unsigned int desired_freq, unsigned char freqp[2]) {
	float bestf = 0;
	unsigned min_M = (400  / CLOCK_FREQ) + 1;
	unsigned max_M = (1000 / CLOCK_FREQ);
	for (unsigned int M = min_M; M < max_M; M++) {
		// Calculate D for this M
		unsigned int D = (CLOCK_FREQ * M) / float(desired_freq) - 1;
		while (++D < M*20) {
			float real_freq = (CLOCK_FREQ * M) / float(D);

			if (bestf < real_freq and real_freq <= desired_freq) {
				bestf = real_freq;
				freqp[0] = M;
				freqp[1] = D; // reversed!!!
			}
		}
	}
	std::cerr << "Will run at " << bestf << " MHz (M: " << (int)freqp[0] << " D: " << (int)freqp[1] << ")" << std::endl;

	// Decrement and reverse!
	for (int i = 0; i < 2; i++) {
		freqp[i]--;
		//freqp[i] = brev(freqp[i]);
	}
}

int fd;

int config_port() {
	struct termios tp;
	int ret;

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

	return ret;
}

void icarus_init(const char * device) {
	int ret;
 
	fd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		perror("open serial port");
		exit(-1);
	}
 
	ret = fcntl(fd, F_SETFL, O_RDWR);
	if (ret < 0) {
		perror("fcntl");
		exit(-1);
	}

	config_port();
}

void testfile_init(const char * filen) {
	fd = open(filen, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR);
	if (fd < 0) {
		perror("open file output port");
		exit(-1);
	}
}

std::string cleanmac (std::string inp) {
	std::string ret;
	for (auto cc: inp) {
		auto c = std::tolower(cc);

		if ((c >= '0' && c <= '9') ||
		    (c >= 'a' && c <= 'f'))
		ret += c;
	}
	return ret;
}

std::vector<Device*> devices;

void exit_driver(int) {
	// Make sure to reset the thing before leaving 
	// otherwise it won't stop working!
	std::cerr << "Reseting FPGAs and exiting!" << std::endl;
	for (auto dev: devices) {
		uint16_t code = controlcmd(CMD_RESET, 0, 0);
		dev->write(&code, sizeof(code));
	}
	exit(0);
}

void * worker(void * data) {
	Device * dev = (Device*)data;

	// Work sharing
	unsigned start = PARALLEL * dev->dnum;
	unsigned step  = PARALLEL * Device::device_counter;
	unsigned maxd  = map.size();

	pthread_mutex_lock(&stdlock);
	std::cerr << "Started device thread " << dev->dnum << " (" << start << ", " << step << ", " << maxd << ")" << std::endl;
	pthread_mutex_unlock(&stdlock);

	// Now keep launching jobs once they are finished
	for (unsigned i = start; i < maxd; i += step) {
		std::vector <uint16_t> program_seq_pipe;

		// Reset device!
		program_seq_pipe.push_back(controlcmd(CMD_RESET, 0, 0));

		for (unsigned n = 0; n < PARALLEL; n++)
			program_seq_pipe = concat(program_seq_pipe, generateInitialMessage(n, i + n));

		// Start the show
		program_seq_pipe.push_back(controlcmd(CMD_START, 0, 0));

		// Send work!
		dev->write(&program_seq_pipe[0], program_seq_pipe.size()*2);

		// Wait for responses
		int next = NUM_DEVS;
		while (next > 0) {
			unsigned char response[5];
			int r = 0;
			while (r < 5) {
				int res = dev->read(&response[r], 5 - r);
				if (res > 0)
					r += res;
				if (res <= 0)
					std::cerr << "Error reading serial port!" << std::endl;
			}

			uint64_t payload = 0;
			for (int i = 3; i >= 0; i--) {
				payload = (payload << 8ULL) | response[i];
			}

			unsigned char resp_cmd = response[4] & 0x1F;
			unsigned int  resp_cracker = (response[4] >> 5) & 0x7;

			pthread_mutex_lock(&stdlock);
			switch (resp_cmd) {
			case RESP_HIT: {
				std::string plaintext = prefix + hit2pwd(resp_cracker + i, payload, map, max_chars, max_chars_device) + postfix;
				std::cerr << currtime();
				std::cerr << "Got a password match " << plaintext << " (" << payload << ") [dev " << resp_cracker << "]" << std::endl;
				} break;
			case RESP_FINISHED:
				std::cerr << currtime();
				std::cerr << "Batch finished! (" << dev->dnum << ", " << resp_cracker << ") " << payload << std::endl;
				next--;
				break;
			default:
				std::cerr << currtime();
				std::cerr << "Malformed response!!!" << std::endl;
				printf("%02x %02x %02x %02x %02x\n",
					response[0],response[1],response[2],response[3], response[4]);
				break;
			}
			pthread_mutex_unlock(&stdlock);
		}
	}
}

int main(int argc, char ** argv) {
	signal(SIGINT, exit_driver);

	if (argc < 5) {
		std::cerr << "Missing arguments! Usage:" << std::endl;
		std::cerr << argv[0] << " charset num-chars bssid dump.cap [-f freq (Mhz)] [-v] [-pre prefix-salt] [-post postfix-salt] [-test file.txt]" << std::endl;
		exit(1);
	}
	std::string charset = argv[1];
	max_chars = atoi(argv[2]);
	std::string bssid = cleanmac(argv[3]);
	std::string dumpfile = argv[4];
	std::string testfile, device_path;
	max_chars_device = max_chars - 1;
	unsigned int desired_freq = 100;

	for (unsigned p = 5; p < argc; p++) {
		if (std::string(argv[p]) == "-pre")
			prefix = std::string(argv[p+1]);
		if (std::string(argv[p]) == "-post")
			postfix = std::string(argv[p+1]);
		if (std::string(argv[p]) == "-test")
			testfile = std::string(argv[p+1]);
		if (std::string(argv[p]) == "-dev")
			device_path = std::string(argv[p+1]);
		if (std::string(argv[p]) == "-v")
			verbose = true;
		if (std::string(argv[p]) == "-f")
			desired_freq = atoi(argv[p+1]);
	}

	if (prefix.size() + max_chars + postfix.size() >= 16) {
		std::cerr << "Password is too long (prefix+pass+postfix < 16 chars)" << std::endl;
		exit(1);
	}

	unsigned char freqp[2];
	calcFreq(desired_freq, freqp);

	// Read pcap file and process it!
	t_handshake hs_info;
	int preadres = parse_pcap(dumpfile.c_str(), &hs_info, bssid);
	if (!preadres)
		std::cerr << "Could not parse and find the bssid in the cap file" << std::endl;

	// Expand the charset
	// Examples are: a-zA-Z0-9 or abcde0-9
	for (unsigned i = 0; i < charset.size(); i++) {
		// Escape dash with backslash
		if (i+1 < charset.size() and charset[i] == '\\' and charset[i+1] == '-') {
			map += '-';
			i++;
		}
		else if (i+2 < charset.size() and charset[i+1] == '-') {
			for (char c = charset[i]; c <= charset[i+2]; c++) {
				map += c;
			}
			i += 2;
		}
		else
			map += charset[i];
	}
	unsigned long long combinations = pow(map.size(), (int)max_chars);
	double etime = combinations / (100e6 / 8192.0f) / 3600.0f;
	std::cerr << "Charset to test " << map << " (" << map.size() << " characters)" << std::endl;
	std::cerr << "Testing " << (int)max_chars << " characters, this is " << combinations << " combinations (" << etime << " hours on 1 FPGA at 20KH/s)" << std::endl;

	// Do initial programming
	if (testfile.size())
		devices.push_back(new FileDevice(testfile.c_str()));
	else if (device_path == "ftdi")
		#ifdef BUILD_FTDI_MODULE
		devices = FTDIDevice::getAllDevs();
		#else
		std::cerr << "No FTDI support built in!" << std::endl;
		#endif
	else
		devices.push_back(new UARTDevice(device_path.c_str()));
	std::cerr << devices.size() << " device(s) found!" << std::endl;

	// Generate init sequence
	std::vector <uint16_t> program_seq;

	program_seq.push_back(controlcmd(CMD_RESET, 0, 0));

	// Setup frequency values (set 100Mhz for now, 5/5 at 500Mhz PLL freq)
	std::cout << (int)freqp[0] << " " << (int)freqp[1] << std::endl;
	program_seq.push_back(controlcmd(CMD_SET_CLK_M_VAL, 0, freqp[0]));
	program_seq.push_back(controlcmd(CMD_SET_CLK_D_VAL, 0, freqp[1]));

	program_seq.push_back(controlcmd(CMD_RESET, 0, 0));

	for (auto dev: devices) {
		dev->flush();
		dev->write(&program_seq[0], program_seq.size()*2);
	}
	sleep(2);

	// Setup wifi ESSID
	program_seq = genEssid(hs_info.essid);

	// Program PKE + EAPOL + ucode
	program_seq = concat(program_seq, RamFill(&hs_info));

	// Setup MIC hash
	program_seq = concat(program_seq, getMIC(&hs_info));

	// Setup character map (fixed for every position for now)
	program_seq = concat(program_seq, setCharMap(map));

	// Set offset to the size of the prefix
	program_seq.push_back(controlcmd(CMD_SET_OFFSET, 0, prefix.size()));
	// Num chars to bruteforce! (Chars - 1)
	program_seq.push_back(controlcmd(CMD_SEL_MSG_LEN, 0, max_chars_device));

	for (auto dev: devices) {
		dev->flush();
		dev->write(&program_seq[0], program_seq.size()*2);
	}

	std::cerr << "Setup done, starting to bruteforce!" << std::endl;


	// Setup worker threads
	int num_workers = devices.size();

	pthread_t tpool[num_workers];
	for (unsigned i = 0; i < devices.size(); i++)
	    pthread_create (&tpool[i], NULL, worker, (void *)devices[i]);

	for (unsigned i = 0; i < devices.size(); i++)
	    pthread_join (tpool[i], NULL);

	// Reset device!
	for (auto dev: devices) {
		uint16_t code = controlcmd(CMD_RESET, 0, 0);
		dev->write(&code, sizeof(code));
	}
}

